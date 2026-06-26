package com.valet.auth.dto;

import com.valet.auth.domain.User;

import java.util.UUID;

/**
 * User projection for the admin/company management screens. Carries role +
 * tenancy so the Flutter Users screen can bucket users (owners=manager,
 * operators=valet, drivers=driver) under their company. NEVER exposes the
 * password hash. {@code companyName} is filled on the admin hierarchical list.
 */
public record AdminUserResponse(
        UUID id,
        String email,
        String name,
        String role,
        UUID companyId,
        String companyName,
        UUID locationId,
        boolean active
) {
    public static AdminUserResponse from(User u) {
        return from(u, null);
    }

    public static AdminUserResponse from(User u, String companyName) {
        return new AdminUserResponse(
                u.getId(),
                u.getEmail(),
                u.getName(),
                u.getRole().wire(),
                u.getCompanyId(),
                companyName,
                u.getLocationId(),
                u.isActive()
        );
    }
}
