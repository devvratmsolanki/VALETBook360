package com.valet.auth.security;

import com.valet.auth.config.JwtProperties;
import com.valet.auth.domain.User;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

/**
 * Issues and validates the stateless ACCESS JWT. Claims carried (the shared
 * contract every downstream service reads): sub=userId, role, companyId,
 * locationId, email, name, plus typ=access. Signed HS256 with a shared secret.
 *
 * <p>Refresh tokens are NOT JWTs — they are opaque, server-stored handles
 * (see {@code RefreshToken}) so they can be rotated/revoked.</p>
 */
@Service
public class JwtService {

    public static final String TYP_ACCESS = "access";

    private final JwtProperties props;
    private final SecretKey key;

    public JwtService(JwtProperties props) {
        this.props = props;
        String secret = props.getSecret();
        if (secret == null || secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException(
                    "auth.jwt.secret (env JWT_SECRET) must be set and at least 32 bytes for HS256");
        }
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }

    /** Build a signed access token for the given user. */
    public IssuedToken issueAccessToken(User user) {
        Instant now = Instant.now();
        Instant exp = now.plusSeconds(props.getAccessTtlSeconds());

        var builder = Jwts.builder()
                .issuer(props.getIssuer())
                .subject(user.getId().toString())
                .issuedAt(Date.from(now))
                .expiration(Date.from(exp))
                .claim("typ", TYP_ACCESS)
                .claim("role", user.getRole().wire())
                .claim("email", user.getEmail())
                .claim("name", user.getName());

        // Tenancy claims — null-safe; admins may have neither.
        if (user.getCompanyId() != null) {
            builder.claim("companyId", user.getCompanyId().toString());
        }
        if (user.getLocationId() != null) {
            builder.claim("locationId", user.getLocationId().toString());
        }

        String jwt = builder.signWith(key).compact();
        return new IssuedToken(jwt, exp, props.getAccessTtlSeconds());
    }

    /**
     * Parse + verify signature and expiry. Throws {@link JwtException} on any
     * problem (expired, tampered, wrong type) — callers map to 401.
     */
    public AuthPrincipal parse(String jwt) {
        Claims claims = Jwts.parser()
                .verifyWith(key)
                .requireIssuer(props.getIssuer())
                .build()
                .parseSignedClaims(jwt)
                .getPayload();

        if (!TYP_ACCESS.equals(claims.get("typ", String.class))) {
            throw new JwtException("Not an access token");
        }

        UUID userId = UUID.fromString(claims.getSubject());
        String role = claims.get("role", String.class);
        UUID companyId = optionalUuid(claims, "companyId");
        UUID locationId = optionalUuid(claims, "locationId");
        String email = claims.get("email", String.class);
        String name = claims.get("name", String.class);

        return new AuthPrincipal(userId, role, companyId, locationId, email, name);
    }

    private static UUID optionalUuid(Claims claims, String key) {
        String v = claims.get(key, String.class);
        return v == null ? null : UUID.fromString(v);
    }

    /** Value object for a freshly minted token + its expiry metadata. */
    public record IssuedToken(String token, Instant expiresAt, long expiresInSeconds) {
    }
}
