package com.valet.auth.dto;

import com.valet.auth.domain.Contract;

import java.util.UUID;

/**
 * Wire shape for a contract, enriched with the location name/city/state for the
 * card display: {@code { id, locationId, locationName, locationCity,
 * locationState, name, type, status, active, managerName, managerPhone,
 * managerEmail }}.
 */
public record ContractResponse(
        UUID id,
        UUID locationId,
        String locationName,
        String locationCity,
        String locationState,
        String name,
        String type,
        String status,
        boolean active,
        String managerName,
        String managerPhone,
        String managerEmail
) {
    public static ContractResponse from(Contract c, String locName, String locCity,
                                        String locState) {
        return new ContractResponse(
                c.getId(), c.getLocationId(), locName, locCity, locState,
                c.getName(), c.getType(), c.getStatus(), c.isActive(),
                c.getManagerName(), c.getManagerPhone(), c.getManagerEmail());
    }
}
