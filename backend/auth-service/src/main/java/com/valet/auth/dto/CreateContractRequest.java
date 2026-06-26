package com.valet.auth.dto;

import jakarta.validation.constraints.NotBlank;
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
        @Size(max = 40) String managerPhone,
        @Size(max = 200) String managerEmail
) {
}
