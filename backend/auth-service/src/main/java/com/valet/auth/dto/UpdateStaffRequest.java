package com.valet.auth.dto;

import com.valet.auth.domain.Role;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.UUID;

/**
 * Edit an existing operator ({@code valet}) or driver ({@code driver}) account.
 * The target user comes from the path ({@code PUT /api/users/{id}}); the company
 * is taken from the stored row (never the body) and the caller is authorized
 * against it. {@code role} is validated in-service to be valet|driver — a staff
 * account can't be promoted to manager/admin here. {@code locationId} is optional:
 * supply it to (re)assign the member to a site, or {@code null} to unassign.
 *
 * <p>Email and password are intentionally NOT editable here — email is the login
 * identity, and password changes go through the dedicated self-service flow.</p>
 */
public record UpdateStaffRequest(
        @NotBlank @Size(max = 120)
        String name,

        @NotNull
        Role role,

        UUID locationId
) {
}
