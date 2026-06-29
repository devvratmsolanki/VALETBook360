package com.valet.auth.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;

/**
 * Bulk key-slot generator input (legacy "Bulk Key Slot Setup"). Generates
 * {@code count} slots named {@code <prefix><startFrom + i>} with matching
 * sort order. {@code prefix} may be blank (→ plain numbers). The service clamps
 * {@code count} to [0, 500]; the bean bounds guard absurd payloads first.
 *
 * <p>{@code prefix} is length-bounded so a caller can't persist 500 rows of
 * arbitrarily large slot names, and {@code startFrom} is capped so
 * {@code startFrom + count} can never overflow the {@code int} sortOrder column.</p>
 */
public record BulkGenerateSlotsRequest(
        @Size(max = 64) String prefix,
        @Min(1) @Max(500) int count,
        @Min(0) @Max(1_000_000) int startFrom
) {
}
