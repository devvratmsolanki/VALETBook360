package com.valet.auth.security.ratelimit;

import com.valet.auth.config.LoginGuardProperties;
import com.valet.auth.exception.ServiceException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.Locale;

/**
 * Login abuse controls, Redis-backed (cluster-safe) via {@link LoginGuardStore}:
 *
 * <ul>
 *   <li><b>Per-IP failure rate limit</b> — fixed window: max {@code ipMaxAttempts}
 *       FAILED login attempts per client IP per {@code ipWindowSeconds}.
 *       <em>Only failures</em> are counted — successful logins from the same IP do
 *       NOT consume the bucket. This is intentional: behind NAT / corporate proxy /
 *       CGNAT a single egress IP is shared by many users, so counting all requests
 *       (or even just successful ones) would lock out innocent users as soon as one
 *       account in the same office misbehaves. The high threshold (default 100/60s)
 *       makes this a coarse abuse circuit-breaker for genuine bot floods, not a
 *       per-request speed-bump. The per-account lockout is the precise primary
 *       control. Enforced in {@code recordFailure} (called by AuthService on every
 *       bad password). Exceed → 429 {@code RATE_LIMITED}. The check is also wired
 *       into {@code RateLimitFilter} for {@code /auth/refresh} (which never
 *       reaches AuthService.login) but the filter path does NOT increment the
 *       counter (only the service call on a confirmed failure does).</li>
 *   <li><b>Per-account lockout</b> — after {@code accountMaxFailures} consecutive
 *       failed logins for one email within {@code accountWindowSeconds}, the email
 *       is locked for {@code accountLockSeconds}. While locked, even a CORRECT
 *       password is rejected with 429 {@code ACCOUNT_LOCKED}. A successful login
 *       clears the failure counter. Enforced inside AuthService.login (it alone
 *       knows the email + outcome).</li>
 * </ul>
 *
 * <p>The store is injected, so a unit test can supply an in-memory fake and
 * exercise this logic without a live Redis.
 */
@Service
public class LoginGuardService {

    private static final Logger log = LoggerFactory.getLogger(LoginGuardService.class);

    // Key namespaces. Email/IP are normalised; emails are lower-cased upstream.
    /**
     * Per-IP FAILURE counter. Keyed by client IP. Only incremented when a login
     * attempt fails (wrong password, unknown account, locked account, etc.) — not
     * on successful logins. Using a separate key from total-request counts means
     * a well-behaved shared-egress IP with many successful logins for different
     * users never trips this ceiling.
     */
    private static final String IP_FAIL_PREFIX = "rl:ip:fail:";   // per-IP failure counter
    private static final String FAIL_PREFIX    = "lock:fail:";     // per-email failure counter
    private static final String LOCK_PREFIX    = "lock:acct:";     // per-email lock flag

    private final LoginGuardStore store;
    private final LoginGuardProperties props;

    public LoginGuardService(LoginGuardStore store, LoginGuardProperties props) {
        this.store = store;
        this.props = props;
    }

    /**
     * Check (but do NOT increment) the per-IP failure counter. Used by
     * {@code RateLimitFilter} on {@code /auth/refresh} requests so they are
     * covered by the coarse abuse ceiling even though they never reach
     * {@code AuthService.login}. The counter is incremented on actual login
     * failures via {@link #recordFailure(String, String)} — not here — so
     * refresh requests (success or failure from the token check) do not inflate
     * the counter via the filter.
     *
     * <p>If the current failure count already exceeds the threshold, throws 429
     * {@code RATE_LIMITED}. This is a read-only check; the window TTL is not
     * extended.
     */
    public void checkIpFailureLimit(String clientIp) {
        if (clientIp == null || clientIp.isBlank()) {
            return; // Can't attribute; don't block.
        }
        String key = IP_FAIL_PREFIX + clientIp;
        long count = store.get(key);
        if (count >= props.getIpMaxAttempts()) {
            long retryAfter = store.ttlSeconds(key);
            if (retryAfter <= 0) {
                retryAfter = props.getIpWindowSeconds();
            }
            log.warn("Per-IP failure ceiling already exceeded for IP {} ({} >= {} in {}s window)",
                    clientIp, count, props.getIpMaxAttempts(), props.getIpWindowSeconds());
            throw ServiceException.tooManyRequests("RATE_LIMITED",
                    "Too many failed attempts from this network. Please wait a bit and try again.",
                    retryAfter);
        }
    }

