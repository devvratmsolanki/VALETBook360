package com.valet.auth;

import com.valet.auth.config.LoginGuardProperties;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.security.ratelimit.LoginGuardService;
import com.valet.auth.security.ratelimit.LoginGuardStore;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Pure unit tests for the login abuse logic, using an in-memory fake
 * {@link LoginGuardStore} so no live Redis is needed.
 *
 * <p>Verifies:
 * <ul>
 *   <li>Per-IP failure-only rate limit (only failures count, not successes).</li>
 *   <li>Account lockout after N consecutive failures (even the correct password
 *       is then blocked).</li>
 *   <li>A success resets the per-account failure counter.</li>
 *   <li>A good login for account B is NOT blocked by account A's failures from
 *       the same IP (as long as the high per-IP failure ceiling is not hit).</li>
 * </ul>
 */
class LoginGuardServiceTest {

    /** Minimal in-memory store. Ignores TTL semantics; sufficient for the logic. */
    static final class FakeStore implements LoginGuardStore {
        final Map<String, Long> counters = new HashMap<>();
        final Map<String, Integer> ttls = new HashMap<>();

        @Override
        public long incrementAndGet(String key, int windowSeconds) {
            long v = counters.merge(key, 1L, Long::sum);
            ttls.putIfAbsent(key, windowSeconds);
            return v;
        }

        @Override
        public long get(String key) {
            return counters.getOrDefault(key, 0L);
        }

        @Override
        public void delete(String key) {
            counters.remove(key);
            ttls.remove(key);
        }

        @Override
        public void setWithTtl(String key, String value, int ttlSeconds) {
            counters.put(key, 1L);
            ttls.put(key, ttlSeconds);
        }

        @Override
        public boolean exists(String key) {
            return counters.containsKey(key);
        }

        @Override
        public long ttlSeconds(String key) {
            return ttls.getOrDefault(key, 0);
        }
    }

    private FakeStore store;
    private LoginGuardService guard;
    private LoginGuardProperties props;

    @BeforeEach
    void setup() {
        store = new FakeStore();
        props = new LoginGuardProperties();
        props.setIpMaxAttempts(10);   // low threshold for test speed
        props.setIpWindowSeconds(60);
        props.setAccountMaxFailures(5);
        props.setAccountWindowSeconds(900);
        props.setAccountLockSeconds(900);
        guard = new LoginGuardService(store, props);
    }

    // ----------------------------------------------------------- per-IP ceiling

