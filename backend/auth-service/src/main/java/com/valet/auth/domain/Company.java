package com.valet.auth.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * Tenant root — the legacy {@code valet_companies} table. Lives in the auth DB
 * alongside {@code users} so the super-admin can manage tenants without a second
 * microservice. A company's owner is a {@code users} row with role
 * {@code manager} (the UI's "company" role).
 */
@Entity
@Table(name = "valet_companies")
public class Company {

    @Id
    @Column(nullable = false, updatable = false)
    private UUID id;

    @Column(name = "company_name", nullable = false)
    private String companyName;

    @Column(name = "owner_name")
    private String ownerName;

    @Column(name = "phone")
    private String phone;

    // citext (case-insensitive) to mirror users.email.
    @Column(name = "email", columnDefinition = "citext")
    private String email;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected Company() {
        // JPA
    }

    public Company(UUID id, String companyName, String ownerName, String phone, String email) {
        this.id = id;
        this.companyName = companyName;
        this.ownerName = ownerName;
        this.phone = phone;
        this.email = email;
    }

    @PrePersist
    void onCreate() {
        if (this.createdAt == null) {
            this.createdAt = Instant.now();
        }
    }

    public UUID getId() {
        return id;
    }

    public String getCompanyName() {
        return companyName;
    }

    public void setCompanyName(String companyName) {
        this.companyName = companyName;
    }

    public String getOwnerName() {
        return ownerName;
    }

    public void setOwnerName(String ownerName) {
        this.ownerName = ownerName;
    }

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
