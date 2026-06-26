package com.valet.transaction;

import com.valet.transaction.domain.ValetStatus;
import com.valet.transaction.domain.ValetTransaction;
import com.valet.transaction.dto.CreateTransactionRequest;
import com.valet.transaction.exception.ServiceException;
import com.valet.transaction.realtime.RealtimeEventPublisher;
import com.valet.transaction.repository.ValetTransactionRepository;
import com.valet.transaction.service.TransactionService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for the service guard: legal-transition enforcement, driver
 * ownership (403), and timestamp stamping. Repository is mocked so these stay
 * fast and DB-free.
 */
class TransactionServiceTest {

    private static final UUID DRIVER = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID OTHER_DRIVER = UUID.fromString("99999999-9999-9999-9999-999999999999");

    private static final UUID COMPANY = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID OTHER_COMPANY = UUID.fromString("88888888-8888-8888-8888-888888888888");

    private ValetTransactionRepository repository;
    private RealtimeEventPublisher realtime;
    private TransactionService service;

    @BeforeEach
    void setUp() {
        repository = mock(ValetTransactionRepository.class);
        realtime = mock(RealtimeEventPublisher.class);
        service = new TransactionService(repository, realtime);
        // save() echoes its argument back, like JPA does.
        when(repository.save(any(ValetTransaction.class)))
                .thenAnswer(inv -> inv.getArgument(0));
    }

    private ValetTransaction tx(UUID id, ValetStatus status, UUID retriever) {
        return tx(id, status, retriever, UUID.randomUUID());
    }

    private ValetTransaction tx(UUID id, ValetStatus status, UUID retriever, UUID companyId) {
        ValetTransaction t = new ValetTransaction();
        t.setId(id);
        t.setCompanyId(companyId);
        t.setStatus(status);
        t.setRetrievedByDriverId(retriever);
        return t;
    }