    @Test
    void perIpFailureCeilingTripsAfterMaxFailures() {
        String ip = "203.0.113.5";
        // Record 10 failures (the threshold).
        for (int i = 0; i < 10; i++) {
            guard.recordFailure("accountA@test.test", ip);
        }
        // The next checkIpFailureLimit must throw RATE_LIMITED.
        assertThatThrownBy(() -> guard.checkIpFailureLimit(ip))
                .isInstanceOf(ServiceException.class)
                .satisfies(ex -> {
                    ServiceException se = (ServiceException) ex;
                    assertThat(se.getStatus()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
                    assertThat(se.getCode()).isEqualTo("RATE_LIMITED");
                    assertThat(se.getRetryAfterSeconds()).isGreaterThan(0);
                });
    }

    @Test
    void successfulLoginDoesNotIncrementPerIpFailureCounter() {
        String ip = "203.0.113.7";
        // recordSuccess does NOT touch the IP failure counter — successful logins
        // for any account must not inflate the per-IP bucket.
        guard.recordSuccess("accountA@test.test");
        guard.recordSuccess("accountB@test.test");

        // 9 failures from the same IP — one below threshold.
        for (int i = 0; i < 9; i++) {
            guard.recordFailure("victim" + i + "@test.test", ip);
        }
        // checkIpFailureLimit must still pass (9 < 10).
        assertThatCode(() -> guard.checkIpFailureLimit(ip)).doesNotThrowAnyException();
    }

    @Test
    void differentIpsHaveIndependentBuckets() {
        // Exhaust IP 1's failure budget entirely.
        for (int i = 0; i < 11; i++) {
            guard.recordFailure("nobody" + i + "@test.test", "198.51.100.1");
        }
        // A different IP is unaffected — its check must pass.
        assertThatCode(() -> guard.checkIpFailureLimit("198.51.100.2"))
                .doesNotThrowAnyException();
    }

    /**
     * THE KEY REGRESSION TEST: account A (from IP X) locks via per-account
     * lockout after 5 bad passwords. A DIFFERENT account B from the SAME IP,
     * with the CORRECT password, must not be blocked by the per-IP bucket
     * (since only 5 failures were recorded, well below the ceiling of 10).
     */
    @Test
    void goodLoginForAccountBNotBlockedByAccountAFailuresFromSameIp() {
        String sharedIp = "10.0.0.1";

        // Account A: 5 bad passwords → per-account lockout.
        for (int i = 0; i < 5; i++) {
            guard.recordFailure("accountA@test.test", sharedIp);
        }
        // accountA is locked.
        assertThatThrownBy(() -> guard.assertNotLocked("accountA@test.test"))
                .isInstanceOf(ServiceException.class)
                .satisfies(ex -> assertThat(((ServiceException) ex).getCode())
                        .isEqualTo("ACCOUNT_LOCKED"));

        // The per-IP failure counter has 5 hits — below the ceiling of 10.
        // checkIpFailureLimit must pass, so a good login for accountB would proceed.
        assertThatCode(() -> guard.checkIpFailureLimit(sharedIp))
                .doesNotThrowAnyException();

        // accountB itself is not locked.
        assertThatCode(() -> guard.assertNotLocked("accountB@test.test"))
                .doesNotThrowAnyException();
    }

    // --------------------------------------------------- per-account lockout

    @Test
    void accountLocksAfterMaxFailuresThenBlocksEvenCorrectPassword() {
        String email = "victim@valet.test";
        // Not locked initially.
        guard.assertNotLocked(email);

        // Record N failures.
        for (int i = 0; i < props.getAccountMaxFailures(); i++) {
            guard.recordFailure(email, null);
        }

        // Now locked — assertNotLocked must throw ACCOUNT_LOCKED, regardless of
        // whether the next attempt would carry the correct password.
        assertThatThrownBy(() -> guard.assertNotLocked(email))
                .isInstanceOf(ServiceException.class)
                .satisfies(ex -> {
                    ServiceException se = (ServiceException) ex;
                    assertThat(se.getStatus()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
                    assertThat(se.getCode()).isEqualTo("ACCOUNT_LOCKED");
                    assertThat(se.getRetryAfterSeconds()).isGreaterThan(0);
                });
    }

    @Test
    void successResetsFailureCounterSoLockNeverTrips() {
        String email = "user@valet.test";
        // 4 failures (one short of the threshold of 5).
        for (int i = 0; i < props.getAccountMaxFailures() - 1; i++) {
            guard.recordFailure(email, null);
        }
        // A success wipes the per-account counter.
        guard.recordSuccess(email);

        // 4 more failures still don't lock, because the counter restarted at 0.
        for (int i = 0; i < props.getAccountMaxFailures() - 1; i++) {
            guard.recordFailure(email, null);
        }
        guard.assertNotLocked(email); // does not throw
    }

    @Test
    void recordSuccessClearsAnExistingLock() {
        String email = "recover@valet.test";
        for (int i = 0; i < props.getAccountMaxFailures(); i++) {
            guard.recordFailure(email, null);
        }
        // Locked now.
        assertThatThrownBy(() -> guard.assertNotLocked(email))
                .isInstanceOf(ServiceException.class);

        // Admin/lock-expiry simulation: a success clears the lock flag.
        guard.recordSuccess(email);
        guard.assertNotLocked(email); // no longer throws
    }
}
