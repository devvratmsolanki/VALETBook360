package com.valet.auth.repository;

import com.valet.auth.domain.Location;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface LocationRepository extends JpaRepository<Location, UUID> {

    /** Locations for one company, name-ordered (company drilldown). */
    List<Location> findByCompanyIdOrderByNameAsc(UUID companyId);

    /** Every location across every company (admin "all locations" view). */
    List<Location> findAllByOrderByNameAsc();

    /** Paged: every location across every company (admin "all locations" view). */
    Page<Location> findAllByOrderByNameAsc(Pageable pageable);

    /** Locations assigned to a specific facility owner (their panel view). */
    List<Location> findByFacilityOwnerIdOrderByNameAsc(UUID facilityOwnerId);
}
