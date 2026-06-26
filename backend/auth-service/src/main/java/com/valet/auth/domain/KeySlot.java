package com.valet.auth.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * A custom key-storage slot for a location (the legacy {@code key_slots} table).
 * When a location has slots, they replace the generic numeric 1..key_capacity
 * fallback. Created in bulk from the company panel.
 */
@Entity
@Table(name = "key_slots")
public class KeySlot {

    @Id
    @Column(nullable = false, updatable = false)
    private UUID id;

    @Column(name = "location_id", nullable = false)
    private UUID locationId;

    @Column(name = "slot_name", nullable = false)
    private String slotName;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected KeySlot() {
        // JPA
    }

    public KeySlot(UUID id, UUID locationId, String slotName, int sortOrder) {
        this.id = id;
        this.locationId = locationId;
        this.slotName = slotName;
        this.sortOrder = sortOrder;
    }

    @PrePersist
    void onPersist() {
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }

    public UUID getId() {
        return id;
    }

    public UUID getLocationId() {
        return locationId;
    }

    public String getSlotName() {
        return slotName;
    }

    public void setSlotName(String slotName) {
        this.slotName = slotName;
    }

    public int getSortOrder() {
        return sortOrder;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
