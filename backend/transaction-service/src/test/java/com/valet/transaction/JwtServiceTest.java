package com.valet.transaction;

import com.valet.transaction.config.JwtProperties;
import com.valet.transaction.security.AuthPrincipal;
import com.valet.transaction.security.JwtService;
import com.valet.transaction.support.TestTokens;
import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Pure unit tests for the resource-server JWT validation. No Spring context.
 * Verifies the contract: HS256, shared secret, claims sub/role/companyId/
 * locationId, typ=access required, and signature/expiry rejection.
 */
class JwtServiceTest {

    private JwtService service() {
        JwtProperties props = new JwtProperties();
        props.setSecret(TestTokens.SECRET);
        return new JwtService(props);
    }

    @Test
    void parsesAllSharedClaimsFromAValidDriverToken() {
        UUID driver = UUID.fromString("11111111-1111-1111-1111-111111111111");
        UUID company = UUID.fromString("22222222-2222-2222-2222-222222222222");
        UUID location = UUID.fromString("33333333-3333-3333-3333-333333333333");

        AuthPrincipal p = service().parse(
                TestTokens.driverAccessToken(driver, company, location));

        assertThat(p.userId()).isEqualTo(driver);
        assertThat(p.driverId()).isEqualTo(driver);   // driverId == sub
        assertThat(p.role()).isEqualTo("driver");
        assertThat(p.isDriver()).isTrue();
        assertThat(p.companyId()).isEqualTo(company);
        assertThat(p.locationId()).isEqualTo(location);
    }

    @Test
    void rejectsNonAccessTyp() {
        assertThatThrownBy(() -> service().parse(TestTokens.wrongTypToken(UUID.randomUUID())))
                .isInstanceOf(JwtException.class)
                .hasMessageContaining("access");
    }

    @Test
    void rejectsTokenSignedWithWrongSecret() {
        assertThatThrownBy(() -> service().parse(TestTokens.forgedWithWrongSecret(UUID.randomUUID())))
                .isInstanceOf(JwtException.class);
    }

    @Test
    void rejectsExpiredToken() {
        assertThatThrownBy(() -> service().parse(TestTokens.expiredAccessToken(UUID.randomUUID())))
                .isInstanceOf(JwtException.class);
    }

    @Test
    void rejectsGarbage() {
        assertThatThrownBy(() -> service().parse("not.a.jwt"))
                .isInstanceOfAny(JwtException.class, IllegalArgumentException.class);
    }

    @Test
    void rejectsSecretShorterThan32Bytes() {
        JwtProperties props = new JwtProperties();
        props.setSecret("too-short");
        assertThatThrownBy(() -> new JwtService(props))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("32 bytes");
    }
}
