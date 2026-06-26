package com.valet.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Rename a single key slot. */
public record RenameSlotRequest(
        @NotBlank @Size(max = 64) String slotName
) {
}
