package com.valet.auth.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * A company's physical valet site — the legacy {@code locations} table.
 * {@code key_capacity} feeds the numeric key-slot fallback in the operator flow.
 */
@Entity
@Table(name = "locations")
public class Location {

    @Id
    @Column(nullable = false, updatable = false)
    private UUID id;

    @Column(name = "valet_company_id", nullable = false)
    private UUID companyId;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "address")
    private String address;

    @Column(name = "city")
    private String city;

    @Column(name = "state")
    private String state;

    @Column(name = "country")
    private String country;

    @Column(name = "key_capacity", nullable = false)
    private int keyCapacity;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    protected Location() {
        // JPA
    }

    public Location(UUID id, UUID companyId, String name, String address, String city,
                    String state, String country, int keyCapacity) {
        this.id = id;
        this.companyId = companyId;
        this.name = name;
        this.address = address;
        this.city = city;
        this.state = state;
        this.country = country;
        this.keyCapacity = keyCapacity;
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

    public UUID getCompanyId() {
        return companyId;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getAddress() {
        return address;
    }

    public void setAddress(String address) {
        this.address = address;
    }

    public String getCity() {
        return city;
    }

    public void setCity(String city) {
        this.city = city;
    }

    public String getState() {
        return state;
    }

    public void setState(String state) {
        this.state = state;
    }

    public String getCountry() {
        return country;
    }

    public void setCountry(String country) {
        this.country = country;
    }

    public int getKeyCapacity() {
        return keyCapacity;
    }

    public void setKeyCapacity(int keyCapacity) {
        this.keyCapacity = keyCapacity;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
