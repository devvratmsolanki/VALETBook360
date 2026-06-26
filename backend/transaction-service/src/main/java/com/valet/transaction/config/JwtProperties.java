package com.valet.transaction.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Externalised JWT config for this resource server. Only the shared HS256
 * secret is needed — this service validates tokens, it never issues them. The
 * secret is supplied via env ({@code JWT_SECRET}, same value as the
 * auth-service) and must be >= 32 bytes for HS256.
 */
@ConfigurationProperties(prefix = "valet.jwt")
public class JwtProperties {

    /** HMAC signing secret (raw UTF-8); injected from env. Never hardcoded. */
    private String secret;

    public String getSecret() {
        return secret;
    }

    public void setSecret(String secret) {
        this.secret = secret;
    }
}
