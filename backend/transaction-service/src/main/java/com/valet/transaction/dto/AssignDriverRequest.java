package com.valet.transaction.dto;

import jakarta.validation.constraints.NotNull;

import java.util.UUID;

/**
 * Operator assign-driver body. The only trusted field is the target driver; the
 * transaction id comes from the path and the tenant from the JWT principal —
 * never the body. The {@code driverId} is the {@code retrieved_by_driver_id}
 * stamped on the transaction as it moves requested → driver_assigned.
 */
public record AssignDriverRequest(
        @NotNull(message = "driverId is required")
        UUID driverId
) {
}
