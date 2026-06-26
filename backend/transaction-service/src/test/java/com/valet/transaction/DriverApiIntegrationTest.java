package com.valet.transaction;

import com.valet.transaction.support.TestTokens;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
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
 * Full-stack slice against a real Postgres (Testcontainers): runs Flyway (enum +
 * legal-transition trigger + the mandatory demo seed), then exercises the driver
 * API with a forged-but-correctly-signed HS256 token (same shared secret).
 *
 * <p>If Docker is unavailable, Testcontainers fails fast at container start and
 * this class is effectively skipped; the pure unit tests
 * ({@link ValetStatusTransitionTest}, {@link TransactionServiceTest},
 * {@link JwtServiceTest}) still cover the legal-transition map and JWT layer.
 * See README "Build & test results".</p>
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class DriverApiIntegrationTest {

    private static final UUID DEMO_DRIVER = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID DEMO_COMPANY = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID DEMO_LOCATION = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final UUID TX_1 = UUID.fromString("aaaaaaa1-0000-0000-0000-000000000001");

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

    private HttpEntity<Void> bearer(String token) {
        HttpHeaders h = new HttpHeaders();
        h.setBearerAuth(token);
        return new HttpEntity<>(h);
    }

    private String demoDriverToken() {
        return TestTokens.driverAccessToken(DEMO_DRIVER, DEMO_COMPANY, DEMO_LOCATION);
    }

    @Test
    @Order(1)
    void seededAssignmentsAreReturnedNewestFirst() {
        ResponseEntity<List> resp = rest.exchange(base() + "/api/driver/assignments",
                HttpMethod.GET, bearer(demoDriverToken()), List.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = resp.getBody();
        assertThat(items).hasSize(3);
        // newest first by created_at: tx_3 (15m ago) should precede tx_1 (40m ago)
        assertThat(items.get(0).get("id")).isEqualTo("aaaaaaa1-0000-0000-0000-000000000003");
        assertThat(items.get(2).get("id")).isEqualTo("aaaaaaa1-0000-0000-0000-000000000001");
        // contract item shape
        Map<String, Object> first = items.get(0);
        assertThat(first).containsKeys("id", "carPlate", "carMake", "carModel",
                "carColor", "keyCode", "status", "guestName", "locationId", "requestedAt");
        assertThat(first.get("status")).isEqualTo("driver_assigned");
    }

    @Test
    @Order(10)
    void transitionHappyPathDriverAssignedToEnRouteToArrivedToDelivered() {
        String token = demoDriverToken();

        ResponseEntity<Map> enRoute = rest.exchange(
                base() + "/api/driver/transactions/" + TX_1 + "/en-route",
                HttpMethod.POST, bearer(token), Map.class);
        assertThat(enRoute.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(enRoute.getBody().get("status")).isEqualTo("en_route");

        ResponseEntity<Map> arrived = rest.exchange(
                base() + "/api/driver/transactions/" + TX_1 + "/arrived",
                HttpMethod.POST, bearer(token), Map.class);
        assertThat(arrived.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(arrived.getBody().get("status")).isEqualTo("arrived");
        assertThat(arrived.getBody().get("arrivedAt")).isNotNull();

        ResponseEntity<Map> delivered = rest.exchange(
                base() + "/api/driver/transactions/" + TX_1 + "/delivered",
                HttpMethod.POST, bearer(token), Map.class);
        assertThat(delivered.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(delivered.getBody().get("status")).isEqualTo("delivered");
        assertThat(delivered.getBody().get("deliveredAt")).isNotNull();
    }

    @Test
    @Order(2)
    void illegalTransitionIsRejectedWith409() {
        // tx_2 is driver_assigned; jumping straight to /arrived skips en_route.
        UUID tx2 = UUID.fromString("aaaaaaa1-0000-0000-0000-000000000002");
        ResponseEntity<Map> resp = rest.exchange(
                base() + "/api/driver/transactions/" + tx2 + "/arrived",
                HttpMethod.POST, bearer(demoDriverToken()), Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(resp.getBody().get("code")).isEqualTo("ILLEGAL_TRANSITION");
    }

    @Test
    @Order(3)
    void foreignDriverGets403() {
        UUID otherDriver = UUID.randomUUID();
        String token = TestTokens.driverAccessToken(otherDriver, DEMO_COMPANY, DEMO_LOCATION);
        ResponseEntity<Map> resp = rest.exchange(
                base() + "/api/driver/transactions/" + TX_1 + "/en-route",
                HttpMethod.POST, bearer(token), Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("NOT_YOUR_ASSIGNMENT");
    }

    @Test
    @Order(2)
    void nonDriverRoleIsForbiddenFromDriverApi() {
        String valetToken = TestTokens.valetAccessToken(UUID.randomUUID(), DEMO_COMPANY, DEMO_LOCATION);
        ResponseEntity<Map> resp = rest.exchange(base() + "/api/driver/assignments",
                HttpMethod.GET, bearer(valetToken), Map.class);

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    @Order(2)
    void noTokenIs401() {
        ResponseEntity<Map> resp = rest.getForEntity(base() + "/api/driver/assignments", Map.class);
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }

    @Test
    @Order(5)
    void debugGetTransactionReturnsFullShape() {
        ResponseEntity<Map> resp = rest.exchange(base() + "/api/transactions/" + TX_1,
                HttpMethod.GET, bearer(demoDriverToken()), Map.class);
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(resp.getBody().get("companyId")).isEqualTo(DEMO_COMPANY.toString());
        assertThat(resp.getBody().get("retrievedByDriverId")).isEqualTo(DEMO_DRIVER.toString());
    }
}
