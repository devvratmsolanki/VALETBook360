package com.valet.auth.dto;

import com.valet.auth.domain.Role;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.UUID;

/**
 * Admin/manager-gated staff creation. Mirrors the legacy create-staff edge
 * function payload: email, password, name, role, company_id, location_id.
 *
 * <p>Password policy matches legacy {@code isValidPassword}: 8+ chars with at
 * least one letter and one digit.</p>
 */
public record RegisterRequest(
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

        // Tenancy. May be null only when an admin creates another admin.
        UUID companyId,

        UUID locationId
) {
}
