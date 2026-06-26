package com.valet.auth.controller;

import com.valet.auth.dto.DriverSummary;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.security.AuthPrincipal;
import com.valet.auth.service.DriverDirectoryService;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Tenant-scoped driver directory for the operator's assign-driver picker.
 *
 * <p>Driver identities live in the auth service's {@code users} table (role =
 * {@code driver}, with a {@code company_id}), so the lookup belongs here rather
 * than in transaction-service (whose {@code valet_core} DB has no users table).
 * The Flutter operator app calls AUTH for this list and transaction-service for
 * the actual assign.</p>
 *
 * <p>The security chain only guarantees the caller is authenticated
 * ({@code anyRequest().authenticated()}); role + tenant authorization is
 * enforced in {@link DriverDirectoryService} from the JWT principal, exactly
 * like the transaction-service OperatorController pattern, so the endpoint is
 * safe even without a dedicated security rule.</p>
 */
@RestController
@RequestMapping("/drivers")
public class DriverDirectoryController {

    private final DriverDirectoryService directory;

    public DriverDirectoryController(DriverDirectoryService directory) {
        this.directory = directory;
    }

    /**
     * GET /drivers → the active drivers in the caller's company as
     * {@code [{ id, name, email }]}. Operator-capable roles only; tenant is
     * server-derived from the JWT. 403 for a driver token or a principal with
     * no company.
     */
    @GetMapping
    public List<DriverSummary> listDrivers() {
        return directory.listForCompany(currentPrincipal());
    }

    /**
     * Pull the JWT-derived principal out of the SecurityContext. The security
     * chain guarantees authentication for any non-public path, so a missing
     * principal here is an internal invariant violation.
     */
    private AuthPrincipal currentPrincipal() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof AuthPrincipal principal)) {
            throw ServiceException.unauthorized("AUTH_REQUIRED",
                    "You need to sign in to continue.");
        }
        return principal;
    }
}
