package com.valet.transaction.dto;

import jakarta.validation.constraints.NotBlank;
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
        @Size(max = 32, message = "carPlate is too long")
        String carPlate,

        @Size(max = 64) String carMake,
        @Size(max = 64) String carModel,
        @Size(max = 32) String carColor,
        @Size(max = 128) String guestName,
        @Size(max = 32) String guestPhone,
        @Size(max = 32) String keyCode
) {
}
