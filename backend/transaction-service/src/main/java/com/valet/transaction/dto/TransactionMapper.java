package com.valet.transaction.dto;

import com.valet.transaction.domain.ValetTransaction;

/**
 * Hand-rolled domain → DTO mapping (snake_case entity ↔ camelCase wire). Kept
 * explicit rather than reflective so the wire contract is reviewable in one
 * place and never accidentally leaks new columns.
 */
public final class TransactionMapper {

    private TransactionMapper() {
    }

    public static DriverAssignmentResponse toAssignment(ValetTransaction t) {
        return new DriverAssignmentResponse(
                t.getId(),
                t.getCarPlate(),
                t.getCarMake(),
                t.getCarModel(),
                t.getCarColor(),
                t.getKeyCode(),
                t.getStatus().dbValue(),
                t.getGuestName(),
                t.getLocationId(),
                t.getRequestedAt(),
                missionType(t)
        );
    }

    /**
     * A {@code waiting_for_driver} car on a driver's list is a PARK (intake)
     * mission; anything else (driver_assigned → arrived) is a RETRIEVAL mission.
     */
    private static String missionType(ValetTransaction t) {
        return t.getStatus() == com.valet.transaction.domain.ValetStatus.WAITING_FOR_DRIVER
                ? "park"
                : "retrieval";
    }

    public static TransactionResponse toResponse(ValetTransaction t) {
        return new TransactionResponse(
                t.getId(),
                t.getCompanyId(),
                t.getLocationId(),
                t.getCarPlate(),
                t.getCarMake(),
                t.getCarModel(),
                t.getCarColor(),
                t.getKeyCode(),
                t.getStatus().dbValue(),
                t.getParkedByDriverId(),
                t.getRetrievedByDriverId(),
                t.getGuestName(),
                t.getGuestPhone(),
                t.getRequestedAt(),
                t.getArrivedAt(),
                t.getDeliveredAt(),
                t.getCreatedAt(),
                t.getUpdatedAt()
        );
    }
}