    /**
     * Reject (429 {@code ACCOUNT_LOCKED}) if the email is currently locked.
     * Call this at the TOP of login, before any password check, so a locked
     * account is blocked even with the right password.
     */
    public void assertNotLocked(String email) {
        String norm = normalize(email);
        if (norm == null) {
            return;
        }
        String lockKey = LOCK_PREFIX + norm;
        if (store.exists(lockKey)) {
            long retryAfter = store.ttlSeconds(lockKey);
            if (retryAfter <= 0) {
                retryAfter = props.getAccountLockSeconds();
            }
            throw ServiceException.tooManyRequests("ACCOUNT_LOCKED",
                    "This account is temporarily locked after too many failed sign-in "
                            + "attempts. Please try again later.", retryAfter);
        }
    }

    /**
     * Record a failed login for {@code email} from {@code clientIp}. Both the
     * per-account lockout counter and the per-IP failure counter are incremented.
     *
     * <p>Per-account: when the consecutive-failure counter reaches the threshold,
     * the account is locked (lock flag set, failure counter cleared). Best-effort:
     * store failures fail open.
     *
     * <p>Per-IP: when the failure counter reaches the coarse ceiling, the NEXT
     * check from that IP (via {@link #checkIpFailureLimit}) will be rejected. A
     * successful login for any account from that IP does NOT reset this counter —
     * it decays naturally when the window TTL expires.
     */
    public void recordFailure(String email, String clientIp) {
        // --- per-account lockout ---
        String norm = normalize(email);
        if (norm != null) {
            String failKey = FAIL_PREFIX + norm;
            long failures = store.incrementAndGet(failKey, props.getAccountWindowSeconds());
            if (failures >= props.getAccountMaxFailures()) {
                store.setWithTtl(LOCK_PREFIX + norm, "1", props.getAccountLockSeconds());
                store.delete(failKey);
                log.warn("Account locked after {} failed logins: {} (locked {}s)",
                        failures, norm, props.getAccountLockSeconds());
            }
        }

        // --- coarse per-IP failure ceiling ---
        if (clientIp != null && !clientIp.isBlank()) {
            String ipKey = IP_FAIL_PREFIX + clientIp;
            long ipFailures = store.incrementAndGet(ipKey, props.getIpWindowSeconds());
            if (ipFailures >= props.getIpMaxAttempts()) {
                log.warn("Per-IP failure ceiling reached for IP {} ({} failures in {}s window)",
                        clientIp, ipFailures, props.getIpWindowSeconds());
                // Don't throw here — the account-lockout or INVALID_CREDENTIALS
                // response was already on its way. The ceiling will be enforced
                // on the NEXT request via checkIpFailureLimit.
            }
        }
    }

    /**
     * Convenience overload for callers that don't have the client IP
     * (e.g. internal service code or existing callers without the IP context).
     * Only the per-account lockout counter is updated; the per-IP bucket is
     * left unchanged.
     *
     * @deprecated Prefer {@link #recordFailure(String, String)} to also update
     *             the per-IP failure counter.
     */
    @Deprecated
    public void recordFailure(String email) {
        recordFailure(email, null);
    }

    /** Clear the per-account failure counter and any lock after a successful login.
     *  The per-IP failure counter is intentionally NOT reset — it decays naturally
     *  when its window expires. A successful login does not whittle down the abuse
     *  record from the same IP. */
    public void recordSuccess(String email) {
        String norm = normalize(email);
        if (norm == null) {
            return;
        }
        store.delete(FAIL_PREFIX + norm);
        store.delete(LOCK_PREFIX + norm);
    }

    private static String normalize(String email) {
        if (email == null) {
            return null;
        }
        String trimmed = email.trim().toLowerCase(Locale.ROOT);
        return trimmed.isEmpty() ? null : trimmed;
    }
}
