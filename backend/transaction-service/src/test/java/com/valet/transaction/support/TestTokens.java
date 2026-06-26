package com.valet.transaction.support;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

/**
 * Forges correctly-signed HS256 access tokens for tests — exactly what the
 * auth-service would mint, signed with the same shared secret. This lets the
 * resource-server tests exercise the real validation path without standing up
 * the auth-service.
 */
public final class TestTokens {

    /** Must be >= 32 bytes; shared across the test config + forging here. */
    public static final String SECRET = "test-shared-hs256-secret-at-least-32-bytes!!";

    private TestTokens() {
    }

    private static SecretKey key() {
        return Keys.hmacShaKeyFor(SECRET.getBytes(StandardCharsets.UTF_8));
    }

    /** A valid driver access token (typ=access) for the given driver/company/location. */
    public static String driverAccessToken(UUID driverId, UUID companyId, UUID locationId) {
        return base(driverId, "driver", companyId, locationId)
                .claim("typ", "access")
                .signWith(key())
                .compact();
    }

    /** A token whose typ is NOT access (should be rejected by the resource server). */
    public static String wrongTypToken(UUID driverId) {
        return base(driverId, "driver", null, null)
                .claim("typ", "refresh")
                .signWith(key())
                .compact();
    }

    /** A correctly-shaped token signed with the WRONG secret (tampered). */
    public static String forgedWithWrongSecret(UUID driverId) {
        SecretKey wrong = Keys.hmacShaKeyFor(
                "a-totally-different-secret-of-32-plus-bytes!!".getBytes(StandardCharsets.UTF_8));
        return base(driverId, "driver", null, null)
                .claim("typ", "access")
                .signWith(wrong)
                .compact();
    }

    /** An expired (but correctly signed) access token. */
    public static String expiredAccessToken(UUID driverId) {
        Instant past = Instant.now().minusSeconds(3600);
        return Jwts.builder()
                .subject(driverId.toString())
                .claim("role", "driver")
                .claim("typ", "access")
                .issuedAt(Date.from(past.minusSeconds(900)))
                .expiration(Date.from(past))
                .signWith(key())
                .compact();
    }

    /** A token with role=valet (not a driver). */
    public static String valetAccessToken(UUID userId, UUID companyId, UUID locationId) {
        return base(userId, "valet", companyId, locationId)
                .claim("typ", "access")
                .signWith(key())
                .compact();
    }

    /** A token with role=manager (the DB role behind the UI "company" operator). */
    public static String managerAccessToken(UUID userId, UUID companyId, UUID locationId) {
        return base(userId, "manager", companyId, locationId)
                .claim("typ", "access")
                .signWith(key())
                .compact();
    }

    /** A generic operator access token for any role (valet/manager/admin). */
    public static String operatorAccessToken(UUID userId, String role, UUID companyId, UUID locationId) {
        return base(userId, role, companyId, locationId)
                .claim("typ", "access")
                .signWith(key())
                .compact();
    }

    private static io.jsonwebtoken.JwtBuilder base(UUID sub, String role, UUID companyId, UUID locationId) {
        Instant now = Instant.now();
        var b = Jwts.builder()
                .issuer("valet-auth")
                .subject(sub.toString())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plusSeconds(900)))
                .claim("role", role)
                .claim("email", "demo@valet.test")
                .claim("name", "Demo");
        if (companyId != null) {
            b.claim("companyId", companyId.toString());
        }
        if (locationId != null) {
            b.claim("locationId", locationId.toString());
        }
        return b;
    }
}
