package com.valet.auth.repository;

import com.valet.auth.domain.KeySlot;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface KeySlotRepository extends JpaRepository<KeySlot, UUID> {

    /** All slots for a location, in display order (sort_order then name). */
    List<KeySlot> findByLocationIdOrderBySortOrderAscSlotNameAsc(UUID locationId);

    /** Current slot count for a location (used to default the bulk start seq). */
    long countByLocationId(UUID locationId);

    /**
     * The subset of {@code names} already used by slots at this location — used to
     * pre-empt the {@code ux_slot_name_per_location} unique constraint on bulk
     * generation with a precise SLOT_NAME_TAKEN 409.
     */
    List<KeySlot> findByLocationIdAndSlotNameIn(UUID locationId, Collection<String> names);

    /** True if a DIFFERENT slot at this location already holds {@code slotName} (rename guard). */
    boolean existsByLocationIdAndSlotNameAndIdNot(UUID locationId, String slotName, UUID id);
}
