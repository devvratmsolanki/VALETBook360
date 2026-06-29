package com.valet.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.UUID;

/** Create a contract under a company. {@code locationId} is optional. */
public record CreateContractRequest(
        UUID locationId,
        @NotBlank @Size(max = 200) String name,
        @Size(max = 80) String type,
        @Size(max = 80) String status,
        Boolean active,
        @Size(max = 120) String managerName,
        // Optional: @Pattern/@Email skip null, so absent values stay valid; only
        // a supplied value is format-checked.
        @Size(max = 40) @Pattern(regexp = "^[+\\d\\s\\-()]{7,20}$",
                message = "managerPhone is not a valid phone number") String managerPhone,
        @Size(max = 200) @Email String managerEmail
) {
}
