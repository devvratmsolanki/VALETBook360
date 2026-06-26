package com.valet.auth.security.ratelimit;

/**
 * Tiny abstraction over the counter store backing the login rate-limit and
 * account-lockout logic. Implemented for real over Redis ({@code INCR + EXPIRE})
 * and as an in-memory fake for unit tests, so the guard logic can be tested
 * without a live Redis.
 *
 * <p>All windows are fixed-window counters: the first {@code increment} for a
 * key sets the TTL; subsequent increments within the window do not extend it.
 * Implementations should FAIL OPEN on backing-store errors (return values that
 * do not block the request) so an infra blip never causes a total login outage.
 */
public interface LoginGuardStore {

    /**
     * Atomically increment the counter at {@code key}, setting its TTL to
     * {@code windowSeconds} on first creation. Returns the new count, or 0 if the
     * store failed (fail-open: a 0 count never trips a threshold).
     */
    long incrementAndGet(String key, int windowSeconds);

    /** Current counter value at {@code key}, or 0 if absent/unreadable. */
    long get(String key);

    /** Delete the key (e.g. reset the failure counter after a success). */
    void delete(String key);

    /**
     * Mark {@code key} as set with the given TTL (used to record a lockout flag).
     * No-op-safe on store failure.
     */
    void setWithTtl(String key, String value, int ttlSeconds);

    /** True if {@code key} currently exists (e.g. an active lockout flag). */
    boolean exists(String key);

    /** Remaining TTL of {@code key} in seconds, or 0 if absent / no TTL. */
    long ttlSeconds(String key);
}
