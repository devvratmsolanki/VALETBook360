package com.valet.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

/**
 * Create-location payload. The owning company comes from the path
 * ({@code /api/companies/{id}/locations}), never the body, so a manager cannot
 * smuggle another tenant's id here.
 */
public record CreateLocationRequest(
        @NotBlank @Size(max = 200)
        String name,

        @Size(max = 300)
        String address,

        @Size(max = 120)
        String city,

        @Size(max = 120)
        String state,

        @Size(max = 120)
        String country,

        @PositiveOrZero
        int keyCapacity
) {
}