    @Test
    void enRouteHappyPathMovesDriverAssignedToEnRoute() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.DRIVER_ASSIGNED, DRIVER)));

        ValetTransaction result = service.driverEnRoute(id, DRIVER);

        assertThat(result.getStatus()).isEqualTo(ValetStatus.EN_ROUTE);
        verify(repository).save(any(ValetTransaction.class));
    }

    @Test
    void arrivedStampsArrivedAt() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.EN_ROUTE, DRIVER)));

        ValetTransaction result = service.driverArrived(id, DRIVER);

        assertThat(result.getStatus()).isEqualTo(ValetStatus.ARRIVED);
        assertThat(result.getArrivedAt()).isNotNull();
    }

    @Test
    void deliveredStampsDeliveredAt() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.ARRIVED, DRIVER)));

        ValetTransaction result = service.driverDelivered(id, DRIVER);

        assertThat(result.getStatus()).isEqualTo(ValetStatus.DELIVERED);
        assertThat(result.getDeliveredAt()).isNotNull();
    }

    @Test
    void illegalTransitionThrows409AndDoesNotSave() {
        UUID id = UUID.randomUUID();
        // arrived -> en_route is backwards / illegal
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.ARRIVED, DRIVER)));

        assertThatThrownBy(() -> service.driverEnRoute(id, DRIVER))
                .isInstanceOf(ServiceException.class)
                .satisfies(e -> {
                    ServiceException se = (ServiceException) e;
                    assertThat(se.getCode()).isEqualTo("ILLEGAL_TRANSITION");
                    assertThat(se.getStatus().value()).isEqualTo(409);
                });

        verify(repository, never()).save(any());
    }

    @Test
    void foreignDriverGets403NotYourAssignment() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.DRIVER_ASSIGNED, OTHER_DRIVER)));

        assertThatThrownBy(() -> service.driverEnRoute(id, DRIVER))
                .isInstanceOf(ServiceException.class)
                .satisfies(e -> {
                    ServiceException se = (ServiceException) e;
                    assertThat(se.getCode()).isEqualTo("NOT_YOUR_ASSIGNMENT");
                    assertThat(se.getStatus().value()).isEqualTo(403);
                });

        verify(repository, never()).save(any());
    }

    @Test
    void unknownTransactionGets404() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.driverArrived(id, DRIVER))
                .isInstanceOf(ServiceException.class)
                .satisfies(e -> assertThat(((ServiceException) e).getStatus().value()).isEqualTo(404));
    }

    // --- realtime wiring ---------------------------------------------------

    @Test
    void transitionEmitsStatusOnce() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.DRIVER_ASSIGNED, DRIVER)));

        service.driverEnRoute(id, DRIVER);

        verify(realtime).emitStatus(any(ValetTransaction.class));
        verify(realtime, never()).emitAssigned(any());
        verify(realtime, never()).emitCreated(any());
    }

    // --- operator: create --------------------------------------------------

    @Test
    void createForOperatorForcesWaitingAndStampsTenantFromPrincipalNotBody() {
        // The request body carries NO tenant fields (whitelisted DTO); tenant
        // comes from the principal args. Status must be server-forced.
        CreateTransactionRequest req = new CreateTransactionRequest(
                "MH01AB1234", "Toyota", "Camry", "Silver",
                "Aarav", "+919800000001", "K-07");
        UUID locationId = UUID.randomUUID();

        ValetTransaction created = service.createForOperator(req, COMPANY, locationId);

        assertThat(created.getStatus()).isEqualTo(ValetStatus.WAITING_FOR_DRIVER);
        assertThat(created.getCompanyId()).isEqualTo(COMPANY);
        assertThat(created.getLocationId()).isEqualTo(locationId);
        assertThat(created.getCarPlate()).isEqualTo("MH01AB1234");
        verify(realtime).emitCreated(any(ValetTransaction.class));
    }

    // --- operator: full happy path -----------------------------------------

    @Test
    void operatorHappyPathParkKeyInRequestAssign() {
        UUID id = UUID.randomUUID();
        UUID assignee = UUID.randomUUID();
        ValetTransaction state = tx(id, ValetStatus.WAITING_FOR_DRIVER, null, COMPANY);
        when(repository.findById(id)).thenReturn(Optional.of(state));

        assertThat(service.operatorPark(id, COMPANY).getStatus()).isEqualTo(ValetStatus.PARKED);
        assertThat(service.operatorKeyIn(id, COMPANY).getStatus()).isEqualTo(ValetStatus.KEY_IN);
        assertThat(service.operatorRequest(id, COMPANY).getStatus()).isEqualTo(ValetStatus.REQUESTED);

        ValetTransaction assigned = service.operatorAssign(id, COMPANY, assignee);
        assertThat(assigned.getStatus()).isEqualTo(ValetStatus.DRIVER_ASSIGNED);
        assertThat(assigned.getRetrievedByDriverId()).isEqualTo(assignee);

        // assign emits exactly the assigned event for its change (no generic status)
        verify(realtime).emitAssigned(any(ValetTransaction.class));
        // park + key-in + request => three generic status emits
        verify(realtime, org.mockito.Mockito.times(3)).emitStatus(any(ValetTransaction.class));
    }

    // --- operator: cross-tenant guard --------------------------------------

    @Test
    void operatorFromAnotherCompanyCannotParkGets403() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.WAITING_FOR_DRIVER, null, COMPANY)));

        assertThatThrownBy(() -> service.operatorPark(id, OTHER_COMPANY))
                .isInstanceOf(ServiceException.class)
                .satisfies(e -> {
                    ServiceException se = (ServiceException) e;
                    assertThat(se.getCode()).isEqualTo("NOT_YOUR_TRANSACTION");
                    assertThat(se.getStatus().value()).isEqualTo(403);
                });

        verify(repository, never()).save(any());
    }

    @Test
    void operatorFromAnotherCompanyCannotAssignGets403() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.REQUESTED, null, COMPANY)));

        assertThatThrownBy(() -> service.operatorAssign(id, OTHER_COMPANY, UUID.randomUUID()))
                .isInstanceOf(ServiceException.class)
                .satisfies(e -> assertThat(((ServiceException) e).getStatus().value()).isEqualTo(403));

        verify(repository, never()).save(any());
        verify(realtime, never()).emitAssigned(any());
    }

    // --- operator: illegal transition --------------------------------------

    @Test
    void operatorParkOnAlreadyParkedGets409() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.PARKED, null, COMPANY)));

        assertThatThrownBy(() -> service.operatorPark(id, COMPANY))
                .isInstanceOf(ServiceException.class)
                .satisfies(e -> {
                    ServiceException se = (ServiceException) e;
                    assertThat(se.getCode()).isEqualTo("ILLEGAL_TRANSITION");
                    assertThat(se.getStatus().value()).isEqualTo(409);
                });

        verify(repository, never()).save(any());
    }

    // --- operator: assign stamps retriever ---------------------------------

    @Test
    void operatorAssignStampsRetrieverAndEmitsAssigned() {
        UUID id = UUID.randomUUID();
        UUID assignee = UUID.fromString("11111111-1111-1111-1111-111111111111");
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.REQUESTED, null, COMPANY)));

        ValetTransaction result = service.operatorAssign(id, COMPANY, assignee);

        assertThat(result.getRetrievedByDriverId()).isEqualTo(assignee);
        assertThat(result.getStatus()).isEqualTo(ValetStatus.DRIVER_ASSIGNED);
        verify(realtime).emitAssigned(any(ValetTransaction.class));
        verify(realtime, never()).emitStatus(any());
    }

    // --- intake: park assignment + driver confirm-parked -------------------

    @Test
    void operatorAssignParkStampsParkerKeepsWaitingAndEmitsParkAssigned() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.WAITING_FOR_DRIVER, null, COMPANY)));

        ValetTransaction result = service.operatorAssignPark(id, COMPANY, DRIVER);

        assertThat(result.getParkedByDriverId()).isEqualTo(DRIVER);
        // Status must NOT advance — the driver hasn't parked yet.
        assertThat(result.getStatus()).isEqualTo(ValetStatus.WAITING_FOR_DRIVER);
        verify(realtime).emitParkAssigned(any(ValetTransaction.class));
        verify(realtime, never()).emitStatus(any());
    }

    @Test
    void operatorAssignParkAfterParkedThrows409() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.PARKED, null, COMPANY)));

        assertThatThrownBy(() -> service.operatorAssignPark(id, COMPANY, DRIVER))
                .isInstanceOf(ServiceException.class)
                .satisfies(e -> {
                    ServiceException se = (ServiceException) e;
                    assertThat(se.getCode()).isEqualTo("ILLEGAL_TRANSITION");
                    assertThat(se.getStatus().value()).isEqualTo(409);
                });
        verify(repository, never()).save(any());
    }

    @Test
    void operatorAssignParkCrossTenantThrows403() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id))
                .thenReturn(Optional.of(tx(id, ValetStatus.WAITING_FOR_DRIVER, null, OTHER_COMPANY)));

        assertThatThrownBy(() -> service.operatorAssignPark(id, COMPANY, DRIVER))
                .isInstanceOf(ServiceException.class)
                .satisfies(e -> assertThat(((ServiceException) e).getStatus().value()).isEqualTo(403));
        verify(repository, never()).save(any());
    }

    @Test
    void driverConfirmParkedByAssignedParkerMovesWaitingToParked() {
        UUID id = UUID.randomUUID();
        ValetTransaction t = tx(id, ValetStatus.WAITING_FOR_DRIVER, null, COMPANY);
        t.setParkedByDriverId(DRIVER);
        when(repository.findById(id)).thenReturn(Optional.of(t));

        ValetTransaction result = service.driverConfirmParked(id, DRIVER);

        assertThat(result.getStatus()).isEqualTo(ValetStatus.PARKED);
        verify(realtime).emitStatus(any(ValetTransaction.class));
    }

    @Test
    void driverConfirmParkedByNonAssignedDriverThrows403() {
        UUID id = UUID.randomUUID();
        ValetTransaction t = tx(id, ValetStatus.WAITING_FOR_DRIVER, null, COMPANY);
        t.setParkedByDriverId(DRIVER);
        when(repository.findById(id)).thenReturn(Optional.of(t));

        assertThatThrownBy(() -> service.driverConfirmParked(id, OTHER_DRIVER))
                .isInstanceOf(ServiceException.class)
                .satisfies(e -> {
                    ServiceException se = (ServiceException) e;
                    assertThat(se.getCode()).isEqualTo("NOT_YOUR_ASSIGNMENT");
                    assertThat(se.getStatus().value()).isEqualTo(403);
                });
        verify(repository, never()).save(any());
    }

    @Test
    void getDriverAssignmentsMergesParkAndRetrievalMissions() {
        ValetTransaction park = tx(UUID.randomUUID(), ValetStatus.WAITING_FOR_DRIVER, null, COMPANY);
        park.setParkedByDriverId(DRIVER);
        ValetTransaction retrieval = tx(UUID.randomUUID(), ValetStatus.DRIVER_ASSIGNED, DRIVER, COMPANY);
        when(repository.findByParkedByDriverIdAndStatusInOrderByCreatedAtDesc(
                eq(DRIVER), any())).thenReturn(java.util.List.of(park));
        when(repository.findByRetrievedByDriverIdAndStatusInOrderByCreatedAtDesc(
                eq(DRIVER), any())).thenReturn(java.util.List.of(retrieval));

        var result = service.getDriverAssignments(DRIVER);

        assertThat(result).hasSize(2)
                .extracting(ValetTransaction::getStatus)
                .containsExactlyInAnyOrder(ValetStatus.WAITING_FOR_DRIVER, ValetStatus.DRIVER_ASSIGNED);
    }
}
