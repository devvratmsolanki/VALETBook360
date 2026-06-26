package com.valet.transaction.controller;

import com.valet.transaction.dto.DriverAssignmentResponse;
import com.valet.transaction.dto.TransactionMapper;
import com.valet.transaction.dto.TransactionResponse;
import com.valet.transaction.security.AuthPrincipal;
import com.valet.transaction.security.SecurityUtils;
import com.valet.transaction.service.TransactionService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Driver-facing mission endpoints. The security chain has already enforced
 * {@code role=driver}; here {@code driverId = JWT sub}. Ownership of each
 * specific transaction is enforced in the service (403 on mismatch); illegal
 * lifecycle moves return 409.
 */
@RestController
@RequestMapping("/api/driver")
public class DriverController {

    private final TransactionService service;

    public DriverController(TransactionService service) {
        this.service = service;
    }

    @GetMapping("/assignments")
    public List<DriverAssignmentResponse> assignments() {
        UUID driverId = driverId();
        return service.getDriverAssignments(driverId).stream()
                .map(TransactionMapper::toAssignment)
                .toList();
    }

    @PostMapping("/transactions/{id}/en-route")
    public ResponseEntity<TransactionResponse> enRoute(@PathVariable UUID id) {
        return ResponseEntity.ok(
                TransactionMapper.toResponse(service.driverEnRoute(id, driverId())));
    }

    /**
     * The assigned PARK driver confirms the incoming car is parked:
     * {@code waiting_for_driver → parked}. Ownership ({@code parked_by_driver_id})
     * is enforced in the service (403 on mismatch).
     */
    @PostMapping("/transactions/{id}/parked")
    public ResponseEntity<TransactionResponse> parked(@PathVariable UUID id) {
        return ResponseEntity.ok(
                TransactionMapper.toResponse(service.driverConfirmParked(id, driverId())));
    }

    @PostMapping("/transactions/{id}/arrived")
    public ResponseEntity<TransactionResponse> arrived(@PathVariable UUID id) {
        return ResponseEntity.ok(
                TransactionMapper.toResponse(service.driverArrived(id, driverId())));
    }

    @PostMapping("/transactions/{id}/delivered")
    public ResponseEntity<TransactionResponse> delivered(@PathVariable UUID id) {
        return ResponseEntity.ok(
                TransactionMapper.toResponse(service.driverDelivered(id, driverId())));
    }

    private UUID driverId() {
        AuthPrincipal principal = SecurityUtils.currentPrincipal();
        return principal.driverId();
    }
}
