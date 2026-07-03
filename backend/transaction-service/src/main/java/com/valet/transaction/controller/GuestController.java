package com.valet.transaction.controller;

import com.valet.transaction.dto.TransactionMapper;
import com.valet.transaction.dto.TransactionResponse;
import com.valet.transaction.service.TransactionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Public (unauthenticated) guest portal endpoints. Visitors authenticate by
 * presenting their car plate + last-4-digits of phone; the backend matches
 * against the stored guestPhone column (RIGHT match, handles both full numbers
 * and 4-digit-only storage). Returns only the safe subset via TransactionResponse.
 */
@RestController
@RequestMapping("/api/guest")
public class GuestController {

    private final TransactionService service;

    public GuestController(TransactionService service) {
        this.service = service;
    }

    /**
     * Look up an active booking. Returns the full transaction so the guest portal
     * can render the current status rail immediately.
     */
    @PostMapping("/lookup")
    public TransactionResponse lookup(@Valid @RequestBody GuestRequest body) {
        return TransactionMapper.toResponse(service.guestLookup(body.plate(), body.last4()));
    }

    /**
     * Guest requests their car back. Transitions the transaction to REQUESTED so
     * the operator floor immediately shows the retrieval request. Idempotent once
     * already in REQUESTED or later.
     */
    @PostMapping("/request")
    public TransactionResponse request(@Valid @RequestBody GuestRequest body) {
        return TransactionMapper.toResponse(service.guestRequest(body.plate(), body.last4()));
    }

    /**
     * Status poll endpoint. Uses guestPollStatus so it can return terminal states
     * (delivered, cancelled) — the guest portal stops polling on those and shows
     * the final banner. Using guestLookup here would return 404 once delivered,
     * leaving the guest stuck on the last non-terminal status.
     */
    @PostMapping("/status")
    public TransactionResponse status(@Valid @RequestBody GuestRequest body) {
        return TransactionMapper.toResponse(service.guestPollStatus(body.plate(), body.last4()));
    }

    public record GuestRequest(
            @NotBlank
            @Pattern(regexp = "^[A-Za-z0-9]{2,15}$", message = "Invalid plate")
            String plate,

            @NotBlank
            @Pattern(regexp = "^[0-9]{4,15}$", message = "Enter your last 4 digits or full phone number (digits only)")
            String last4
    ) {}
}
