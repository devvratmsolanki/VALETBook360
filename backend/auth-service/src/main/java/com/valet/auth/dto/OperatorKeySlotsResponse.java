package com.valet.auth.dto;

import java.util.List;
import java.util.UUID;

/**
 * The effective key-slot pool for an operator's own location, used by the
 * operator panel to render the slot grid and auto-assign a code on park.
 *
 * <p>{@code slots} is the ORDERED list of slot names the location uses: the
 * custom {@code key_slots} names (sorted) when the company has set them up, or
 * the generated sequence {@code "1".."keyCapacity"} as the default. The operator
 * never sees the other slot endpoints (those are admin/manager-only); this is the
 * single read-only projection a valet is allowed, scoped to their JWT location.</p>
 */
public record OperatorKeySlotsResponse(
        UUID locationId,
        int keyCapacity,
        List<String> slots
) {
}
