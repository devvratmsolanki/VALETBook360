package com.valet.transaction.dto;

import java.time.Instant;
import java.util.UUID;

/**
 * Full transaction representation returned by transition endpoints and the
 * debug GET. camelCase JSON ↔ snake_case DB, mirroring the legacy service
 * mapping convention. Timestamps are UTC instants serialised as ISO-8601.
 */
public record TransactionResponse(
        UUID id,
        UUID companyId,
        UUID locationId,
        String carPlate,
        String carMake,
        String carModel,
        String carColor,
        String keyCode,
        String status,
        UUID parkedByDriverId,
        UUID retrievedByDriverId,
        String guestName,
        String guestPhone,
        Instant requestedAt,
        Instant arrivedAt,
        Instant deliveredAt,
        Instant createdAt,
        Instant updatedAt
) {
}
