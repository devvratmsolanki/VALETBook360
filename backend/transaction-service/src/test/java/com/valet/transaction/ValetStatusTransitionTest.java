package com.valet.transaction;

import com.valet.transaction.domain.ValetStatus;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import java.util.EnumSet;
import java.util.Set;

import static com.valet.transaction.domain.ValetStatus.ARRIVED;
import static com.valet.transaction.domain.ValetStatus.CANCELLED;
import static com.valet.transaction.domain.ValetStatus.DELIVERED;
import static com.valet.transaction.domain.ValetStatus.DRIVER_ASSIGNED;
import static com.valet.transaction.domain.ValetStatus.EN_ROUTE;
import static com.valet.transaction.domain.ValetStatus.KEY_IN;
import static com.valet.transaction.domain.ValetStatus.PARKED;
import static com.valet.transaction.domain.ValetStatus.REQUESTED;
import static com.valet.transaction.domain.ValetStatus.WAITING_FOR_DRIVER;
import static org.assertj.core.api.Assertions.assertThat;

/**
 * The legal-transition map is the heart of the service. These pure unit tests
 * pin every legal edge and assert that everything else is rejected — so an
 * accidental edit to {@link ValetStatus#LEGAL_TRANSITIONS} fails loudly.
 */
class ValetStatusTransitionTest {

    // --- explicit legal edges ---------------------------------------------

    @ParameterizedTest(name = "legal: {0} -> {1}")
    @CsvSource({
            "WAITING_FOR_DRIVER, PARKED",
            "PARKED, KEY_IN",
            "PARKED, REQUESTED",          // guest requests while key still with driver
            "KEY_IN, REQUESTED",
            "REQUESTED, DRIVER_ASSIGNED",
            "DRIVER_ASSIGNED, EN_ROUTE",
            "EN_ROUTE, ARRIVED",
            "ARRIVED, DELIVERED",
            // every non-terminal -> cancelled
            "WAITING_FOR_DRIVER, CANCELLED",
            "PARKED, CANCELLED",
            "KEY_IN, CANCELLED",
            "REQUESTED, CANCELLED",
            "DRIVER_ASSIGNED, CANCELLED",
            "EN_ROUTE, CANCELLED",
            "ARRIVED, CANCELLED"
    })
    void legalTransitionsAreAllowed(ValetStatus from, ValetStatus to) {
        assertThat(ValetStatus.isLegalTransition(from, to)).isTrue();
    }

    // --- representative illegal edges -------------------------------------

    @ParameterizedTest(name = "illegal: {0} -> {1}")
    @CsvSource({
            "WAITING_FOR_DRIVER, KEY_IN",        // skips parked
            "WAITING_FOR_DRIVER, DELIVERED",     // skips the whole flow
            "PARKED, EN_ROUTE",                  // skips requested + driver_assigned
            "KEY_IN, DRIVER_ASSIGNED",           // skips requested
            "REQUESTED, EN_ROUTE",               // skips driver_assigned
            "DRIVER_ASSIGNED, ARRIVED",          // skips en_route
            "EN_ROUTE, DELIVERED",               // skips arrived
            "ARRIVED, REQUESTED",                // backwards
            "DELIVERED, ARRIVED",                // terminal cannot move
            "DELIVERED, CANCELLED",              // terminal cannot be cancelled
            "CANCELLED, PARKED",                 // terminal cannot move
            "PARKED, PARKED",                    // self-loop is not a transition
            "PARKED, WAITING_FOR_DRIVER"         // backwards
    })
    void illegalTransitionsAreRejected(ValetStatus from, ValetStatus to) {
        assertThat(ValetStatus.isLegalTransition(from, to)).isFalse();
    }

    @Test
    void nullsAreNeverLegal() {
        assertThat(ValetStatus.isLegalTransition(null, PARKED)).isFalse();
        assertThat(ValetStatus.isLegalTransition(PARKED, null)).isFalse();
        assertThat(ValetStatus.isLegalTransition(null, null)).isFalse();
    }

    @Test
    void terminalStatesHaveNoOutgoingEdges() {
        assertThat(ValetStatus.LEGAL_TRANSITIONS.get(DELIVERED)).isEmpty();
        assertThat(ValetStatus.LEGAL_TRANSITIONS.get(CANCELLED)).isEmpty();
        assertThat(DELIVERED.isTerminal()).isTrue();
        assertThat(CANCELLED.isTerminal()).isTrue();
    }

    @Test
    void forwardEdgesMatchTheCanonicalDiagramExactly() {
        // Pin the exact out-sets so an unintended edge (added or removed) fails.
        assertThat(ValetStatus.LEGAL_TRANSITIONS.get(WAITING_FOR_DRIVER))
                .isEqualTo(EnumSet.of(PARKED, CANCELLED));
        assertThat(ValetStatus.LEGAL_TRANSITIONS.get(PARKED))
                .isEqualTo(EnumSet.of(KEY_IN, REQUESTED, CANCELLED));
        assertThat(ValetStatus.LEGAL_TRANSITIONS.get(KEY_IN))
                .isEqualTo(EnumSet.of(REQUESTED, CANCELLED));
        assertThat(ValetStatus.LEGAL_TRANSITIONS.get(REQUESTED))
                .isEqualTo(EnumSet.of(DRIVER_ASSIGNED, CANCELLED));
        assertThat(ValetStatus.LEGAL_TRANSITIONS.get(DRIVER_ASSIGNED))
                .isEqualTo(EnumSet.of(EN_ROUTE, CANCELLED));
        assertThat(ValetStatus.LEGAL_TRANSITIONS.get(EN_ROUTE))
                .isEqualTo(EnumSet.of(ARRIVED, CANCELLED));
        assertThat(ValetStatus.LEGAL_TRANSITIONS.get(ARRIVED))
                .isEqualTo(EnumSet.of(DELIVERED, CANCELLED));
    }

    @Test
    void legalTransitionsMapIsImmutable() {
        Set<ValetStatus> out = ValetStatus.LEGAL_TRANSITIONS.get(PARKED);
        try {
            out.add(DELIVERED);
        } catch (UnsupportedOperationException expected) {
            // good — defensive immutability holds
            return;
        }
        // If the add unexpectedly succeeded, the map is mutable: fail.
        assertThat(false).as("LEGAL_TRANSITIONS sets must be immutable").isTrue();
    }
}
