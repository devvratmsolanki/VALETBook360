package com.valet.auth.dto;

import com.valet.auth.domain.User;

import java.util.UUID;

/**
 * Public profile projection — never exposes the password hash. This is the
 * {@code GET /auth/me} body and the embedded user in token responses, carrying
 * the same role + tenancy claims the JWT does.
 */
public record UserResponse(
        UUID id,
        String email,
        String name,
        String role,
        UUID companyId,
        UUID locationId,
        boolean active
) {
    public static UserResponse from(User u) {
        return new UserResponse(
                u.getId(),
                u.getEmail(),
                u.getName(),
                u.getRole().wire(),
                u.getCompanyId(),
                u.getLocationId(),
                u.isActive()
        );
    }
}
