package com.valet.auth.dto;

import com.valet.auth.domain.KeySlot;

import java.util.UUID;

/** Wire shape for a key slot: {@code { id, locationId, slotName, sortOrder }}. */
public record KeySlotResponse(
        UUID id,
        UUID locationId,
        String slotName,
        int sortOrder
) {
    public static KeySlotResponse from(KeySlot s) {
        return new KeySlotResponse(
                s.getId(), s.getLocationId(), s.getSlotName(), s.getSortOrder());
    }
}
