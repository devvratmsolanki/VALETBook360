package com.valet.transaction.security;

import java.util.UUID;

/**
 * The authenticated caller decoded from the access JWT — the shared
 * tenancy/identity context reconstructed from the same token every service
 * reads. For driver endpoints, {@code userId} (= JWT {@code sub}) is the
 * {@code driverId}. Plain record: no Spring coupling.
 */
public record AuthPrincipal(
        UUID userId,
        String role,
        UUID companyId,
        UUID locationId,
        String email,
        String name
) {
    /** Convenience: driver endpoints treat the subject as the driverId. */
    public UUID driverId() {
        return userId;
    }

    public boolean isDriver() {
        return "driver".equalsIgnoreCase(role);
    }
}
