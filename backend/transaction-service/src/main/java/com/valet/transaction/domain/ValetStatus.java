package com.valet.transaction.domain;

import java.util.Collections;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.Map;
import java.util.Set;

/**
 * The canonical valet lifecycle, preserved <em>exactly</em> from the legacy
 * {@code transactionService.js} {@code STATUS_FLOW} / {@code LEGAL_TRANSITIONS}:
 *
 * <pre>
 *   waiting_for_driver -> parked -> key_in -> requested
 *                      -> driver_assigned -> en_route -> arrived -> delivered
 *   (any non-terminal) -> cancelled
 *   parked -> requested            (guest requests while key still with driver)
 * </pre>
 *
 * <p>The {@link #LEGAL_TRANSITIONS} map is the single source of truth for what
 * moves are allowed; the service guard consults it and the Postgres
 * {@code BEFORE UPDATE} trigger enforces the same map at the database. Illegal
 * transitions are rejected with HTTP 409.</p>
 *
 * <p>{@code delivered} and {@code cancelled} are terminal — no outgoing edges.</p>
 */
public enum ValetStatus {

    WAITING_FOR_DRIVER("waiting_for_driver"),
    PARKED("parked"),
    KEY_IN("key_in"),
    REQUESTED("requested"),
    DRIVER_ASSIGNED("driver_assigned"),
    EN_ROUTE("en_route"),
    ARRIVED("arrived"),
    DELIVERED("delivered"),
    CANCELLED("cancelled");

    private final String dbValue;

    ValetStatus(String dbValue) {
        this.dbValue = dbValue;
    }

    /** The snake_case value stored in the {@code valet_status} Postgres enum. */
    public String dbValue() {
        return dbValue;
    }

    /** Terminal states have no legal outgoing transitions. */
    public boolean isTerminal() {
        return this == DELIVERED || this == CANCELLED;
    }

    /**
     * The legal-transition adjacency map. Every non-terminal status may move to
     * {@code CANCELLED}; the forward lifecycle edges follow the diagram above.
     * Immutable and shared.
     */
    public static final Map<ValetStatus, Set<ValetStatus>> LEGAL_TRANSITIONS;

    static {
        EnumMap<ValetStatus, Set<ValetStatus>> m = new EnumMap<>(ValetStatus.class);
        m.put(WAITING_FOR_DRIVER, EnumSet.of(PARKED, CANCELLED));
        m.put(PARKED, EnumSet.of(KEY_IN, REQUESTED, CANCELLED));
        m.put(KEY_IN, EnumSet.of(REQUESTED, CANCELLED));
        m.put(REQUESTED, EnumSet.of(DRIVER_ASSIGNED, CANCELLED));
        m.put(DRIVER_ASSIGNED, EnumSet.of(EN_ROUTE, CANCELLED));
        m.put(EN_ROUTE, EnumSet.of(ARRIVED, CANCELLED));
        m.put(ARRIVED, EnumSet.of(DELIVERED, CANCELLED));
        m.put(DELIVERED, EnumSet.noneOf(ValetStatus.class));
        m.put(CANCELLED, EnumSet.noneOf(ValetStatus.class));

        // Deep-immutable view.
        EnumMap<ValetStatus, Set<ValetStatus>> immutable = new EnumMap<>(ValetStatus.class);
        m.forEach((k, v) -> immutable.put(k, Collections.unmodifiableSet(v)));
        LEGAL_TRANSITIONS = Collections.unmodifiableMap(immutable);
    }

    /** Whether {@code from -> to} is a legal edge in the lifecycle. */
    public static boolean isLegalTransition(ValetStatus from, ValetStatus to) {
        if (from == null || to == null) {
            return false;
        }
        return LEGAL_TRANSITIONS.getOrDefault(from, Set.of()).contains(to);
    }

    /** Resolve from the snake_case DB / wire value; throws if unknown. */
    public static ValetStatus fromDbValue(String value) {
        if (value != null) {
            for (ValetStatus s : values()) {
                if (s.dbValue.equals(value)) {
                    return s;
                }
            }
        }
        throw new IllegalArgumentException("Unknown valet status: " + value);
    }
}
