package com.valet.auth.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Externalised JWT config. The secret is supplied via env (JWT_SECRET, the
 * shared-contract var read by every service that validates these access tokens);
 * never hardcoded. Must be >= 32 bytes for HS256.
 */
@ConfigurationProperties(prefix = "auth.jwt")
public class JwtProperties {

    /** HMAC signing secret (base64 or raw); injected from env. */
    private String secret;

    /** Token issuer claim. */
    private String issuer = "valet-auth";

    /** Access-token lifetime in seconds (default 15m). */
    private long accessTtlSeconds = 900;

    /** Refresh-token lifetime in seconds (default 30d). */
    private long refreshTtlSeconds = 2_592_000;

    public String getSecret() {
        return secret;
    }

    public void setSecret(String secret) {
        this.secret = secret;
    }

    public String getIssuer() {
        return issuer;
    }

    public void setIssuer(String issuer) {
        this.issuer = issuer;
    }

    public long getAccessTtlSeconds() {
        return accessTtlSeconds;
    }

    public void setAccessTtlSeconds(long accessTtlSeconds) {
        this.accessTtlSeconds = accessTtlSeconds;
    }

    public long getRefreshTtlSeconds() {
        return refreshTtlSeconds;
    }

    public void setRefreshTtlSeconds(long refreshTtlSeconds) {
        this.refreshTtlSeconds = refreshTtlSeconds;
    }
}
