package com.valet.transaction.dto;

import java.time.Instant;
import java.util.UUID;

/**
 * The driver-assignment item shape from the fixed contract:
 * {@code {id, carPlate, carMake, carModel, carColor, keyCode, status,
 * guestName, locationId, requestedAt, missionType}}. camelCase on the wire.
 *
 * <p>{@code missionType} distinguishes the two driver mission kinds:
 * {@code "park"} (intake — go park this incoming car, status
 * {@code waiting_for_driver}) vs {@code "retrieval"} (go fetch + deliver this
 * car, status {@code driver_assigned → en_route → arrived}). The app renders
 * the right action ("Confirm parked" vs the en-route/arrived/deliver swipe).</p>
 */
public record DriverAssignmentResponse(
        UUID id,
        String carPlate,
        String carMake,
        String carModel,
        String carColor,
        String keyCode,
        String status,
        String guestName,
        UUID locationId,
        Instant requestedAt,
        String missionType
) {
}
