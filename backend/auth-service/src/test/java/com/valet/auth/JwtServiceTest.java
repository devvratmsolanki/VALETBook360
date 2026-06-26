package com.valet.auth;

import com.valet.auth.config.JwtProperties;
import com.valet.auth.domain.Role;
import com.valet.auth.domain.User;
import com.valet.auth.security.AuthPrincipal;
import com.valet.auth.security.JwtService;
import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Pure unit tests for JWT issuance + validation. No Spring context.
 */
class JwtServiceTest {

    private JwtService serviceWith(String secret) {
        JwtProperties props = new JwtProperties();
        props.setSecret(secret);
        props.setIssuer("valet-auth-test");
        props.setAccessTtlSeconds(900);
        return new JwtService(props);
    }

    private User sampleUser(UUID companyId, UUID locationId) {
        return new User(
                UUID.randomUUID(),
                "driver@acme.test",
                "$2a$12$hash",
                Role.DRIVER,
                companyId,
                locationId,
                "Test Driver",
                true
        );
    }

    @Test
    void issuesAndParsesAllClaims() {
        JwtService svc = serviceWith("a-very-strong-test-secret-of-32+bytes!!");
        UUID companyId = UUID.randomUUID();
        UUID locationId = UUID.randomUUID();
        User user = sampleUser(companyId, locationId);

        JwtService.IssuedToken issued = svc.issueAccessToken(user);
        AuthPrincipal principal = svc.parse(issued.token());

        assertThat(principal.userId()).isEqualTo(user.getId());
        // Wire/JWT role is the lowercase contract form.
        assertThat(principal.role()).isEqualTo("driver");
        assertThat(principal.companyId()).isEqualTo(companyId);
        assertThat(principal.locationId()).isEqualTo(locationId);
        assertThat(principal.email()).isEqualTo("driver@acme.test");
        assertThat(principal.name()).isEqualTo("Test Driver");
        assertThat(issued.expiresInSeconds()).isEqualTo(900);
    }

    @Test
    void omitsTenancyClaimsForAdminWithNoTenant() {
        JwtService svc = serviceWith("a-very-strong-test-secret-of-32+bytes!!");
        User admin = new User(UUID.randomUUID(), "admin@valet.test", "$2a$12$hash",
                Role.ADMIN, null, null, "Root Admin", true);

        AuthPrincipal principal = svc.parse(svc.issueAccessToken(admin).token());

        assertThat(principal.role()).isEqualTo("admin");
        assertThat(principal.companyId()).isNull();
        assertThat(principal.locationId()).isNull();
    }

    @Test
    void rejectsTamperedSignature() {
        JwtService signer = serviceWith("a-very-strong-test-secret-of-32+bytes!!");
        JwtService attacker = serviceWith("a-DIFFERENT-strong-secret-of-32+bytes!");

        String token = signer.issueAccessToken(sampleUser(UUID.randomUUID(), null)).token();

        assertThatThrownBy(() -> attacker.parse(token)).isInstanceOf(JwtException.class);
    }

    @Test
    void rejectsSecretShorterThan32Bytes() {
        assertThatThrownBy(() -> serviceWith("too-short"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("32 bytes");
    }

    /**
     * Guards the mandatory seed (V2__seed_demo_users.sql): the STATIC BCrypt
     * hashes baked into the migration must verify against the production encoder
     * for the exact contract passwords. If this fails, the parallel slice's demo
     * login is broken and the seed hashes must be regenerated.
     */
    @Test
    void seedBcryptHashesVerifyAgainstContractPasswords() {
        BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
        String driverHash = "$2b$12$ZeaTahDl73HPa4GYE7P6q.AHs8vaIrzug4QKl8hM3q6RNLymEBwSq";
        String adminHash = "$2b$12$zUF4VzPbtv5Q1uohW/T7j.V1HV7PH1dWLwt16YurXMSS4b8OlhHu6";
        assertThat(encoder.matches("Driver123", driverHash)).isTrue();
        assertThat(encoder.matches("Admin123", adminHash)).isTrue();
    }

    @Test
    void rejectsGarbageToken() {
        JwtService svc = serviceWith("a-very-strong-test-secret-of-32+bytes!!");
        assertThatThrownBy(() -> svc.parse("not.a.jwt"))
                .isInstanceOfAny(JwtException.class, IllegalArgumentException.class);
    }
}
