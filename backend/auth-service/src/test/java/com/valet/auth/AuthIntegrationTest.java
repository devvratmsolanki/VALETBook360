package com.valet.auth;

import com.valet.auth.domain.Company;
import com.valet.auth.domain.Role;
import com.valet.auth.domain.User;
import com.valet.auth.repository.CompanyRepository;
import com.valet.auth.repository.LocationRepository;
import com.valet.auth.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.web.client.NoOpResponseErrorHandler;
import org.springframework.web.client.RestTemplate;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Full-stack slice: boots the app against a real Postgres (Testcontainers),
 * runs Flyway, and exercises the register -> login -> me flow plus the tenancy
 * guard rails. Verifies the legacy role + multi-tenant rules are preserved.
 *
 * <p>If Docker is unavailable in the build environment, this test is skipped at
 * the container-start boundary by Testcontainers; the JwtServiceTest still runs.</p>
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class AuthIntegrationTest {

    @Container
    static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:16-alpine")
                    .withDatabaseName("valet_auth")
                    .withUsername("valet")
                    .withPassword("valet");

    // Redis backs the login rate-limit + account-lockout counters. The guards
    // are exercised by the *Limited / *Locked tests below.
    @Container
    static final GenericContainer<?> REDIS =
            new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

    @DynamicPropertySource
    static void datasourceProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url",
                () -> POSTGRES.getJdbcUrl() + "&stringtype=unspecified");
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("auth.jwt.secret", () -> "integration-test-secret-which-is-32+bytes!!");
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
        // Thresholds for the abuse-control tests. The per-IP failure limit is set
        // low enough for the dedicated IP-ceiling test to be fast (15 failures
        // trips it), yet high enough that ordinary login tests (a handful of
        // requests each) never trip it. The per-IP counter only counts FAILURES,
        // so successful logins in other tests don't inflate it. Redis is flushed
        // in @BeforeEach so counters never leak between tests.
        registry.add("auth.login-guard.ip-max-attempts", () -> 15);
        registry.add("auth.login-guard.ip-window-seconds", () -> 60);
        registry.add("auth.login-guard.account-max-failures", () -> 4);
        registry.add("auth.login-guard.account-window-seconds", () -> 60);
        registry.add("auth.login-guard.account-lock-seconds", () -> 60);
    }

    @LocalServerPort
    int port;

    @Autowired
    TestRestTemplate rest;

    /**
     * A RestTemplate backed by Apache HttpClient 5 that can read 4xx/5xx response
     * bodies from POST endpoints. Java's built-in HttpURLConnection intercepts 401
     * responses and throws HttpRetryException("cannot retry due to server
     * authentication, in streaming mode") before Spring can read the body.
     * Apache HttpComponents does not perform this interception — it passes the
     * raw response to Spring regardless of status code.
     */
    private RestTemplate rawRest;

    @Autowired
    UserRepository users;

    @Autowired
    CompanyRepository companies;

    @Autowired
    LocationRepository locations;

    @Autowired
    PasswordEncoder encoder;

    @Autowired
    org.springframework.data.redis.core.StringRedisTemplate redis;

    private UUID companyA;
    private UUID companyB;

    @BeforeEach
    void seed() {
        // Apache HttpClient 5 does not intercept 401 responses like JDK's
        // HttpURLConnection does. This lets tests assert on the error body.
        rawRest = new RestTemplate(new HttpComponentsClientHttpRequestFactory());
        rawRest.setErrorHandler(new NoOpResponseErrorHandler());
        // Wipe rate-limit + lockout counters so abuse-control state never leaks
        // between tests (all requests originate from loopback / shared emails).
        redis.getConnectionFactory().getConnection().serverCommands().flushAll();
        // FK-safe wipe order (users -> locations -> companies): users.company_id
        // and users.location_id now have FKs (V4), so users must go first.
        users.deleteAll();
        locations.deleteAll();
        companies.deleteAll();
        companyA = UUID.randomUUID();
        companyB = UUID.randomUUID();
        // Parent company rows for the FK on users.company_id (added in V4). Without
        // these the seeded manager/valet inserts below would violate fk_users_company.
        companies.save(new Company(companyA, "Acme", "Acme Owner", null, "owner@acme.test"));
        companies.save(new Company(companyB, "Globex", "Globex Owner", null, "owner@globex.test"));
        // Bootstrap super-admin (tenant-less).
        users.save(new User(UUID.randomUUID(), "admin@valet.test",
                encoder.encode("admin1234"), Role.ADMIN, null, null, "Root", true));
        // A company manager for company A.
        users.save(new User(UUID.randomUUID(), "mgr.a@acme.test",
                encoder.encode("manager1234"), Role.MANAGER, companyA, null, "Mgr A", true));
    }

    private String base() {
        return "http://localhost:" + port;
    }

    private String login(String email, String password) {
        ResponseEntity<Map> resp = rest.postForEntity(base() + "/auth/login",
                Map.of("email", email, "password", password), Map.class);
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        return (String) resp.getBody().get("accessToken");
    }

    private HttpEntity<Map<String, Object>> authed(String token, Map<String, Object> body) {
        HttpHeaders h = new HttpHeaders();
        h.setContentType(MediaType.APPLICATION_JSON);
        h.setBearerAuth(token);
        return new HttpEntity<>(body, h);
    }

    @Test
    void loginThenMeReturnsProfileAndTenancy() {
        String token = login("mgr.a@acme.test", "manager1234");

        HttpHeaders h = new HttpHeaders();
        h.setBearerAuth(token);
        ResponseEntity<Map> me = rest.exchange(base() + "/auth/me", HttpMethod.GET,
                new HttpEntity<>(h), Map.class);

        assertThat(me.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(me.getBody().get("email")).isEqualTo("mgr.a@acme.test");
        assertThat(me.getBody().get("role")).isEqualTo("manager");
        assertThat(me.getBody().get("companyId")).isEqualTo(companyA.toString());
    }

    @Test
    void loginWithWrongPasswordIsUnauthorizedAndGeneric() {
        // rawRest is used here because Java's HttpURLConnection throws
        // HttpRetryException when reading a 401 POST response body in streaming
        // mode. rawRest uses SimpleClientHttpRequestFactory with outputStreaming=false
        // which buffers the request and allows reading the 401 body.
        ResponseEntity<Map> resp = rawRest.postForEntity(base() + "/auth/login",
                Map.of("email", "mgr.a@acme.test", "password", "wrongpass1"), Map.class);
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(resp.getBody().get("code")).isEqualTo("INVALID_CREDENTIALS");
    }

    @Test
    void meWithoutTokenIs401() {
        ResponseEntity<Map> resp = rest.getForEntity(base() + "/auth/me", Map.class);
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void adminCanRegisterValetThatCanThenLogin() {
        String adminToken = login("admin@valet.test", "admin1234");

        Map<String, Object> newValet = Map.of(
                "email", "valet1@acme.test",
                "password", "valet1234",
                "name", "Valet One",
                "role", "valet",
                "companyId", companyA.toString());

        ResponseEntity<Map> created = rest.postForEntity(base() + "/auth/register",
                authed(adminToken, newValet), Map.class);
        assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(created.getBody().get("role")).isEqualTo("valet");

        // The freshly created valet can log in.
        String valetToken = login("valet1@acme.test", "valet1234");
        assertThat(valetToken).isNotBlank();
    }

    @Test
    void managerCannotRegisterForAnotherCompany() {
        String mgrToken = login("mgr.a@acme.test", "manager1234");

        Map<String, Object> crossTenant = Map.of(
                "email", "intruder@other.test",
                "password", "intrud1234",
                "name", "Intruder",
                "role", "valet",
                "companyId", companyB.toString());

        ResponseEntity<Map> resp = rest.postForEntity(base() + "/auth/register",
                authed(mgrToken, crossTenant), Map.class);
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("CROSS_TENANT");
    }

    @Test
    void valetCannotRegisterStaff() {
        // Seed a valet and log in as them.
        users.save(new User(UUID.randomUUID(), "valet.x@acme.test",
                encoder.encode("valet1234"), Role.VALET, companyA, null, "Valet X", true));
        String valetToken = login("valet.x@acme.test", "valet1234");

        Map<String, Object> body = Map.of(
                "email", "nope@acme.test",
                "password", "nopen1234",
                "name", "Nope",
                "role", "driver",
                "companyId", companyA.toString());

        ResponseEntity<Map> resp = rest.postForEntity(base() + "/auth/register",
                authed(valetToken, body), Map.class);
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("INSUFFICIENT_PERMISSIONS");
    }

    @Test
    void seededDemoDriverCanLoginWithContractCredentials() {
        // The mandatory seed (V2) is the linchpin for the parallel slice. The
        // @BeforeEach wipes users, so re-insert the demo driver exactly as the
        // Flyway seed does (same id/tenancy) and prove the contract creds work
        // through the real login path + that /me returns the fixed claims.
        UUID driverId = UUID.fromString("11111111-1111-1111-1111-111111111111");
        UUID demoCompany = UUID.fromString("22222222-2222-2222-2222-222222222222");
        UUID demoLocation = UUID.fromString("33333333-3333-3333-3333-333333333333");
        // The @BeforeEach wipes companies/locations, so re-materialise the demo
        // tenant (V4 seeds it in prod) before the FK-bound driver insert.
        companies.save(new Company(demoCompany, "Demo Valet Co", "Demo Owner", null,
                "owner@valet.demo"));
        locations.save(new com.valet.auth.domain.Location(demoLocation, demoCompany,
                "Demo Garage", null, null, null, null, 50));
        users.save(new User(driverId, "driver@valet.demo",
                encoder.encode("Driver123"), Role.DRIVER, demoCompany, demoLocation,
                "Demo Driver", true));

        String token = login("driver@valet.demo", "Driver123");

        HttpHeaders h = new HttpHeaders();
        h.setBearerAuth(token);
        ResponseEntity<Map> me = rest.exchange(base() + "/auth/me", HttpMethod.GET,
                new HttpEntity<>(h), Map.class);
        assertThat(me.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(me.getBody().get("id")).isEqualTo(driverId.toString());
        assertThat(me.getBody().get("role")).isEqualTo("driver");
        assertThat(me.getBody().get("companyId")).isEqualTo(demoCompany.toString());
        assertThat(me.getBody().get("locationId")).isEqualTo(demoLocation.toString());
    }

    @Test
    void logoutRevokesRefreshTokenSoItCannotBeReused() {
        ResponseEntity<Map> loginResp = rest.postForEntity(base() + "/auth/login",
                Map.of("email", "admin@valet.test", "password", "admin1234"), Map.class);
        String access = (String) loginResp.getBody().get("accessToken");
        String refresh = (String) loginResp.getBody().get("refreshToken");

        // Logout (Bearer access) revoking this specific refresh token.
        ResponseEntity<Void> out = rest.exchange(base() + "/auth/logout", HttpMethod.POST,
                authed(access, Map.of("refreshToken", refresh)), Void.class);
        assertThat(out.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);

        // The revoked refresh token must no longer rotate. rawRest avoids
        // HttpURLConnection's HttpRetryException on 401 POST responses.
        ResponseEntity<Map> reuse = rawRest.postForEntity(base() + "/auth/refresh",
                Map.of("refreshToken", refresh), Map.class);
        assertThat(reuse.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void refreshRotatesAndOldTokenIsRejected() {
        ResponseEntity<Map> loginResp = rest.postForEntity(base() + "/auth/login",
                Map.of("email", "admin@valet.test", "password", "admin1234"), Map.class);
        String refresh1 = (String) loginResp.getBody().get("refreshToken");

        ResponseEntity<Map> r1 = rest.postForEntity(base() + "/auth/refresh",
                Map.of("refreshToken", refresh1), Map.class);
        assertThat(r1.getStatusCode()).isEqualTo(HttpStatus.OK);
        String refresh2 = (String) r1.getBody().get("refreshToken");
        assertThat(refresh2).isNotEqualTo(refresh1);

        // Reusing the rotated-out token must fail (reuse detection).
        // rawRest avoids HttpURLConnection's HttpRetryException on 401 POST responses.
        ResponseEntity<Map> reuse = rawRest.postForEntity(base() + "/auth/refresh",
                Map.of("refreshToken", refresh1), Map.class);
        assertThat(reuse.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);

        // Theft detection: reusing R1 must revoke the WHOLE family, so the
        // still-current R2 is now dead too. (Regression guard: this revoke must
        // commit independently of the 401 throw — REQUIRES_NEW.)
        ResponseEntity<Map> r2dead = rawRest.postForEntity(base() + "/auth/refresh",
                Map.of("refreshToken", refresh2), Map.class);
        assertThat(r2dead.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    // ----------------------------------------------------- abuse controls

    /** A small JSON-body POST helper that can read 4xx/429 bodies (rawRest). */
    private ResponseEntity<Map> postLogin(String email, String password) {
        return rawRest.postForEntity(base() + "/auth/login",
                Map.of("email", email, "password", password), Map.class);
    }

    @Test
    void rapidBadLoginsLockTheAccountThenBlockEvenTheCorrectPassword() {
        // account-max-failures = 4. Fire 4 wrong-password attempts for the manager.
        for (int i = 0; i < 4; i++) {
            ResponseEntity<Map> bad = postLogin("mgr.a@acme.test", "wrongpass" + i);
            assertThat(bad.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
            assertThat(bad.getBody().get("code")).isEqualTo("INVALID_CREDENTIALS");
        }

        // The account is now locked: even the CORRECT password is rejected with
        // 429 ACCOUNT_LOCKED until the lock window expires.
        ResponseEntity<Map> locked = postLogin("mgr.a@acme.test", "manager1234");
        assertThat(locked.getStatusCode()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
        assertThat(locked.getBody().get("code")).isEqualTo("ACCOUNT_LOCKED");
    }

    @Test
    void successfulLoginResetsTheFailureCounter() {
        // 3 failures — one short of the threshold (4).
        for (int i = 0; i < 3; i++) {
            assertThat(postLogin("mgr.a@acme.test", "bad" + i).getStatusCode())
                    .isEqualTo(HttpStatus.UNAUTHORIZED);
        }
        // A correct login succeeds and clears the counter.
        assertThat(postLogin("mgr.a@acme.test", "manager1234").getStatusCode())
                .isEqualTo(HttpStatus.OK);

        // 3 more failures still do NOT lock (counter restarted at 0).
        for (int i = 0; i < 3; i++) {
            assertThat(postLogin("mgr.a@acme.test", "bad2" + i).getStatusCode())
                    .isEqualTo(HttpStatus.UNAUTHORIZED);
        }
        // Correct password still works — not locked.
        assertThat(postLogin("mgr.a@acme.test", "manager1234").getStatusCode())
                .isEqualTo(HttpStatus.OK);
    }

    @Test
    void perIpFailureCeilingReturns429AfterTooManyFailures() {
        // ip-max-attempts = 15. Vary the email each time so no single account
        // locks first (isolating the per-IP ceiling). All attempts use wrong
        // passwords — only failures increment the per-IP bucket. After 15 the
        // 16th check must return 429 RATE_LIMITED with a Retry-After header.
        HttpStatus last = null;
        Object lastCode = null;
        String retryAfter = null;
        for (int i = 0; i < 25; i++) {
            ResponseEntity<Map> r = postLogin("nobody" + i + "@nope.test", "wrongpass1");
            last = HttpStatus.valueOf(r.getStatusCode().value());
            if (last == HttpStatus.TOO_MANY_REQUESTS) {
                lastCode = r.getBody().get("code");
                retryAfter = r.getHeaders().getFirst("Retry-After");
                break;
            }
        }
        assertThat(last).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
        assertThat(lastCode).isEqualTo("RATE_LIMITED");
        assertThat(retryAfter).isNotNull();
    }

    /**
     * THE KEY FIX REGRESSION TEST: account A gets locked via per-account lockout
     * (bad passwords), but a DIFFERENT account B from the SAME loopback IP can
     * still log in successfully with the correct password — the per-IP failure
     * bucket (only 4 failures, well below the ceiling of 15) must not block it.
     */
    @Test
    void goodLoginForAccountBSucceedsAfterAccountALocksFromSameIp() {
        // account-max-failures = 4. Lock accountA with 4 bad passwords.
        for (int i = 0; i < 4; i++) {
            ResponseEntity<Map> bad = postLogin("mgr.a@acme.test", "wrongpass" + i);
            assertThat(bad.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
            assertThat(bad.getBody().get("code")).isEqualTo("INVALID_CREDENTIALS");
        }
        // accountA is now locked: even the correct password is rejected.
        ResponseEntity<Map> locked = postLogin("mgr.a@acme.test", "manager1234");
        assertThat(locked.getStatusCode()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
        assertThat(locked.getBody().get("code")).isEqualTo("ACCOUNT_LOCKED");

        // The per-IP failure counter has 4 hits (< 15 ceiling).
        // A DIFFERENT account (admin@valet.test) from the SAME loopback IP must
        // succeed with its correct password.
        ResponseEntity<Map> good = postLogin("admin@valet.test", "admin1234");
        assertThat(good.getStatusCode())
                .as("Account B good login must succeed; per-IP failure bucket (%d) "
                        + "is below ceiling (15) so it must not block", 4)
                .isEqualTo(HttpStatus.OK);
        assertThat(good.getBody()).containsKey("accessToken");
    }

    @Test
    void healthEndpointIsNotRateLimited() {
        // Hammer the health endpoint well past the per-IP login limit — it must
        // never be rate limited (the filter self-scopes to POST login/refresh).
        for (int i = 0; i < 50; i++) {
            ResponseEntity<Map> h = rawRest.getForEntity(
                    base() + "/actuator/health", Map.class);
            assertThat(h.getStatusCode()).isEqualTo(HttpStatus.OK);
        }
    }

    // ----------------------------------------------------- method-not-allowed

    /**
     * A GET on a POST-only route must return 405 METHOD_NOT_ALLOWED (not 500).
     * Spring throws {@code HttpRequestMethodNotSupportedException}; without the
     * explicit handler it falls through to the catch-all 500 — wrong status AND
     * it pollutes error monitoring with phantom server errors.
     *
     * <p>The {@code Allow} header must list the supported method(s) per RFC 9110.
     */
    @Test
    void getOnPostOnlyRouteReturns405WithAllowHeader() {
        ResponseEntity<Map> resp = rawRest.exchange(base() + "/auth/login",
                org.springframework.http.HttpMethod.GET, null, Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.METHOD_NOT_ALLOWED);
        assertThat(resp.getBody().get("code")).isEqualTo("METHOD_NOT_ALLOWED");
        assertThat(resp.getHeaders().getFirst("Allow")).isNotNull();
        assertThat(resp.getHeaders().getFirst("Allow")).containsIgnoringCase("POST");
    }
}
