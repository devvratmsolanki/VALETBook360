package com.valet.transaction.controller;

import com.valet.transaction.dto.AssignDriverRequest;
import com.valet.transaction.dto.CreateTransactionRequest;
import com.valet.transaction.dto.TransactionMapper;
import com.valet.transaction.dto.TransactionResponse;
import com.valet.transaction.exception.ServiceException;
import com.valet.transaction.security.AuthPrincipal;
import com.valet.transaction.security.SecurityUtils;
import com.valet.transaction.service.TransactionService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Operator-facing floor endpoints (the live floor). Every endpoint is strictly
 * tenant-scoped: companyId / locationId are derived from the JWT principal and
 * NEVER from the request body. Ownership of each loaded transaction is enforced
 * in the service (403 on a cross-tenant mismatch); illegal lifecycle moves
 * return 409.
 *
 * <p><strong>Authorization (defence-in-depth, three layers).</strong>
 * <ol>
 *   <li>Security chain ({@code SecurityConfig}): {@code /api/operator/**} requires
 *       {@code ROLE_VALET}, {@code ROLE_MANAGER}, or {@code ROLE_ADMIN} — rejects
 *       driver tokens before this controller is reached.</li>
 *   <li>{@code @PreAuthorize} below (layer 2): same role check at the
 *       method-security level, enforced by Spring AOP after the filter chain
 *       but before the controller method body runs.</li>
 *   <li>{@code operatorPrincipal()} (layer 3): validates role + mandatory
 *       companyId so the NOT_AN_OPERATOR / NO_TENANT error codes and userMessages
 *       are returned precisely for any edge-case principal that slips through.</li>
 * </ol>
 * </p>
 */
@PreAuthorize("hasAnyRole('VALET', 'MANAGER', 'ADMIN')")
@RestController
@RequestMapping("/api/operator")
public class OperatorController {

    /** Roles allowed to drive the operator floor. Drivers are excluded. */
    private static final Set<String> OPERATOR_ROLES = Set.of("valet", "manager", "admin");

    private final TransactionService service;

    public OperatorController(TransactionService service) {
        this.service = service;
    }

    // --- reads -------------------------------------------------------------

    /** The active floor feed: all non-terminal transactions for the caller's company, newest first. */
    @GetMapping("/transactions")
    public List<TransactionResponse> activeFloor() {
        AuthPrincipal principal = operatorPrincipal();
        return service.getActiveFloor(principal.companyId()).stream()
                .map(TransactionMapper::toResponse)
                .toList();
    }

    /**
     * Full company transaction history (every status, newest first, recent 500).
     * Powers the company panel Dashboard / Transactions / Analytics tabs.
     * Tenant-scoped to the caller's company.
     */
    @GetMapping("/transactions/history")
    public List<TransactionResponse> history() {
        AuthPrincipal principal = operatorPrincipal();
        return service.getCompanyHistory(principal.companyId()).stream()
                .map(TransactionMapper::toResponse)
                .toList();
    }

    // --- writes ------------------------------------------------------------

    /** Operator check-in. Status forced to waiting_for_driver; tenant from the principal. */
    @PostMapping("/transactions")
    public ResponseEntity<TransactionResponse> create(@Valid @RequestBody CreateTransactionRequest body) {
        AuthPrincipal principal = operatorPrincipal();
        var tx = service.createForOperator(body, principal.companyId(), principal.locationId());
        return ResponseEntity.status(201).body(TransactionMapper.toResponse(tx));
    }

    @PostMapping("/transactions/{id}/park")
    public ResponseEntity<TransactionResponse> park(@PathVariable UUID id) {
        return ok(service.operatorPark(id, companyId()));
    }

    @PostMapping("/transactions/{id}/key-in")
    public ResponseEntity<TransactionResponse> keyIn(@PathVariable UUID id) {
        return ok(service.operatorKeyIn(id, companyId()));
    }

    @PostMapping("/transactions/{id}/request")
    public ResponseEntity<TransactionResponse> request(@PathVariable UUID id) {
        return ok(service.operatorRequest(id, companyId()));
    }

    @PostMapping("/transactions/{id}/assign")
    public ResponseEntity<TransactionResponse> assign(@PathVariable UUID id,
                                                      @Valid @RequestBody AssignDriverRequest body) {
        return ok(service.operatorAssign(id, companyId(), body.driverId()));
    }

    /**
     * Assign a driver to PARK an incoming car (intake side). Sets
     * {@code parked_by_driver_id}; the car stays {@code waiting_for_driver}
     * until that driver confirms it parked.
     */
    @PostMapping("/transactions/{id}/assign-park")
    public ResponseEntity<TransactionResponse> assignPark(@PathVariable UUID id,
                                                          @Valid @RequestBody AssignDriverRequest body) {
        return ok(service.operatorAssignPark(id, companyId(), body.driverId()));
    }

    @PostMapping("/transactions/{id}/cancel")
    public ResponseEntity<TransactionResponse> cancel(@PathVariable UUID id) {
        return ok(service.operatorCancel(id, companyId()));
    }

    // --- helpers -----------------------------------------------------------

    private static ResponseEntity<TransactionResponse> ok(
            com.valet.transaction.domain.ValetTransaction tx) {
        return ResponseEntity.ok(TransactionMapper.toResponse(tx));
    }

    private UUID companyId() {
        return operatorPrincipal().companyId();
    }

    /**
     * Resolve the caller and assert they are an operator with a tenant. Drivers
     * (and any other role) are forbidden (403); a principal without a companyId
     * cannot be tenant-scoped, so it is also forbidden (403).
     */
    private AuthPrincipal operatorPrincipal() {
        AuthPrincipal principal = SecurityUtils.currentPrincipal();
        String role = principal.role() == null ? "" : principal.role().toLowerCase();
        if (!OPERATOR_ROLES.contains(role)) {
            throw ServiceException.forbidden("NOT_AN_OPERATOR",
                    "This action is only available to valet floor staff.");
        }
        if (principal.companyId() == null) {
            throw ServiceException.forbidden("NO_TENANT",
                    "Your account is not linked to a company.");
        }
        return principal;
    }
}
