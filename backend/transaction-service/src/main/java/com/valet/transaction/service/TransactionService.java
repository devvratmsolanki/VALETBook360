package com.valet.transaction.service;

import com.valet.transaction.domain.ValetStatus;
import com.valet.transaction.domain.ValetTransaction;
import com.valet.transaction.dto.CreateTransactionRequest;
import com.valet.transaction.exception.ServiceException;
import com.valet.transaction.realtime.RealtimeEventPublisher;
import com.valet.transaction.repository.ValetTransactionRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Owns the valet lifecycle: legal-transition enforcement plus the driver- and
 * operator-facing mission operations. The {@link #transition} method is the
 * single chokepoint for every status change — the operator endpoints
 * (park/key-in/request/assign/cancel) and driver endpoints all reuse it so the
 * legal-transition map can never be bypassed.
 *
 * <p>Every committed mutation emits exactly one realtime delta via
 * {@link RealtimeEventPublisher}: {@code emitCreated} on create,
 * {@code emitAssigned} on driver assignment (it pins {@code driver_assigned}),
 * and {@code emitStatus} for every other transition. Emits are registered inside
 * the {@code @Transactional} method so the publisher's {@code afterCommit} hook
 * fires only when the work actually commits.</p>
 */
@Service
public class TransactionService {

    /** Active retrieval statuses surfaced to a driver as "my missions". */
    static final List<ValetStatus> DRIVER_ACTIVE_STATUSES = List.of(
            ValetStatus.DRIVER_ASSIGNED, ValetStatus.EN_ROUTE, ValetStatus.ARRIVED);

    /**
     * Active PARK (intake) statuses surfaced to a driver as a "go park this car"
     * mission: a car assigned to them ({@code parked_by_driver_id}) that is still
     * awaiting parking. Once they confirm the park it becomes {@code parked} and
     * drops off their list.
     */
    static final List<ValetStatus> PARK_ACTIVE_STATUSES = List.of(
            ValetStatus.WAITING_FOR_DRIVER);

    /** Terminal statuses excluded from the operator "active floor" feed. */
    static final List<ValetStatus> TERMINAL_STATUSES = List.of(
            ValetStatus.DELIVERED, ValetStatus.CANCELLED);

    private final ValetTransactionRepository repository;
    private final RealtimeEventPublisher realtime;

    public TransactionService(ValetTransactionRepository repository,
                              RealtimeEventPublisher realtime) {
        this.repository = repository;
        this.realtime = realtime;
    }

    // --- reads -------------------------------------------------------------

    @Transactional(readOnly = true)
    public ValetTransaction getById(UUID id) {
        return repository.findById(id)
                .orElseThrow(() -> ServiceException.notFound(
                        "TX_NOT_FOUND", "That transaction could not be found."));
    }

    /**
     * Tenant- and role-scoped single-transaction read for the generic
     * {@code GET /api/transactions/{id}} endpoint.
     *
     * <p>Access is granted when the caller is:
     * <ul>
     *   <li>An operator-capable role (valet / manager / admin) whose
     *       {@code companyId} matches the transaction's company, OR</li>
     *   <li>The driver currently assigned for retrieval
     *       ({@code retrieved_by_driver_id == principal.userId}).</li>
     * </ul>
     *
     * <p>When the id does not exist <em>or</em> the caller is outside scope,
     * the response is identical — 403 {@code NOT_YOUR_TRANSACTION} — so callers
     * cannot probe for the existence of transactions they don't own. The sole
     * exception: a legitimately-scoped caller who supplies a non-existent id
     * receives the underlying 404 {@code TX_NOT_FOUND} from {@link #getById}.
     */
    @Transactional(readOnly = true)
    public ValetTransaction getByIdScoped(UUID id, com.valet.transaction.security.AuthPrincipal principal) {
        ValetTransaction tx;
        try {
            tx = getById(id);
        } catch (ServiceException ex) {
            // If the caller is not entitled at all, reveal nothing — return 403.
            // Only a legitimately-scoped caller gets the real 404.
            boolean isOperatorRole = !principal.isDriver();
            // We can't check companyId without the tx, so treat not-found as 403
            // for drivers; operators get the 404 (they have a legit reason to know).
            if (isOperatorRole) {
                throw ex; // 404 for operators — they can determine non-existence
            }
            throw ServiceException.forbidden("NOT_YOUR_TRANSACTION",
                    "You don't have access to this transaction.");
        }

        if (principal.isDriver()) {
            // Driver access: must be the assigned retriever OR the assigned parker.
            boolean isRetriever = principal.userId().equals(tx.getRetrievedByDriverId());
            boolean isParker = principal.userId().equals(tx.getParkedByDriverId());
            if (!isRetriever && !isParker) {
                throw ServiceException.forbidden("NOT_YOUR_TRANSACTION",
                        "You don't have access to this transaction.");
            }
        } else {
            // Operator-capable role (valet / manager / admin): must be same company.
            if (!principal.companyId().equals(tx.getCompanyId())) {
                throw ServiceException.forbidden("NOT_YOUR_TRANSACTION",
                        "This transaction belongs to another company.");
            }
        }
        return tx;
    }

    /**
     * A driver's full active mission list, newest first: both PARK (intake)
     * missions — cars assigned to them to park, still {@code waiting_for_driver}
     * — and RETRIEVAL missions (driver_assigned → en_route → arrived). The two
     * sets are disjoint (a car is on at most one side at a time) and merged
     * newest-first by {@code createdAt}.
     */
    @Transactional(readOnly = true)
    public List<ValetTransaction> getDriverAssignments(UUID driverId) {
        List<ValetTransaction> merged = new ArrayList<>();
        merged.addAll(repository.findByParkedByDriverIdAndStatusInOrderByCreatedAtDesc(
                driverId, PARK_ACTIVE_STATUSES));
        merged.addAll(repository.findByRetrievedByDriverIdAndStatusInOrderByCreatedAtDesc(
                driverId, DRIVER_ACTIVE_STATUSES));
        merged.sort((a, b) -> {
            Instant ca = a.getCreatedAt();
            Instant cb = b.getCreatedAt();
            if (ca == null && cb == null) return 0;
            if (ca == null) return 1;
            if (cb == null) return -1;
            return cb.compareTo(ca); // newest first
        });
        return merged;
    }

    /**
     * The operator "active floor" feed for one tenant: every non-terminal
     * transaction (not delivered/cancelled) for the company, newest first.
     * Strictly tenant-scoped — companyId comes from the caller's principal.
     */
    @Transactional(readOnly = true)
    public List<ValetTransaction> getActiveFloor(UUID companyId) {
        return repository.findByCompanyIdAndStatusNotInOrderByCreatedAtDesc(
                companyId, TERMINAL_STATUSES);
    }

    /**
     * Full transaction history for one company (every status, newest first,
     * most-recent 500). Tenant-scoped — companyId comes from the caller's
     * principal. Powers the company panel's Dashboard, Transactions, and
     * (client-aggregated) Analytics tabs.
     */
    @Transactional(readOnly = true)
    public List<ValetTransaction> getCompanyHistory(UUID companyId) {
        return repository.findTop500ByCompanyIdOrderByCreatedAtDesc(companyId);
    }

    // --- operator floor operations ----------------------------------------

    /**
     * Operator check-in: create a fresh transaction. Status is server-forced to
     * {@code waiting_for_driver}; the tenant ({@code companyId}/{@code locationId})
     * is taken from the caller's principal, never the request body. Emits
     * {@code tx:created} after commit.
     */
    @Transactional
    public ValetTransaction createForOperator(CreateTransactionRequest req,
                                               UUID companyId, UUID locationId) {
        ValetTransaction tx = new ValetTransaction();
        tx.setCompanyId(companyId);
        tx.setLocationId(locationId);
        tx.setCarPlate(req.carPlate());
        tx.setCarMake(req.carMake());
        tx.setCarModel(req.carModel());
        tx.setCarColor(req.carColor());
        tx.setGuestName(req.guestName());
        tx.setGuestPhone(req.guestPhone());
        tx.setKeyCode(req.keyCode());
        tx.setStatus(ValetStatus.WAITING_FOR_DRIVER);

        ValetTransaction saved = repository.save(tx);
        realtime.emitCreated(saved);
        return saved;
    }

    @Transactional
    public ValetTransaction operatorPark(UUID id, UUID companyId) {
        ValetTransaction tx = loadOwnedByCompany(id, companyId);
        return transition(tx, ValetStatus.PARKED);
    }

    @Transactional
    public ValetTransaction operatorKeyIn(UUID id, UUID companyId) {
        ValetTransaction tx = loadOwnedByCompany(id, companyId);
        return transition(tx, ValetStatus.KEY_IN);
    }

    @Transactional
    public ValetTransaction operatorRequest(UUID id, UUID companyId) {
        ValetTransaction tx = loadOwnedByCompany(id, companyId);
        return transition(tx, ValetStatus.REQUESTED);
    }

    @Transactional
    public ValetTransaction operatorCancel(UUID id, UUID companyId) {
        ValetTransaction tx = loadOwnedByCompany(id, companyId);
        return transition(tx, ValetStatus.CANCELLED);
    }

    /**
     * Operator assigns a driver to a retrieval. Stamps
     * {@code retrieved_by_driver_id} and transitions requested → driver_assigned,
     * then emits {@code tx:assigned} (which pins {@code status=driver_assigned}
     * and carries the driverId) so the mission lands in that driver's room. We do
     * NOT also emit a generic {@code tx:status} for the same change.
     */
    @Transactional
    public ValetTransaction operatorAssign(UUID id, UUID companyId, UUID driverId) {
        ValetTransaction tx = loadOwnedByCompany(id, companyId);
        tx.setRetrievedByDriverId(driverId);
        // applyTransition (not transition): assignment emits ONE event — the
        // assigned event — instead of a generic status delta for the same change.
        ValetTransaction saved = applyTransition(tx, ValetStatus.DRIVER_ASSIGNED);
        realtime.emitAssigned(saved);
        return saved;
    }

    /**
     * Operator assigns a driver to PARK an incoming car (intake side). Stamps
     * {@code parked_by_driver_id} but does NOT change status — the car stays
     * {@code waiting_for_driver} until the assigned driver confirms it parked
     * (see {@link #driverConfirmParked}). Emits {@code tx:assigned} routed to the
     * park driver's room so the mission lands live. The car must still be
     * awaiting parking; assigning after it's parked is a 409.
     *
     * <p>Re-assignment while still {@code waiting_for_driver} is allowed (an
     * operator can hand the car to a different driver before it's parked).</p>
     */
    @Transactional
    public ValetTransaction operatorAssignPark(UUID id, UUID companyId, UUID driverId) {
        ValetTransaction tx = loadOwnedByCompany(id, companyId);
        if (tx.getStatus() != ValetStatus.WAITING_FOR_DRIVER) {
            throw ServiceException.conflict("ILLEGAL_TRANSITION",
                    "A park driver can only be assigned while the car is still awaiting parking.");
        }
        tx.setParkedByDriverId(driverId);
        ValetTransaction saved = repository.save(tx);
        realtime.emitParkAssigned(saved);
        return saved;
    }

    /**
     * The assigned PARK driver confirms the car is parked: {@code
     * waiting_for_driver → parked}. Only the driver stamped on
     * {@code parked_by_driver_id} may do this (403 otherwise); the transition
     * itself is the canonical legal edge enforced by {@link #transition}.
     */
    @Transactional
    public ValetTransaction driverConfirmParked(UUID id, UUID driverId) {
        ValetTransaction tx = loadOwnedByParkDriver(id, driverId);
        return transition(tx, ValetStatus.PARKED);
    }

    // --- driver mission transitions ---------------------------------------

    @Transactional
    public ValetTransaction driverEnRoute(UUID id, UUID driverId) {
        ValetTransaction tx = loadOwnedByDriver(id, driverId);
        return transition(tx, ValetStatus.EN_ROUTE);
    }

    @Transactional
    public ValetTransaction driverArrived(UUID id, UUID driverId) {
        ValetTransaction tx = loadOwnedByDriver(id, driverId);
        return transition(tx, ValetStatus.ARRIVED);
    }

    @Transactional
    public ValetTransaction driverDelivered(UUID id, UUID driverId) {
        ValetTransaction tx = loadOwnedByDriver(id, driverId);
        return transition(tx, ValetStatus.DELIVERED);
    }

    // --- the single legal-transition chokepoint ---------------------------

    /**
     * Apply a status change, enforcing the canonical legal-transition map, and
     * emit a generic {@code tx:status} realtime delta after commit. This single
     * call covers every driver + operator transition (park, key_in, requested,
     * en_route, arrived, delivered, cancelled). Illegal transitions throw a 409
     * {@link ServiceException}. Side-effecting timestamp columns are stamped here
     * (and only here) so they can never drift from the transition that caused
     * them.
     *
     * <p>Driver assignment uses {@link #applyTransition} directly + an explicit
     * {@code emitAssigned} so the same change is not double-emitted.</p>
     *
     * @throws ServiceException 409 if {@code from -> to} is not a legal edge.
     */
    public ValetTransaction transition(ValetTransaction tx, ValetStatus to) {
        ValetTransaction saved = applyTransition(tx, to);
        realtime.emitStatus(saved);
        return saved;
    }

    /**
     * The pure legal-transition apply: guard + stamp + save, with no realtime
     * emit. Internal so a caller (driver assignment) can choose a more specific
     * event instead of the generic status delta.
     */
    private ValetTransaction applyTransition(ValetTransaction tx, ValetStatus to) {
        ValetStatus from = tx.getStatus();
        if (!ValetStatus.isLegalTransition(from, to)) {
            throw ServiceException.conflict("ILLEGAL_TRANSITION",
                    "Cannot move this car from " + from.dbValue() + " to " + to.dbValue() + ".");
        }

        tx.setStatus(to);
        stampTimestamp(tx, to);
        return repository.save(tx);
    }

    /** Stamp the lifecycle timestamp matching the transition target. */
    private void stampTimestamp(ValetTransaction tx, ValetStatus to) {
        Instant now = Instant.now();
        switch (to) {
            case REQUESTED -> {
                if (tx.getRequestedAt() == null) {
                    tx.setRequestedAt(now);
                }
            }
            case ARRIVED -> tx.setArrivedAt(now);
            case DELIVERED -> tx.setDeliveredAt(now);
            default -> {
                // No timestamp column for the other states.
            }
        }
    }

    // --- ownership guard ---------------------------------------------------

    /**
     * Load a transaction and assert the given driver is the assigned retriever.
     * A mismatch is a 403 (not 404) per the contract: it is the driver's
     * action that is forbidden. We do not reveal whether the id exists.
     */
    private ValetTransaction loadOwnedByDriver(UUID id, UUID driverId) {
        ValetTransaction tx = getById(id);
        if (!driverId.equals(tx.getRetrievedByDriverId())) {
            throw ServiceException.forbidden("NOT_YOUR_ASSIGNMENT",
                    "This assignment doesn't belong to you.");
        }
        return tx;
    }

    /**
     * Load a transaction and assert the given driver is the assigned PARKER
     * ({@code parked_by_driver_id}). Mirrors {@link #loadOwnedByDriver} for the
     * intake side: a mismatch is a 403 — it is the driver's action that is
     * forbidden — and we do not reveal whether the id exists.
     */
    private ValetTransaction loadOwnedByParkDriver(UUID id, UUID driverId) {
        ValetTransaction tx = getById(id);
        if (!driverId.equals(tx.getParkedByDriverId())) {
            throw ServiceException.forbidden("NOT_YOUR_ASSIGNMENT",
                    "This assignment doesn't belong to you.");
        }
        return tx;
    }

    /**
     * Load a transaction and assert it belongs to the caller's company. Mirrors
     * {@link #loadOwnedByDriver}: a cross-tenant mismatch is a 403 (not 404) so
     * an operator can never mutate — nor probe the existence of — another
     * company's transaction.
     */
    private ValetTransaction loadOwnedByCompany(UUID id, UUID companyId) {
        ValetTransaction tx = getById(id);
        if (!companyId.equals(tx.getCompanyId())) {
            throw ServiceException.forbidden("NOT_YOUR_TRANSACTION",
                    "This transaction belongs to another company.");
        }
        return tx;
    }
}
