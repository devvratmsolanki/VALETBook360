package com.valet.auth;

import com.valet.auth.domain.Company;
import com.valet.auth.domain.Location;
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

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Admin/company management slice: companies, locations, and staff provisioning
 * with the tenant + role authorization rules. Boots the app against a real
 * Postgres (Testcontainers), runs Flyway (so the V4/V5 schema + seed apply), and
 * exercises every new endpoint via Apache HttpClient5 (so 4xx bodies are
 * readable). Mirrors {@link AuthIntegrationTest} infrastructure.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class AdminCompanyIntegrationTest {

    @Container
    static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>("postgres:16-alpine")
                    .withDatabaseName("valet_auth")
                    .withUsername("valet")
                    .withPassword("valet");

    @Container
    static final GenericContainer<?> REDIS =
            new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url",
                () -> POSTGRES.getJdbcUrl() + "&stringtype=unspecified");
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("auth.jwt.secret", () -> "integration-test-secret-which-is-32+bytes!!");
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
        // Generous abuse-control thresholds — this suite does many logins.
        registry.add("auth.login-guard.ip-max-attempts", () -> 500);
        registry.add("auth.login-guard.account-max-failures", () -> 50);
    }

    @LocalServerPort
    int port;

    @Autowired
    TestRestTemplate rest;

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

    private RestTemplate http;

    private UUID companyA; // has manager mgrA
    private UUID companyB; // foreign company

    @BeforeEach
    void seed() {
        http = new RestTemplate(new HttpComponentsClientHttpRequestFactory());
        http.setErrorHandler(new NoOpResponseErrorHandler());
        redis.getConnectionFactory().getConnection().serverCommands().flushAll();

        // FK-safe wipe order: users -> locations -> companies.
        users.deleteAll();
        locations.deleteAll();
        companies.deleteAll();

        companyA = UUID.randomUUID();
        companyB = UUID.randomUUID();
        companies.save(new Company(companyA, "Acme Valet", "Acme Owner", null, "owner@acme.test"));
        companies.save(new Company(companyB, "Globex Valet", "Globex Owner", null, "owner@globex.test"));

        // Super admin (tenant-less).
        users.save(new User(UUID.randomUUID(), "admin@valet.test",
                encoder.encode("admin1234"), Role.ADMIN, null, null, "Root", true));
        // Manager (UI "company") for company A.
        users.save(new User(UUID.randomUUID(), "mgr.a@acme.test",
                encoder.encode("manager1234"), Role.MANAGER, companyA, null, "Mgr A", true));
        // A valet for company A (to prove valet -> 403 on admin/company paths).
        users.save(new User(UUID.randomUUID(), "valet.a@acme.test",
                encoder.encode("valet1234"), Role.VALET, companyA, null, "Valet A", true));
    }

    // ----------------------------------------------------------- helpers

    private String base() {
        return "http://localhost:" + port;
    }

    private String login(String email, String pw) {
        ResponseEntity<Map> r = rest.postForEntity(base() + "/auth/login",
                Map.of("email", email, "password", pw), Map.class);
        assertThat(r.getStatusCode()).isEqualTo(HttpStatus.OK);
        return (String) r.getBody().get("accessToken");
    }

    private HttpHeaders bearer(String token) {
        HttpHeaders h = new HttpHeaders();
        h.setContentType(MediaType.APPLICATION_JSON);
        h.setBearerAuth(token);
        return h;
    }

    private ResponseEntity<Map> get(String token, String path) {
        return http.exchange(base() + path, HttpMethod.GET,
                new HttpEntity<>(bearer(token)), Map.class);
    }

    private ResponseEntity<List> getList(String token, String path) {
        return http.exchange(base() + path, HttpMethod.GET,
                new HttpEntity<>(bearer(token)), List.class);
    }

    private ResponseEntity<Map> post(String token, String path, Map<String, Object> body) {
        return http.exchange(base() + path, HttpMethod.POST,
                new HttpEntity<>(body, bearer(token)), Map.class);
    }

    private ResponseEntity<Map> put(String token, String path, Map<String, Object> body) {
        return http.exchange(base() + path, HttpMethod.PUT,
                new HttpEntity<>(body, bearer(token)), Map.class);
    }

    // =====================================================================

    @Test
    void adminCreatesCompanyAndOwnerCanLogIn() {
        String admin = login("admin@valet.test", "admin1234");

        ResponseEntity<Map> created = post(admin, "/api/companies", Map.of(
                "companyName", "Skyline Co",
                "ownerName", "Sky Owner",
                "phone", "555-0100",
                "email", "newowner@skyline.test",
                "password", "Skyline123"));
        assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(created.getBody().get("companyName")).isEqualTo("Skyline Co");
        String newCompanyId = (String) created.getBody().get("id");
        assertThat(newCompanyId).isNotBlank();

        // The provisioned owner can log in and is a manager bound to the company.
        ResponseEntity<Map> ownerLogin = rest.postForEntity(base() + "/auth/login",
                Map.of("email", "newowner@skyline.test", "password", "Skyline123"), Map.class);
        assertThat(ownerLogin.getStatusCode()).isEqualTo(HttpStatus.OK);
        Map ownerUser = (Map) ownerLogin.getBody().get("user");
        assertThat(ownerUser.get("role")).isEqualTo("manager");
        assertThat(ownerUser.get("companyId")).isEqualTo(newCompanyId);
    }

    @Test
    void createCompanyRollsBackWhenOwnerEmailDuplicate_noOrphanCompany() {
        String admin = login("admin@valet.test", "admin1234");
        long before = companies.count();

        // owner@acme.test already exists? No — but mgr.a@acme.test does. Use it.
        ResponseEntity<Map> resp = post(admin, "/api/companies", Map.of(
                "companyName", "Duplicate Owner Co",
                "ownerName", "Dup",
                "email", "mgr.a@acme.test", // already taken by company A's manager
                "password", "Duplicate123"));
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(resp.getBody().get("code")).isEqualTo("EMAIL_TAKEN");

        // No orphan company row was left behind (transactional rollback).
        assertThat(companies.count()).isEqualTo(before);
        assertThat(companies.findAll().stream()
                .noneMatch(c -> c.getCompanyName().equals("Duplicate Owner Co"))).isTrue();
    }

    @Test
    void adminCreatesLocationOperatorAndDriverUnderCompany_appearInUsers() {
        String admin = login("admin@valet.test", "admin1234");

        // Location.
        ResponseEntity<Map> loc = post(admin, "/api/companies/" + companyA + "/locations", Map.of(
                "name", "Main Garage", "city", "Gotham", "keyCapacity", 40));
        assertThat(loc.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        String locationId = (String) loc.getBody().get("id");

        // Operator (valet) pinned to that location.
        ResponseEntity<Map> op = post(admin, "/api/companies/" + companyA + "/staff", Map.of(
                "email", "op1@acme.test", "password", "Operator123",
                "name", "Op One", "role", "valet", "locationId", locationId));
        assertThat(op.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(op.getBody().get("role")).isEqualTo("valet");
        assertThat(op.getBody().get("locationId")).isEqualTo(locationId);

        // Driver.
        ResponseEntity<Map> dr = post(admin, "/api/companies/" + companyA + "/staff", Map.of(
                "email", "dr1@acme.test", "password", "Driver1234",
                "name", "Driver One", "role", "driver"));
        assertThat(dr.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(dr.getBody().get("role")).isEqualTo("driver");

        // They appear under the company's users.
        ResponseEntity<List> all = getList(admin, "/api/companies/" + companyA + "/users");
        assertThat(all.getStatusCode()).isEqualTo(HttpStatus.OK);
        List<Map> list = all.getBody();
        assertThat(list).anyMatch(u -> "op1@acme.test".equals(u.get("email")));
        assertThat(list).anyMatch(u -> "dr1@acme.test".equals(u.get("email")));

        // Role filter narrows to drivers only.
        ResponseEntity<List> drivers = getList(admin,
                "/api/companies/" + companyA + "/users?role=driver");
        assertThat(drivers.getBody()).allMatch(u -> "driver".equals(((Map) u).get("role")));
        assertThat(drivers.getBody()).anyMatch(u -> "dr1@acme.test".equals(((Map) u).get("email")));

        // The new operator can log in.
        assertThat(login("op1@acme.test", "Operator123")).isNotBlank();
    }

    @Test
    void managerSeesOnlyOwnCompanyOnList() {
        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<List> list = getList(mgr, "/api/companies");
        assertThat(list.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(list.getBody()).hasSize(1);
        assertThat(((Map) list.getBody().get(0)).get("id")).isEqualTo(companyA.toString());
    }

    @Test
    void managerCannotReadAnotherCompany() {
        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = get(mgr, "/api/companies/" + companyB);
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("CROSS_TENANT");
    }

    @Test
    void managerCannotCreateStaffInAnotherCompany() {
        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = post(mgr, "/api/companies/" + companyB + "/staff", Map.of(
                "email", "intruder@globex.test", "password", "Intruder123",
                "name", "Intruder", "role", "valet"));
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("CROSS_TENANT");
    }

    @Test
    void managerCanManageOwnCompanyLocationsAndStaff() {
        String mgr = login("mgr.a@acme.test", "manager1234");

        ResponseEntity<Map> loc = post(mgr, "/api/companies/" + companyA + "/locations", Map.of(
                "name", "Mgr Garage", "keyCapacity", 10));
        assertThat(loc.getStatusCode()).isEqualTo(HttpStatus.CREATED);

        ResponseEntity<Map> staff = post(mgr, "/api/companies/" + companyA + "/staff", Map.of(
                "email", "mgrvalet@acme.test", "password", "Valet1234",
                "name", "Mgr Valet", "role", "valet"));
        assertThat(staff.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }

    @Test
    void managerCannotCreateCompany() {
        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = post(mgr, "/api/companies", Map.of(
                "companyName", "Sneaky Co", "email", "sneaky@x.test", "password", "Sneaky123"));
        // Chain restricts POST /api/companies to ADMIN+MANAGER, so manager reaches
        // the handler, then the service rejects admin-only with 403.
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("INSUFFICIENT_PERMISSIONS");
    }

    @Test
    void managerCannotCreateManagerOrAdminViaStaff() {
        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = post(mgr, "/api/companies/" + companyA + "/staff", Map.of(
                "email", "escalate@acme.test", "password", "Escalate123",
                "name", "Escalate", "role", "manager"));
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(resp.getBody().get("code")).isEqualTo("INVALID_STAFF_ROLE");
    }

    @Test
    void valetIsForbiddenOnCompanyEndpoints() {
        String valet = login("valet.a@acme.test", "valet1234");
        // Chain blocks valet on /api/companies/** with a plain 403.
        ResponseEntity<Map> resp = get(valet, "/api/companies");
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void valetIsForbiddenOnAdminEndpoints() {
        String valet = login("valet.a@acme.test", "valet1234");
        ResponseEntity<Map> resp = get(valet, "/api/admin/users");
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void managerIsForbiddenOnAdminEndpoints() {
        // /api/admin/** is ADMIN-only at the chain; a manager gets 403.
        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = get(mgr, "/api/admin/locations");
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void adminLocationsAndUsersAreCrossTenantAndCarryCompanyName() {
        String admin = login("admin@valet.test", "admin1234");
        // Seed a location in each company.
        locations.save(new Location(UUID.randomUUID(), companyA, "A-Loc", null, null, null, null, 5));
        locations.save(new Location(UUID.randomUUID(), companyB, "B-Loc", null, null, null, null, 5));

        ResponseEntity<List> locs = getList(admin, "/api/admin/locations");
        assertThat(locs.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(locs.getBody()).hasSizeGreaterThanOrEqualTo(2);
        assertThat(locs.getBody()).anyMatch(l -> "Acme Valet".equals(((Map) l).get("companyName")));
        assertThat(locs.getBody()).anyMatch(l -> "Globex Valet".equals(((Map) l).get("companyName")));

        ResponseEntity<List> us = getList(admin, "/api/admin/users");
        assertThat(us.getStatusCode()).isEqualTo(HttpStatus.OK);
        // admin@valet.test (tenant-less) + mgr.a + valet.a => >= 3.
        assertThat(us.getBody()).hasSizeGreaterThanOrEqualTo(3);
        assertThat(us.getBody()).anyMatch(u -> "Acme Valet".equals(((Map) u).get("companyName")));
    }

    // ===================== edit-team-member (PUT /api/users/{id}) =========
    //
    // The recently-added staff-edit endpoint. These lock down the three ways it
    // could leak: cross-tenant IDOR on {id}, privilege escalation via the role
    // field, and cross-tenant location reassignment. Plus the happy path.

    /** Resolve a seeded user's id by email (tests assert against the path id). */
    private UUID userId(String email) {
        return users.findAll().stream()
                .filter(u -> email.equalsIgnoreCase(u.getEmail()))
                .findFirst().orElseThrow().getId();
    }

    @Test
    void managerCannotEditStaffInAnotherCompany() {
        // A valet that belongs to company B.
        UUID valetB = UUID.randomUUID();
        users.save(new User(valetB, "valet.b@globex.test",
                encoder.encode("valet1234"), Role.VALET, companyB, null, "Valet B", true));

        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = put(mgr, "/api/users/" + valetB, Map.of(
                "name", "Hijacked", "role", "valet"));
        // company is taken from the stored row, not the body, and authorized
        // against the manager's own company -> cross-tenant IDOR blocked.
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("CROSS_TENANT");
    }

    @Test
    void updateStaffCannotEscalateRoleToManager() {
        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = put(mgr, "/api/users/" + userId("valet.a@acme.test"), Map.of(
                "name", "Valet A", "role", "manager"));
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(resp.getBody().get("code")).isEqualTo("INVALID_STAFF_ROLE");
    }

    @Test
    void updateStaffCannotTargetAManagerAccount() {
        // Editing a manager/admin account through the staff endpoint is rejected
        // before the role field is even considered (protected-account guard).
        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = put(mgr, "/api/users/" + userId("mgr.a@acme.test"), Map.of(
                "name", "Self Demote", "role", "valet"));
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("PROTECTED_ACCOUNT");
    }

    @Test
    void updateStaffCannotReassignToForeignLocation() {
        // A location owned by company B; manager A must not pin their own valet to it.
        UUID locB = UUID.randomUUID();
        locations.save(new Location(locB, companyB, "B-Loc", null, null, null, null, 5));

        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = put(mgr, "/api/users/" + userId("valet.a@acme.test"), Map.of(
                "name", "Valet A", "role", "valet", "locationId", locB.toString()));
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("CROSS_TENANT");
    }

    @Test
    void managerCanEditOwnStaffNameRoleAndLocation() {
        UUID locA = UUID.randomUUID();
        locations.save(new Location(locA, companyA, "A-Loc", null, null, null, null, 5));

        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = put(mgr, "/api/users/" + userId("valet.a@acme.test"), Map.of(
                "name", "Renamed Valet", "role", "driver", "locationId", locA.toString()));
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(resp.getBody().get("name")).isEqualTo("Renamed Valet");
        assertThat(resp.getBody().get("role")).isEqualTo("driver");
        assertThat(resp.getBody().get("locationId")).isEqualTo(locA.toString());
    }

    @Test
    void updateLocationEnforcesTenant() {
        String admin = login("admin@valet.test", "admin1234");
        // Location in company B.
        UUID locB = UUID.randomUUID();
        locations.save(new Location(locB, companyB, "B-Loc", null, null, null, null, 5));

        // Manager A cannot edit company B's location.
        String mgr = login("mgr.a@acme.test", "manager1234");
        ResponseEntity<Map> resp = put(mgr, "/api/locations/" + locB, Map.of(
                "name", "Hijacked", "keyCapacity", 99));
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(resp.getBody().get("code")).isEqualTo("CROSS_TENANT");

        // Admin can.
        ResponseEntity<Map> ok = put(admin, "/api/locations/" + locB, Map.of(
                "name", "Renamed", "keyCapacity", 77));
        assertThat(ok.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(ok.getBody().get("name")).isEqualTo("Renamed");
        assertThat(ok.getBody().get("keyCapacity")).isEqualTo(77);
    }
}
