package com.valet.transaction.realtime;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.valet.transaction.domain.ValetTransaction;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Instant;
import java.util.UUID;

/**
 * Publishes realtime lifecycle deltas to a single Redis pub/sub channel so the
 * realtime gateway can fan them out to operator/driver clients.
 *
 * <p><strong>Contract (PINNED — do not rename fields).</strong> All messages are
 * camelCase JSON on the channel {@link #CHANNEL} ({@code valet.tx.events}). Three
 * event shapes:</p>
 * <pre>
 *   tx:created  -> {"event":"tx:created","id","status","locationId","companyId","driverId","ts"}
 *   tx:status   -> {"event":"tx:status","id","status","locationId","companyId","driverId","ts"}
 *   tx:assigned -> {"event":"tx:assigned","id","status":"driver_assigned","locationId","companyId","driverId","ts"}
 * </pre>
 * {@code driverId} = {@code retrievedByDriverId} (may be JSON null). {@code ts} is
 * an ISO-8601 instant.
 *
 * <p><strong>Commit safety.</strong> Publishing is deferred to {@code afterCommit}
 * via {@link TransactionSynchronizationManager}, so a rolled-back transition never
 * emits. If no transaction is active we publish immediately.</p>
 *
 * <p><strong>Resilience.</strong> Redis is optional: a publish failure (Redis down,
 * timeout, etc.) is caught and logged at WARN — it never propagates, so it cannot
 * fail the DB transaction or the HTTP request.</p>
 */
@Component
public class RealtimeEventPublisher {

    /** The single Redis pub/sub channel all deltas are published to. */
    public static final String CHANNEL = "valet.tx.events";

    static final String EVENT_CREATED = "tx:created";
    static final String EVENT_STATUS = "tx:status";
    static final String EVENT_ASSIGNED = "tx:assigned";

    private static final Logger log = LoggerFactory.getLogger(RealtimeEventPublisher.class);

    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;

    public RealtimeEventPublisher(StringRedisTemplate redis, ObjectMapper objectMapper) {
        this.redis = redis;
        this.objectMapper = objectMapper;
    }

    // --- public emit hooks (called from inside @Transactional service methods) ---

    /** Emit {@code tx:created} after the surrounding transaction commits. */
    public void emitCreated(ValetTransaction tx) {
        publishAfterCommit(buildMessage(EVENT_CREATED, tx, tx.getStatus().dbValue()));
    }

    /** Emit {@code tx:status} (current status) after the surrounding transaction commits. */
    public void emitStatus(ValetTransaction tx) {
        publishAfterCommit(buildMessage(EVENT_STATUS, tx, tx.getStatus().dbValue()));
    }

    /** Emit {@code tx:assigned} (status pinned to {@code driver_assigned}) after commit. */
    public void emitAssigned(ValetTransaction tx) {
        publishAfterCommit(buildMessage(EVENT_ASSIGNED, tx, "driver_assigned"));
    }

    /**
     * Emit {@code tx:assigned} for an INTAKE (park) assignment after commit. The
     * car stays {@code waiting_for_driver} (the park driver hasn't parked yet),
     * but the event carries {@code driverId = parkedByDriverId} so the gateway
     * routes it to that driver's room — landing the new park mission live.
     */
    public void emitParkAssigned(ValetTransaction tx) {
        publishAfterCommit(buildMessage(
                EVENT_ASSIGNED, tx, tx.getStatus().dbValue(), tx.getParkedByDriverId()));
    }

    // --- message building (pure; unit-testable without a live Redis) ------------

    /**
     * Build the pinned camelCase JSON envelope. Package-visible so unit tests can
     * assert the exact field names without standing up Redis.
     *
     * @param status the {@code status} value to stamp (callers may pin it, e.g.
     *               {@code tx:assigned} always carries {@code driver_assigned}).
     */
    String buildMessage(String event, ValetTransaction tx, String status) {
        // Default driver room = the retrieval driver (the original contract).
        return buildMessage(event, tx, status, tx.getRetrievedByDriverId());
    }

    /**
     * Build the envelope with an EXPLICIT driver room id. Used by the park
     * assignment, whose relevant driver is {@code parkedByDriverId}, not the
     * retrieval driver. All other fields are identical to the pinned contract.
     */
    String buildMessage(String event, ValetTransaction tx, String status, UUID driverId) {
        ObjectNode node = objectMapper.createObjectNode();
        node.put("event", event);
        putUuid(node, "id", tx.getId());
        node.put("status", status);
        putUuid(node, "locationId", tx.getLocationId());
        putUuid(node, "companyId", tx.getCompanyId());
        putUuid(node, "driverId", driverId);
        // Correlation id of the originating request (MDC key set by
        // RequestIdFilter). buildMessage runs synchronously on the request
        // thread — before the afterCommit publish — so the MDC is still the
        // originating request's. Null when emitted outside a request scope.
        String requestId = MDC.get("requestId");
        if (requestId == null) {
            node.putNull("requestId");
        } else {
            node.put("requestId", requestId);
        }
        node.put("ts", Instant.now().toString());
        try {
            return objectMapper.writeValueAsString(node);
        } catch (JsonProcessingException e) {
            // ObjectNode is always serialisable; treat as a programming error but
            // never let it bubble into the request/transaction.
            throw new IllegalStateException("Failed to serialise realtime event", e);
        }
    }

    private static void putUuid(ObjectNode node, String field, UUID value) {
        if (value == null) {
            node.putNull(field);
        } else {
            node.put(field, value.toString());
        }
    }

    // --- commit-safe publishing -------------------------------------------------

    /**
     * Defer the publish to {@code afterCommit} when a transaction is active so a
     * rollback suppresses the event. If none is active, publish immediately.
     */
    private void publishAfterCommit(String message) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    publish(message);
                }
            });
        } else {
            publish(message);
        }
    }

    /** Best-effort publish — any failure is swallowed + logged, never rethrown. */
    private void publish(String message) {
        try {
            redis.convertAndSend(CHANNEL, message);
        } catch (RuntimeException ex) {
            // Redis is optional: an outage must not affect the committed work or
            // the HTTP response. Log and move on.
            log.warn("Realtime publish to '{}' failed (event dropped): {}",
                    CHANNEL, ex.getMessage());
        }
    }
}
