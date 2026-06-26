package com.valet.auth.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * A company ↔ venue service agreement (the legacy {@code contracts} table).
 * Surfaced in the company panel's Contracts tab.
 */
@Entity
@Table(name = "contracts")
public class Contract {

    @Id
    @Column(nullable = false, updatable = false)
    private UUID id;

    @Column(name = "valet_company_id", nullable = false)
    private UUID companyId;

    @Column(name = "location_id")
    private UUID locationId;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "type")
    private String type;

    @Column(name = "status")
    private String status;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @Column(name = "manager_name")
    private String managerName;

    @Column(name = "manager_phone")
    private String managerPhone;

    @Column(name = "manager_email")
    private String managerEmail;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected Contract() {
        // JPA
    }

    public Contract(UUID id, UUID companyId, UUID locationId, String name, String type,
                    String status, boolean active, String managerName, String managerPhone,
                    String managerEmail) {
        this.id = id;
        this.companyId = companyId;
        this.locationId = locationId;
        this.name = name;
        this.type = type;
        this.status = status;
        this.active = active;
        this.managerName = managerName;
        this.managerPhone = managerPhone;
        this.managerEmail = managerEmail;
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

    public UUID getCompanyId() {
        return companyId;
    }

    public UUID getLocationId() {
        return locationId;
    }

    public String getName() {
        return name;
    }

    public String getType() {
        return type;
    }

    public String getStatus() {
        return status;
    }

    public boolean isActive() {
        return active;
    }

    public String getManagerName() {
        return managerName;
    }

    public String getManagerPhone() {
        return managerPhone;
    }

    public String getManagerEmail() {
        return managerEmail;
    }
}
