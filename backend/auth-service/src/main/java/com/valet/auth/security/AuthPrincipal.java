package com.valet.auth.security;

import java.util.UUID;

/**
 * The authenticated caller as decoded from the access JWT. This is the shared
 * tenancy/identity context every downstream microservice will reconstruct from
 * the same token. Kept as a plain record so it is trivially serialisable and
 * carries no Spring coupling.
 */
public record AuthPrincipal(
        UUID userId,
        String role,
        UUID companyId,
        UUID locationId,
        String email,
        String name
) {
}
