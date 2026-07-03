package com.valet.transaction.controller;

import com.valet.transaction.dto.TransactionMapper;
import com.valet.transaction.dto.TransactionResponse;
import com.valet.transaction.exception.ServiceException;
import com.valet.transaction.security.AuthPrincipal;
import com.valet.transaction.security.SecurityUtils;
import com.valet.transaction.service.TransactionService;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@PreAuthorize("hasAnyRole('FACILITY_OWNER', 'MANAGER', 'ADMIN')")
@RestController
@RequestMapping("/api/facility-owner")
public class FacilityOwnerController {

    private final TransactionService service;

    public FacilityOwnerController(TransactionService service) {
        this.service = service;
    }

    /** Active (non-terminal) transactions across all the caller's locations. */
    @GetMapping("/transactions")
    public List<TransactionResponse> activeFloor() {
        return service.getActiveFloorByLocations(locationIds())
                .stream().map(TransactionMapper::toResponse).toList();
    }

    /** Full transaction history across all the caller's locations (newest 200). */
    @GetMapping("/transactions/history")
    public List<TransactionResponse> history() {
        return service.getLocationHistory(locationIds())
                .stream().map(TransactionMapper::toResponse).toList();
    }

    private List<UUID> locationIds() {
        AuthPrincipal p = SecurityUtils.currentPrincipal();
        List<UUID> ids = p.locationIds();
        if (ids == null || ids.isEmpty()) {
            throw ServiceException.forbidden("NO_LOCATION",
                    "Your account is not assigned to any location.");
        }
        return ids;
    }
}
