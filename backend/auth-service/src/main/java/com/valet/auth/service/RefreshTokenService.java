package com.valet.auth.service;

import com.valet.auth.config.JwtProperties;
import com.valet.auth.domain.RefreshToken;
import com.valet.auth.repository.RefreshTokenRepository;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;

/**
 * Issues, hashes, rotates and revokes opaque refresh tokens. Only the SHA-256
 * hash is ever persisted. Rotation + reuse detection live here.
 */
@Service
public class RefreshTokenService {

    private final RefreshTokenRepository repo;
    private final JwtProperties props;
    private final SecureRandom random = new SecureRandom();
    // Self-reference (lazy, breaks the cycle) so the REQUIRES_NEW revoke goes
    // through the transactional proxy rather than an intra-bean call.
    private final ObjectProvider<RefreshTokenService> self;

    public RefreshTokenService(RefreshTokenRepository repo, JwtProperties props,
                               ObjectProvider<RefreshTokenService> self) {
        this.repo = repo;
        this.props = props;
        this.self = self;
    }

    /** Mint a new opaque refresh token, store its hash, return the raw value. */
    @Transactional
    public String issue(UUID userId) {
        String raw = randomToken();
        Instant expires = Instant.now().plusSeconds(props.getRefreshTtlSeconds());
        repo.save(new RefreshToken(UUID.randomUUID(), userId, sha256(raw), expires));
        return raw;
    }

    /**
     * Rotate: validate the presented raw token, revoke it, and issue a fresh one.
     * Returns the owning userId + the new raw token.
     *
     * <p>Reuse detection: if the presented token exists but is already revoked,
     * we treat it as a stolen/replayed token and revoke the entire family for
     * that user, forcing a full re-login.</p>
     */
    @Transactional
    public Rotated rotate(String rawToken) {
        String hash = sha256(rawToken);
        RefreshToken existing = repo.findByTokenHash(hash).orElse(null);

        if (existing == null) {
            throw new InvalidRefreshTokenException();
        }
        if (existing.isRevoked()) {
            // Replay of an already-rotated token -> assume compromise. The
            // family revocation MUST commit even though we then throw, so it runs
            // in its own (REQUIRES_NEW) transaction; otherwise the throw below
            // would roll the revoke back and leave the stolen family alive.
            self.getObject().revokeFamilyOnReuse(existing.getUserId());
            throw new InvalidRefreshTokenException();
        }
        if (!existing.isActive(Instant.now())) {
            throw new InvalidRefreshTokenException();
        }

        existing.revoke();
        repo.save(existing);

        String newRaw = issue(existing.getUserId());
        return new Rotated(existing.getUserId(), newRaw);
    }

    /**
     * Revoke every active token for a user in a NEW transaction that commits
     * independently of the caller. Used by reuse detection, where the caller
     * throws right after to signal 401 — that throw must not undo the revoke.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void revokeFamilyOnReuse(UUID userId) {
        repo.revokeAllForUser(userId);
    }

    @Transactional
    public void revokeOne(String rawToken) {
        repo.findByTokenHash(sha256(rawToken)).ifPresent(t -> {
            t.revoke();
            repo.save(t);
        });
    }

    @Transactional
    public void revokeAll(UUID userId) {
        repo.revokeAllForUser(userId);
    }

    private String randomToken() {
        byte[] bytes = new byte[48]; // 384 bits of entropy
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static String sha256(String value) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }

    public record Rotated(UUID userId, String rawToken) {
    }

    /** Internal marker; mapped to 401 by the AuthService caller. */
    public static class InvalidRefreshTokenException extends RuntimeException {
    }
}
