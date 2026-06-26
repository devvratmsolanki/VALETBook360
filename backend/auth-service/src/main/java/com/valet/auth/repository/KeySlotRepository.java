package com.valet.auth.repository;

import com.valet.auth.domain.KeySlot;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface KeySlotRepository extends JpaRepository<KeySlot, UUID> {

    /** All slots for a location, in display order (sort_order then name). */
    List<KeySlot> findByLocationIdOrderBySortOrderAscSlotNameAsc(UUID locationId);

    /** Current slot count for a location (used to default the bulk start seq). */
    long countByLocationId(UUID locationId);
}
