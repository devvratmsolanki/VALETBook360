package com.valet.auth.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Tunables for the login abuse controls (per-IP failure rate limit + per-account
 * lockout). Bound from {@code auth.login-guard.*}; every value is env-overridable
 * with a sane default (see application.yml).
 */
@ConfigurationProperties(prefix = "auth.login-guard")
public class LoginGuardProperties {

    /**
     * Coarse per-IP FAILURE ceiling: max FAILED login attempts from one client IP
     * per {@link #ipWindowSeconds}. Only failed attempts consume this bucket —
     * successful logins from the same IP do NOT count. This means a shared-egress
     * IP (NAT, corporate proxy, CGNAT) is never penalised by legitimate successful
     * logins from other users sharing that IP.
     *
     * <p>The per-account lockout (keyed on the email address) is the precise primary
     * control. This per-IP ceiling is a coarse abuse circuit-breaker: it will trip
     * only when a genuine credential-stuffing flood is coming from one IP, not from
     * ordinary mixed traffic on a shared exit node.
     *
     * <p>Default: 100 failures / 60 s.  High enough that even a busy corporate proxy
     * with dozens of concurrent users never trips it via normal wrong-password
     * mistakes; low enough to cap a bot flood within a single window.
     */
    private int ipMaxAttempts = 100;

    /** Window length (seconds) for the per-IP failure rate limit. */
    private int ipWindowSeconds = 60;

    /** Consecutive failed logins for one email before the account locks. */
    private int accountMaxFailures = 5;

    /** Window (seconds) over which failures are counted toward a lockout. */
    private int accountWindowSeconds = 900;

    /** How long (seconds) an account stays locked once the threshold is hit. */
    private int accountLockSeconds = 900;

    /**
     * Trust the first hop of {@code X-Forwarded-For} when extracting the client
     * IP. True when a reverse proxy sits in front (prod). Set false if the
     * service is directly internet-exposed, otherwise clients could spoof XFF to
     * dodge the per-IP limit.
     */
    private boolean trustForwardedFor = true;

    public int getIpMaxAttempts() {
        return ipMaxAttempts;
    }

    public void setIpMaxAttempts(int ipMaxAttempts) {
        this.ipMaxAttempts = ipMaxAttempts;
    }

    public int getIpWindowSeconds() {
        return ipWindowSeconds;
    }

    public void setIpWindowSeconds(int ipWindowSeconds) {
        this.ipWindowSeconds = ipWindowSeconds;
    }

    public int getAccountMaxFailures() {
        return accountMaxFailures;
    }

    public void setAccountMaxFailures(int accountMaxFailures) {
        this.accountMaxFailures = accountMaxFailures;
    }

    public int getAccountWindowSeconds() {
        return accountWindowSeconds;
    }

    public void setAccountWindowSeconds(int accountWindowSeconds) {
        this.accountWindowSeconds = accountWindowSeconds;
    }

    public int getAccountLockSeconds() {
        return accountLockSeconds;
    }

    public void setAccountLockSeconds(int accountLockSeconds) {
        this.accountLockSeconds = accountLockSeconds;
    }

    public boolean isTrustForwardedFor() {
        return trustForwardedFor;
    }

    public void setTrustForwardedFor(boolean trustForwardedFor) {
        this.trustForwardedFor = trustForwardedFor;
    }
}
