package com.valet.auth.dto;

import jakarta.validation.constraints.NotNull;

/** Toggle a user's active flag. */
public record SetActiveRequest(
        @NotNull Boolean active
) {
}
