package com.valet.auth.controller;

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
 * Self-service endpoints for the facility owner panel (view-only).
 * Security chain restricts {@code /api/facility-owner/**} to
 * ADMIN | MANAGER | FACILITY_OWNER — enforced in SecurityConfig.
 */
@RestController
@RequestMapping("/api/facility-owner")
public class FacilityOwnerController {

    private final CompanyAdminService service;

    public FacilityOwnerController(CompanyAdminService service) {
        this.service = service;
    }

    /** GET /api/facility-owner/locations — locations assigned to the calling user. */
    @GetMapping("/locations")
    public List<LocationResponse> myLocations() {
        return service.listFacilityOwnerLocations(principal());
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
