package com.valet.auth.dto;

import com.valet.auth.domain.User;

import java.util.UUID;

/**
 * Minimal driver projection for the operator's assign-driver picker. Carries
 * ONLY {@code id}, {@code name}, {@code email} — never the password hash, role,
 * tenancy claims, or activity timestamps. The picker shows the name and assigns
 * by {@code id}; email is included only as a disambiguator for same-named
 * drivers. This deliberately leaks no PII beyond what an operator already needs
 * to dispatch a retrieval.
 */
public record DriverSummary(
        UUID id,
        String name,
        String email
) {
    public static DriverSummary from(User u) {
        return new DriverSummary(u.getId(), u.getName(), u.getEmail());
    }
}
