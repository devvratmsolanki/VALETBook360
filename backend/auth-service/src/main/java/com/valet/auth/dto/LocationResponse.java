package com.valet.auth.dto;

import com.valet.auth.domain.Location;

import java.time.Instant;
import java.util.UUID;

/**
 * Location projection. {@code companyName} is populated only for the admin
 * "all locations across all companies" view (grouped display); it is null on
 * the per-company endpoints where the company is already the context.
 */
public record LocationResponse(
        UUID id,
        UUID companyId,
        String companyName,
        String name,
        String address,
        String city,
        String state,
        String country,
        int keyCapacity,
        Instant createdAt
) {
    public static LocationResponse from(Location l) {
        return from(l, null);
    }

    public static LocationResponse from(Location l, String companyName) {
        return new LocationResponse(
                l.getId(),
                l.getCompanyId(),
                companyName,
                l.getName(),
                l.getAddress(),
                l.getCity(),
                l.getState(),
                l.getCountry(),
                l.getKeyCapacity(),
                l.getCreatedAt()
        );
    }
}
