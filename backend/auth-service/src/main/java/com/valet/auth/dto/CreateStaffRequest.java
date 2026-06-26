package com.valet.auth.dto;

import com.valet.auth.domain.Role;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.UUID;

/**
 * Create an operator ({@code valet}) or driver ({@code driver}) login under a
 * company. The company comes from the path ({@code /api/companies/{id}/staff}),
 * not this body. {@code role} is validated in-service to be valet|driver — a
 * manager/admin may not be minted through this staff endpoint. {@code locationId}
 * is optional (pin the staff member to a site).
 */
public record CreateStaffRequest(
        @NotBlank @Email @Size(max = 255)
        String email,

        @NotBlank
        @Size(min = 8, max = 100, message = "Password must be at least 8 characters")
        @Pattern(regexp = "^(?=.*[A-Za-z])(?=.*\\d).+$",
                message = "Password must contain at least one letter and one digit")
        String password,

        @NotBlank @Size(max = 120)
        String name,

        @NotNull
        Role role,

        UUID locationId
) {
}
