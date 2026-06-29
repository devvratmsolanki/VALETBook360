package com.valet.transaction.repository;

import com.valet.transaction.domain.ValetStatus;
import com.valet.transaction.domain.ValetTransaction;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
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
     * delivered/cancelled), newest first, capped at the most recent 500. Powers
     * the company panel's Dashboard stats, Transactions tab, and Analytics
     * aggregation. Covered by {@code ix_tx_company_status_created}.
     */
    List<ValetTransaction> findTop500ByCompanyIdOrderByCreatedAtDesc(UUID companyId);
}
