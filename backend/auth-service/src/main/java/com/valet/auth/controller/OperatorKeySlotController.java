package com.valet.auth.controller;

import com.valet.auth.dto.OperatorKeySlotsResponse;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.security.AuthPrincipal;
import com.valet.auth.service.CompanyAdminService;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Operator-facing key-slot pool. Unlike the admin/manager slot endpoints under
 * {@code /api/locations/**}, this is reachable by a valet (operator) and always
 * scopes to the caller's OWN location from the JWT — so the operator panel can
 * render the slot grid and auto-assign a code without admin rights. Mirrors the
 * operator-accessible {@code /drivers} directory.
 */
@RestController
public class OperatorKeySlotController {

    private final CompanyAdminService service;

    public OperatorKeySlotController(CompanyAdminService service) {
        this.service = service;
    }

    /** GET /key-slots — the effective slot pool for the caller's own location. */
    @GetMapping("/key-slots")
    public OperatorKeySlotsResponse myLocationKeySlots() {
        return service.operatorKeySlots(principal());
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
