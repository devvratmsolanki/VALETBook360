package com.valet.auth.service;

import com.valet.auth.domain.Role;
import com.valet.auth.dto.DriverSummary;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.repository.DriverDirectoryRepository;
import com.valet.auth.security.AuthPrincipal;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Set;

/**
 * Backs the operator's driver picker. Returns the active {@code driver}-role
 * users in the CALLER's company so an operator can dispatch a retrieval to a
 * real driver instead of typing a raw id.
 *
 * <p><b>Authorization (enforced here, not the security chain).</b> Under the
 * current {@code anyRequest().authenticated()} rule the endpoint only knows the
 * caller is authenticated; this service applies the fine-grained rules,
 * mirroring {@link AuthService} and the transaction-service OperatorController:
 * <ul>
 *   <li>Only operator-capable roles ({@code valet}, {@code manager},
 *       {@code admin}) may list drivers — a {@code driver} token is rejected
 *       403. A driver has no need to enumerate the company's drivers.</li>
 *   <li>The caller's company is MANDATORY and is taken from the JWT principal,
 *       never the request. A principal with no company is rejected 403
 *       (mirrors the {@code NO_TENANT} contract). This also means an admin who
 *       carries no company gets 403 here — the picker is a tenant-scoped view,
 *       so a global admin must operate within a company context to use it.</li>
 * </ul></p>
 */
@Service
public class DriverDirectoryService {

    /** Roles allowed to read the driver directory. Drivers are excluded. */
    private static final Set<String> OPERATOR_ROLES = Set.of("valet", "manager", "admin");

    private final DriverDirectoryRepository drivers;

    public DriverDirectoryService(DriverDirectoryRepository drivers) {
        this.drivers = drivers;
    }

    /**
     * List the active drivers in the caller's company. Tenant scope is derived
     * solely from {@code caller.companyId()} — it is never accepted from input.
     */
    @Transactional(readOnly = true)
    public List<DriverSummary> listForCompany(AuthPrincipal caller) {
        String role = caller.role() == null ? "" : caller.role().toLowerCase();
        if (!OPERATOR_ROLES.contains(role)) {
            throw ServiceException.forbidden("NOT_AN_OPERATOR",
                    "This action is only available to valet floor staff.");
        }
        if (caller.companyId() == null) {
            throw ServiceException.forbidden("NO_TENANT",
                    "Your account is not linked to a company.");
        }

        return drivers
                .findByRoleAndCompanyIdAndActiveTrueOrderByNameAsc(Role.DRIVER, caller.companyId())
                .stream()
                .map(DriverSummary::from)
                .toList();
    }
}
