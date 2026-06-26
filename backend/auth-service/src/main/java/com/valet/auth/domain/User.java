package com.valet.auth.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * Identity record. Owns credentials (password hash) and tenancy claims
 * (company_id, location_id) — the Auth service is now the system of record
 * for these, replacing Supabase Auth.
 */
@Entity
@Table(name = "users")
public class User {

    @Id
    @Column(nullable = false, updatable = false)
    private UUID id;

    /**
     * Stored lower-cased (enforced by a CHECK + the citext-like lowering in the
     * service layer). Unique index lives in the Flyway migration.
     */
    // DB column is citext (case-insensitive). Declare the columnDefinition so
    // Hibernate's ddl-auto=validate doesn't reject it as a varchar mismatch.
    @Column(nullable = false, unique = true, columnDefinition = "citext")
    private String email;

    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    // RoleConverter maps the uppercase Java enum to the lowercase PG user_role
    // value. columnDefinition keeps ddl-auto=validate happy with the native enum.
    @Convert(converter = RoleConverter.class)
    @Column(nullable = false, columnDefinition = "user_role")
    private Role role;

    @Column(name = "company_id")
    private UUID companyId;

    @Column(name = "location_id")
    private UUID locationId;

    @Column(nullable = false)
    private String name;

    @Column(name = "is_active", nullable = false)
    private boolean active = true;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected User() {
        // JPA
    }

    public User(UUID id, String email, String passwordHash, Role role,
                UUID companyId, UUID locationId, String name, boolean active) {
        this.id = id;
        this.email = email;
        this.passwordHash = passwordHash;
        this.role = role;
        this.companyId = companyId;
        this.locationId = locationId;
        this.name = name;
        this.active = active;
    }

    @PrePersist
    void onCreate() {
        Instant now = Instant.now();
        if (this.createdAt == null) {
            this.createdAt = now;
        }
        this.updatedAt = now;
    }

    @PreUpdate
    void onUpdate() {
        this.updatedAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public String getEmail() {
        return email;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public void setPasswordHash(String passwordHash) {
        this.passwordHash = passwordHash;
    }

    public Role getRole() {
        return role;
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

    public void setName(String name) {
        this.name = name;
    }

    public boolean isActive() {
        return active;
    }

    public void setActive(boolean active) {
        this.active = active;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
