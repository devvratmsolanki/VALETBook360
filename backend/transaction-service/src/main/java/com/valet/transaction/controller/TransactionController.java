package com.valet.transaction.controller;

import com.valet.transaction.dto.TransactionMapper;
import com.valet.transaction.dto.TransactionResponse;
import com.valet.transaction.security.AuthPrincipal;
import com.valet.transaction.security.SecurityUtils;
import com.valet.transaction.service.TransactionService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * Generic transaction reads. {@code GET /api/transactions/{id}} enforces
 * tenant + role scoping: operator-capable callers (valet/manager/admin) must
 * own the transaction's company; drivers must be the assigned retriever.
 * All other callers — including drivers reading a transaction that isn't
 * theirs — receive 403 {@code NOT_YOUR_TRANSACTION}. The endpoint never
 * reveals whether an id exists to an unauthorized caller.
 */
@RestController
@RequestMapping("/api/transactions")
public class TransactionController {

    private final TransactionService service;

    public TransactionController(TransactionService service) {
        this.service = service;
    }

    @GetMapping("/{id}")
    public ResponseEntity<TransactionResponse> getById(@PathVariable UUID id) {
        AuthPrincipal principal = SecurityUtils.currentPrincipal();
        return ResponseEntity.ok(TransactionMapper.toResponse(service.getByIdScoped(id, principal)));
    }
}
