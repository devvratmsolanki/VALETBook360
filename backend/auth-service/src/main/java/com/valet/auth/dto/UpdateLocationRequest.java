package com.valet.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

/**
 * Edit-location payload (PUT /api/locations/{id}). Full replacement of the
 * mutable fields; the company a location belongs to is immutable, so it is not
 * accepted here.
 */
public record UpdateLocationRequest(
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
