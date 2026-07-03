package com.valet.transaction.repository;

import com.valet.transaction.domain.ValetStatus;
import com.valet.transaction.domain.ValetTransaction;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface ValetTransactionRepository extends JpaRepository<ValetTransaction, UUID> {

    /**
     * A driver's active retrieval missions, newest first. Backed by the
     * {@code (retrieved_by_driver_id, status)} index. Status filter is the
     * retrieval-in-flight set: driver_assigned, en_route, arrived.
     */
    List<ValetTransaction> findByRetrievedByDriverIdAndStatusInOrderByCreatedAtDesc(
            UUID retrievedByDriverId, Collection<ValetStatus> statuses);

    /**
     * A driver's active PARK (intake) missions, newest first: cars assigned to
     * this driver to park that are still awaiting parking. Backed by the
     * {@code ix_tx_parker_status (parked_by_driver_id, status)} partial index
     * (added in V4). Status filter is the intake set (currently just
     * {@code waiting_for_driver}).
     */
    List<ValetTransaction> findByParkedByDriverIdAndStatusInOrderByCreatedAtDesc(
            UUID parkedByDriverId, Collection<ValetStatus> statuses);

    /**
     * The operator "active floor" feed for one location, oldest first (the
     * floor is a work queue: the longest-waiting car surfaces at the top).
     * Scoped strictly to a single tenant + location + the active-status set.
     * Partially covered by {@code ix_tx_company_status_created
     * (company_id, status, created_at)}; the extra {@code location_id} predicate
     * is a cheap residual filter — no new index is warranted.
     */
    List<ValetTransaction> findByCompanyIdAndLocationIdAndStatusInOrderByCreatedAtAsc(
            UUID companyId, UUID locationId, Collection<ValetStatus> statuses);

    /**
     * The operator "active floor" feed for one tenant: every transaction whose
     * status is NOT in the terminal set (delivered, cancelled), newest first.
     * Scoped strictly to a single company (derived from the JWT principal).
     * Covered by {@code ix_tx_company_status_created (company_id, status,
     * created_at)}.
     */
    List<ValetTransaction> findByCompanyIdAndStatusNotInOrderByCreatedAtDesc(
            UUID companyId, Collection<ValetStatus> statuses);

    /**
     * Full transaction history for one company (ALL statuses incl.
     * delivered/cancelled), newest first, paginated. Powers the company panel's
     * Dashboard stats, Transactions tab, and Analytics aggregation.
     * Covered by {@code ix_tx_company_status_created}.
     */
    List<ValetTransaction> findByCompanyIdOrderByCreatedAtDesc(UUID companyId, Pageable pageable);

    /**
     * Guest lookup: find the most recent non-terminal transaction matching plate
     * (case-insensitive) + last 4 digits. Both sides use RIGHT(…, 4) so:
     *  - Operator may store full number or only 4 digits.
     *  - Guest may enter full number or only last 4 digits.
     * Either combination resolves correctly.
     */
    @Query("SELECT t FROM ValetTransaction t WHERE UPPER(t.carPlate) = UPPER(:plate) AND RIGHT(t.guestPhone, 4) = RIGHT(:last4, 4) AND t.status NOT IN :terminal ORDER BY t.createdAt DESC LIMIT 1")
    Optional<ValetTransaction> findActiveByPlateAndLast4(@Param("plate") String plate, @Param("last4") String last4, @Param("terminal") Collection<ValetStatus> terminal);

    /** Guest status poll: most recent transaction for this plate+phone, including terminal states. */
    @Query("SELECT t FROM ValetTransaction t WHERE UPPER(t.carPlate) = UPPER(:plate) AND RIGHT(t.guestPhone, 4) = RIGHT(:last4, 4) ORDER BY t.createdAt DESC LIMIT 1")
    Optional<ValetTransaction> findMostRecentByPlateAndLast4(@Param("plate") String plate, @Param("last4") String last4);

    /** A driver's delivered-car history, most recently delivered first, paginated. */
    List<ValetTransaction> findByRetrievedByDriverIdAndStatusInOrderByDeliveredAtDesc(
            UUID retrievedByDriverId, Collection<ValetStatus> statuses, Pageable pageable);

    /** Active non-terminal transactions across a set of locations (facility owner view), newest first. */
    List<ValetTransaction> findByLocationIdInAndStatusNotInOrderByCreatedAtDesc(
            Collection<UUID> locationIds, Collection<ValetStatus> statuses);

    /** Transaction history across a set of locations, newest first, capped at 200. */
    @org.springframework.data.jpa.repository.Query(
            "SELECT t FROM ValetTransaction t WHERE t.locationId IN :locationIds ORDER BY t.createdAt DESC LIMIT 200")
    List<ValetTransaction> findTop200ByLocationIds(
            @org.springframework.data.repository.query.Param("locationIds") Collection<UUID> locationIds);
}
