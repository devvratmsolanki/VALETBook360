package com.valet.auth.controller;

import com.valet.auth.dto.AdminUserResponse;
import com.valet.auth.dto.LocationResponse;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.security.AuthPrincipal;
import com.valet.auth.service.CompanyAdminService;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Super-admin-only cross-tenant views ({@code /api/admin/**}). The security chain
 * restricts these paths to ADMIN; the service re-checks for precise codes.
 * These power the admin's "all locations" and hierarchical "all users" screens.
 */
@RestController
@RequestMapping("/api/admin")
public class AdminController {

    private final CompanyAdminService service;

    public AdminController(CompanyAdminService service) {
        this.service = service;
    }

    /** GET /api/admin/locations — every location, each with its companyName. */
    @GetMapping("/locations")
    public List<LocationResponse> allLocations() {
        return service.listAllLocations(principal());
    }

    /** GET /api/admin/users — every user with company + role, for bucketing. */
    @GetMapping("/users")
    public List<AdminUserResponse> allUsers() {
        return service.listAllUsers(principal());
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
