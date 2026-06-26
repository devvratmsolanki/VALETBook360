package com.valet.transaction;

import com.valet.transaction.support.TestTokens;
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
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Full-stack slice for the operator floor API against a real Postgres
 * (Testcontainers): Flyway runs (enum + legal-transition trigger + demo seed),
 * then operator endpoints are exercised with forged-but-correctly-signed HS256
 * tokens (same shared secret) so the real security + tenancy path is covered.
 *
 * <p>If Docker is unavailable, Testcontainers fails fast at container start and
 * this class is effectively skipped; the pure unit tests
 * ({@link TransactionServiceTest}, {@link ValetStatusTransitionTest}) still
 * cover the operator service logic, the realtime wiring and the legal-transition
 * map. See README "Build & test results".</p>
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class OperatorApiIntegrationTest {

    private static final UUID DEMO_DRIVER = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID DEMO_COMPANY = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID DEMO_LOCATION = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final UUID OPERATOR = UUID.fromString("44444444-4444-4444-4444-444444444444");
    private static final UUID OTHER_COMPANY = UUID.fromString("88888888-8888-8888-8888-888888888888");
    /** A seeded driver_assigned tx that already belongs to DEMO_COMPANY. */
    private static final UUID SEEDED_TX = UUID.fromString("aaaaaaa1-0000-0000-0000-000000000001");

    @Container
    static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:16-alpine")
                    .withDatabaseName("valet_core")
                    .withUsername("valet")
                    .withPassword("valet");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url",
                () -> POSTGRES.getJdbcUrl() + "&stringtype=unspecified");
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("valet.jwt.secret", () -> TestTokens.SECRET);
    }

    @LocalServerPort
    int port;

    @Autowired
    TestRestTemplate rest;

    private String base() {
        return "http://localhost:" + port;
    }

    private HttpHeaders headers(String token) {
        HttpHeaders h = new HttpHeaders();
        h.setBearerAuth(token);
        h.setContentType(MediaType.APPLICATION_JSON);
        return h;
    }

    private HttpEntity<Object> body(String token, Object payload) {
        return new HttpEntity<>(payload, headers(token));
    }

    private HttpEntity<Void> bearer(String token) {
        return new HttpEntity<>(headers(token));
    }

    private String operatorToken() {
        return TestTokens.valetAccessToken(OPERATOR, DEMO_COMPANY, DEMO_LOCATION);
    }

    private Map<String, Object> createCar(String plate) {
        return Map.of("carPlate", plate, "guestName", "Guest", "keyCode", "K-99",
                // these tenant fields are decoys: they must be ignored by the server
                "companyId", OTHER_COMPANY.toString(), "locationId", UUID.randomUUID().toString());
    }

    // --- create forces status + tenant -------------------------------------

    @Test
    void createForcesWaitingForDriverAndStampsTenantFromPrincipal() {
        ResponseEntity<Map> resp = rest.exchange(base() + "/api/operator/transactions",
                HttpMethod.POST, body(operatorToken(), createCar("CREATE001")), Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(resp.getBody().get("status")).isEqualTo("waiting_for_driver");
        // companyId from the principal, NOT the decoy OTHER_COMPANY in the body
        assertThat(resp.getBody().get("companyId")).isEqualTo(DEMO_COMPANY.toString());
    }

    // --- full operator happy path: create -> park -> key-in -> request -> assign

    @Test
    void operatorHappyPathThroughAssignAndCarAppearsInDriverAssignments() {
        String token = operatorToken();

        ResponseEntity<Map> created = rest.exchange(base() + "/api/operator/transactions",
                HttpMethod.POST, body(token, createCar("HAPPY001")), Map.class);
        assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        String id = (String) created.getBody().get("id");

        assertThat(post(token, id, "park").getBody().get("status")).isEqualTo("parked");
        assertThat(post(token, id, "key-in").getBody().get("status")).isEqualTo("key_in");
        assertThat(post(token, id, "request").getBody().get("status")).isEqualTo("requested");

        // assign a fresh driver
        UUID newDriver = UUID.fromString("55555555-5555-5555-5555-555555555555");
        ResponseEntity<Map> assigned = rest.exchange(
                base() + "/api/operator/transactions/" + id + "/assign",
                HttpMethod.POST, body(token, Map.of("driverId", newDriver.toString())), Map.class);
        assertThat(assigned.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(assigned.getBody().get("status")).isEqualTo("driver_assigned");
        assertThat(assigned.getBody().get("retrievedByDriverId")).isEqualTo(newDriver.toString());

        // the assigned car now shows in THAT driver's assignments feed
        ResponseEntity<List> feed = rest.exchange(base() + "/api/driver/assignments",
                HttpMethod.GET,
                bearer(TestTokens.driverAccessToken(newDriver, DEMO_COMPANY, DEMO_LOCATION)),
                List.class);
        assertThat(feed.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = feed.getBody();
        assertThat(items).extracting(m -> m.get("id")).contains(id);
    }

    private ResponseEntity<Map> post(String token, String id, String action) {
        ResponseEntity<Map> r = rest.exchange(
                base() + "/api/operator/transactions/" + id + "/" + action,
                HttpMethod.POST, bearer(token), Map.class);
        assertThat(r.getStatusCode()).isEqualTo(HttpStatus.OK);
        return r;
    }

    // --- active floor feed -------------------------------------------------

    @Test
    void activeFloorReturnsOnlyCallerCompanyNonTerminalTransactions() {
        ResponseEntity<List> resp = rest.exchange(base() + "/api/operator/transactions",
                HttpMethod.GET, bearer(operatorToken()), List.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = resp.getBody();
        // every row must belong to the caller's company; none terminal
        assertThat(items).isNotEmpty();
        assertThat(items).allSatisfy(m -> {
            assertThat(m.get("companyId")).isEqualTo(DEMO_COMPANY.toString());
            assertThat(m.get("status")).isNotIn("delivered", "cancelled");
        });
    }

    // --- cross-tenant guard ------------------------------------------------

    @Test
    void operatorFromAnotherCompanyCannotParkForeignTxGets403() {
        // operator scoped to OTHER_COMPANY tries to touch DEMO_COMPANY's seeded tx
        String foreign = TestTokens.valetAccessToken(OPERATOR, OTHER_COMPANY, DEMO_LOCATION);
        ResponseEntity<Map> resp = rest.exchange(
                base() + "/api/operator/transactions/" + SEEDED_TX + "/cancel",
                HttpMethod.POST, bearer(foreign), Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("NOT_YOUR_TRANSACTION");
    }

    // --- role guard: driver hitting an operator endpoint -------------------

    /**
     * The security-chain URL rule ({@code /api/operator/**} → hasAnyRole(VALET, MANAGER, ADMIN))
     * rejects the driver token at layer 1, before the controller's NOT_AN_OPERATOR
     * check is reached. {@code ProblemAuthEntryPoint} therefore emits the generic
     * {@code FORBIDDEN} code. This is the correct production behaviour: leaking a
     * role-specific error code ({@code NOT_AN_OPERATOR}) to an attacker who is
     * probing the API would be information disclosure. The 403 status is the
     * binding contract; the specific code is an implementation detail of the
     * security layer, not the controller layer.
     */
    @Test
    void driverRoleIsForbiddenFromOperatorApi() {
        String driverToken = TestTokens.driverAccessToken(DEMO_DRIVER, DEMO_COMPANY, DEMO_LOCATION);
        ResponseEntity<Map> resp = rest.exchange(base() + "/api/operator/transactions",
                HttpMethod.GET, bearer(driverToken), Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("FORBIDDEN");
    }

    // --- illegal transition guard ------------------------------------------

    @Test
    void parkingAnAlreadyAssignedTxGets409() {
        // SEEDED_TX is driver_assigned; waiting->parked is illegal from there
        ResponseEntity<Map> resp = rest.exchange(
                base() + "/api/operator/transactions/" + SEEDED_TX + "/park",
                HttpMethod.POST, bearer(operatorToken()), Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(resp.getBody().get("code")).isEqualTo("ILLEGAL_TRANSITION");
    }

    // --- manager role is also an operator ----------------------------------

    @Test
    void managerRoleCanCreate() {
        String managerToken = TestTokens.managerAccessToken(OPERATOR, DEMO_COMPANY, DEMO_LOCATION);
        ResponseEntity<Map> resp = rest.exchange(base() + "/api/operator/transactions",
                HttpMethod.POST, body(managerToken, createCar("MGR00001")), Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(resp.getBody().get("companyId")).isEqualTo(DEMO_COMPANY.toString());
    }

    // --- method-not-allowed handler (FIX 2) --------------------------------

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
        String token = operatorToken();
        ResponseEntity<Map> resp = rest.exchange(
                base() + "/api/operator/transactions/" + SEEDED_TX + "/park",
                HttpMethod.GET, bearer(token), Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.METHOD_NOT_ALLOWED);
        assertThat(resp.getBody().get("code")).isEqualTo("METHOD_NOT_ALLOWED");
        assertThat(resp.getHeaders().getFirst("Allow")).isNotNull();
        assertThat(resp.getHeaders().getFirst("Allow")).containsIgnoringCase("POST");
    }
}
