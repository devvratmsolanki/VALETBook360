package com.valet.transaction.security;

import com.valet.transaction.config.JwtProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

/**
 * Validates the stateless ACCESS JWT issued by the auth-service. This service
 * is a pure <em>resource server</em>: it verifies signature + expiry + the
 * {@code typ=access} claim and extracts the shared identity/tenancy claims
 * ({@code sub}, {@code role}, {@code companyId}, {@code locationId}). Signed
 * HS256 with the secret shared with the auth-service.
 *
 * <p>Deliberately does <strong>not</strong> require the {@code iss} claim: the
 * cross-service contract pins only the secret + the five claims, so we accept
 * any correctly-signed access token regardless of issuer. (The auth-service
 * currently stamps {@code iss=valet-auth}; relaxing it here keeps us decoupled
 * from that detail.)</p>
 */
@Service
public class JwtService {

    public static final String TYP_ACCESS = "access";

    private final SecretKey key;

    public JwtService(JwtProperties props) {
        String secret = props.getSecret();
        if (secret == null || secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException(
                    "valet.jwt.secret (JWT_SECRET) must be set and at least 32 bytes for HS256");
        }
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * Parse + verify signature and expiry. Throws {@link JwtException} on any
     * problem (expired, tampered, wrong type) — the filter maps that to an
     * unauthenticated context.
     */
    public AuthPrincipal parse(String jwt) {
        Claims claims = Jwts.parser()
                .verifyWith(key)
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

        if (role == null) {
            throw new JwtException("Missing role claim");
        }

        return new AuthPrincipal(userId, role, companyId, locationId, email, name);
    }

    private static UUID optionalUuid(Claims claims, String key) {
        String v = claims.get(key, String.class);
        return v == null ? null : UUID.fromString(v);
    }
}
