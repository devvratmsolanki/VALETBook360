package com.valet.auth.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

/**
 * Bulk key-slot generator input (legacy "Bulk Key Slot Setup"). Generates
 * {@code count} slots named {@code <prefix><startFrom + i>} with matching
 * sort order. {@code prefix} may be blank (→ plain numbers). The service clamps
 * {@code count} to [0, 500]; the bean bounds guard absurd payloads first.
 */
public record BulkGenerateSlotsRequest(
        String prefix,
        @Min(1) @Max(500) int count,
        @Min(0) int startFrom
) {
}
