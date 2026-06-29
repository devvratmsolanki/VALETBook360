package com.valet.auth.dto;

import jakarta.validation.constraints.Max;
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

        // Upper-bounded so a caller can never request billions of generated
        // numeric key slots (operatorKeySlots streams 1..keyCapacity) → OOM.
        @PositiveOrZero @Max(10_000)
        int keyCapacity
) {
}
