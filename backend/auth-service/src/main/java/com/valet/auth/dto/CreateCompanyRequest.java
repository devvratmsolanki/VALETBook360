package com.valet.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * ADMIN-only create-company-with-owner payload — the port of the legacy
 * {@code companyService.createCompanyWithOwner}. Creates the
 * {@code valet_companies} row AND the owner auth login (role {@code manager},
 * UI "company") in one transaction.
 *
 * <p>{@code email} is the OWNER's login email (it also defaults the company's
 * contact email). {@code password} policy matches the legacy
 * {@code isValidPassword}: 8+ chars, at least one letter and one digit.</p>
 */
public record CreateCompanyRequest(
        @NotBlank @Size(max = 200)
        String companyName,

        @Size(max = 120)
        String ownerName,

        @Size(max = 40)
        String phone,

        @NotBlank @Email @Size(max = 255)
        String email,

        @NotBlank
        @Size(min = 8, max = 100, message = "Password must be at least 8 characters")
        @Pattern(regexp = "^(?=.*[A-Za-z])(?=.*\\d).+$",
                message = "Password must contain at least one letter and one digit")
        String password
) {
}
