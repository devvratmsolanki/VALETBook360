package com.valet.auth.domain;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Canonical role names, preserved exactly from the legacy Supabase
 * {@code users.role} column: admin, manager, valet, driver.
 *
 * <p><b>Case contract:</b> the wire value (JSON request/response + the JWT
 * {@code role} claim) and the PostgreSQL {@code user_role} enum value are BOTH
 * lowercase ({@code admin|manager|valet|driver}). The Java constant is uppercase
 * by convention. {@link #wire()} / {@link #fromWire(String)} bridge the two, and
 * Jackson (@JsonValue/@JsonCreator) + the DB {@code RoleConverter} use them so a
 * lowercase value is the only thing ever seen outside this class.</p>
 *
 * <p>NOTE on the legacy naming skew (see CLAUDE.md): the old React frontend
 * displayed {@code manager} as "company". That UI synonym is intentionally NOT
 * stored here — the canonical name is the source of truth. The "company owner"
 * with staff-creation rights is {@link #MANAGER}.</p>
 */
public enum Role {
    ADMIN,
    MANAGER,
    VALET,
    DRIVER;

    /** Lowercase wire/DB value (the shared contract form). */
    @JsonValue
    public String wire() {
        return name().toLowerCase();
    }

    /** Parse a wire/DB value case-insensitively. Accepts admin/ADMIN/Admin. */
    @JsonCreator
    public static Role fromWire(String value) {
        if (value == null) {
            return null;
        }
        return Role.valueOf(value.trim().toUpperCase());
    }

    /**
     * Roles permitted to create (register) new staff accounts.
     * Mirrors the legacy create-staff edge function: only admin/manager.
     */
    public boolean canCreateStaff() {
        return this == ADMIN || this == MANAGER;
    }

    /** Admin may provision any tenant; manager is bound to its own company. */
    public boolean isTenantBound() {
        return this == MANAGER;
    }
}
