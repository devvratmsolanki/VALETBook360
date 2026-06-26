package com.valet.auth.controller;

import com.valet.auth.domain.Role;
import com.valet.auth.dto.AdminUserResponse;
import com.valet.auth.dto.CompanyResponse;
import com.valet.auth.dto.CreateCompanyRequest;
import com.valet.auth.dto.CreateLocationRequest;
import com.valet.auth.dto.CreateStaffRequest;
import com.valet.auth.dto.LocationResponse;
import com.valet.auth.dto.UpdateLocationRequest;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.security.AuthPrincipal;
import com.valet.auth.service.CompanyAdminService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Tenant management for the admin + company-owner panels.
 *
 * <p>Paths under {@code /api/companies/**} and {@code /api/locations/**}. The
 * security chain restricts these to roles ADMIN + MANAGER; per-tenant + admin-only
 * checks (a manager touching another company, create-company being admin-only)
 * live in {@link CompanyAdminService} so the precise RFC7807 codes
 * ({@code CROSS_TENANT}, {@code INSUFFICIENT_PERMISSIONS}, ...) reach the client.
 * The caller's tenant is ALWAYS taken from the JWT principal, never the body.</p>
 */
@RestController
@RequestMapping("/api")
public class CompanyController {

    private final CompanyAdminService service;

    public CompanyController(CompanyAdminService service) {
        this.service = service;
    }

    // ----------------------------------------------------------- companies

    /** GET /api/companies — admin: all; manager: their own (1-element list). */
    @GetMapping("/companies")
    public List<CompanyResponse> listCompanies() {
        return service.listCompanies(principal());
    }

    /** POST /api/companies — ADMIN only. Transactional create-company-with-owner. */
    @PostMapping("/companies")
    public ResponseEntity<CompanyResponse> createCompany(
            @Valid @RequestBody CreateCompanyRequest req) {
        CompanyResponse created = service.createCompanyWithOwner(principal(), req);
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    /** GET /api/companies/{id} — admin any; manager own only (else 403). */
    @GetMapping("/companies/{id}")
    public CompanyResponse getCompany(@PathVariable("id") UUID id) {
        return service.getCompany(principal(), id);
    }

    // ----------------------------------------------------------- locations

    /** GET /api/companies/{id}/locations — admin any; manager own. */
    @GetMapping("/companies/{id}/locations")
    public List<LocationResponse> listLocations(@PathVariable("id") UUID id) {
        return service.listLocations(principal(), id);
    }

    /** POST /api/companies/{id}/locations — create a location. Admin any; manager own. */
    @PostMapping("/companies/{id}/locations")
    public ResponseEntity<LocationResponse> createLocation(
            @PathVariable("id") UUID id,
            @Valid @RequestBody CreateLocationRequest req) {
        LocationResponse created = service.createLocation(principal(), id, req);
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    /** PUT /api/locations/{id} — edit a location. Admin any; manager own. */
    @PutMapping("/locations/{id}")
    public LocationResponse updateLocation(@PathVariable("id") UUID id,
                                           @Valid @RequestBody UpdateLocationRequest req) {
        return service.updateLocation(principal(), id, req);
    }

    // ---------------------------------------------------------- staff/users

    /**
     * GET /api/companies/{id}/users?role= — list a company's users, optionally
     * filtered by role (valet/driver/manager). Admin any; manager own.
     */
    @GetMapping("/companies/{id}/users")
    public List<AdminUserResponse> listCompanyUsers(@PathVariable("id") UUID id,
                                                    @RequestParam(value = "role", required = false)
                                                    String role) {
        Role roleFilter = parseRoleFilter(role);
        return service.listCompanyUsers(principal(), id, roleFilter);
    }

    /**
     * POST /api/companies/{id}/staff — create an operator (valet) or driver
     * login under the company. Admin any; manager own. role must be valet|driver.
     */
    @PostMapping("/companies/{id}/staff")
    public ResponseEntity<AdminUserResponse> createStaff(
            @PathVariable("id") UUID id,
            @Valid @RequestBody CreateStaffRequest req) {
        AdminUserResponse created = service.createStaff(principal(), id, req);
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    // -------------------------------------------------------------- helpers

    private static Role parseRoleFilter(String role) {
        if (role == null || role.isBlank()) {
            return null;
        }
        try {
            return Role.fromWire(role);
        } catch (IllegalArgumentException ex) {
            throw ServiceException.badRequest("INVALID_ROLE_FILTER",
                    "Unknown role filter. Use admin, manager, valet or driver.");
        }
    }

    private AuthPrincipal principal() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof AuthPrincipal p)) {
            throw ServiceException.unauthorized("AUTH_REQUIRED",
                    "You need to sign in to continue.");
        }
        return p;
    }
}
