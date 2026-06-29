package com.valet.transaction.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Operator create-transaction body. Deliberately whitelists ONLY the
 * guest/car/key fields an operator may set on check-in — status, tenant
 * (companyId/locationId) and driver assignment are NEVER trusted from the body:
 * status is server-forced to {@code waiting_for_driver} and the tenant is
 * derived from the JWT principal.
 */
public record CreateTransactionRequest(
        @NotBlank(message = "carPlate is required")
        @Pattern(regexp = "^[A-Za-z0-9]{2,15}$",
                message = "carPlate must be 2-15 letters or digits")
        String carPlate,

        @Size(max = 64) String carMake,
        @Size(max = 64) String carModel,
        @Size(max = 32) String carColor,

        // Optional, but length-bounded and free of markup/quote chars so a guest
        // name/phone can't be used to smuggle HTML/SQL-ish payloads.
        @Size(max = 100)
        @Pattern(regexp = "^[^<>\"'&]{0,100}$", message = "guestName contains invalid characters")
        String guestName,

        @Size(max = 100)
        @Pattern(regexp = "^[^<>\"'&]{0,100}$", message = "guestPhone contains invalid characters")
        String guestPhone,

        @Size(max = 32) String keyCode
) {
}
