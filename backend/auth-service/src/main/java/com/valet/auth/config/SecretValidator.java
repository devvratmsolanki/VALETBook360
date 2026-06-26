package com.valet.auth.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;

/**
 * Eager, profile-independent fail-fast guard for the JWT signing secret.
 *
 * <p>Runs at context initialisation (via {@link InitializingBean}). If
 * {@code auth.jwt.secret} (env {@code JWT_SECRET}) is null, blank, or shorter
 * than 32 bytes — too weak for HS256 — it throws and ABORTS boot with a clear,
 * actionable message. This makes a missing/empty secret a loud startup failure
 * regardless of the active Spring profile.
 *
 * <p>{@link com.valet.auth.security.JwtService} performs the same length check
 * in its constructor (so the failure happens even if this bean were removed),
 * but JwtService's message is terse and its failure is buried in a bean-creation
 * stack. This validator surfaces the problem first, with a remediation hint.
 *
 * <p>The dev default secret in {@code application.yml} is 40 bytes, so local
 * {@code docker compose} still boots. The {@code prod} profile removes that
 * fallback entirely, so a missing env var resolves to empty and aborts here.
 */
@Component
public class SecretValidator implements InitializingBean {

    private static final Logger log = LoggerFactory.getLogger(SecretValidator.class);
    private static final int MIN_SECRET_BYTES = 32;

    private final JwtProperties props;

    public SecretValidator(JwtProperties props) {
        this.props = props;
    }

    @Override
    public void afterPropertiesSet() {
        String secret = props.getSecret();
        int len = secret == null ? 0 : secret.getBytes(StandardCharsets.UTF_8).length;

        if (secret == null || secret.isBlank() || len < MIN_SECRET_BYTES) {
            String reason = (secret == null || secret.isBlank())
                    ? "is missing or blank"
                    : "is only " + len + " bytes (need >= " + MIN_SECRET_BYTES + ")";
            String msg = "FATAL: JWT signing secret " + reason + ". "
                    + "Set the JWT_SECRET environment variable to a strong value "
                    + "(generate with: openssl rand -base64 48). "
                    + "In the 'prod' profile there is NO insecure fallback, so this "
                    + "is a hard boot failure by design. Aborting startup.";
            // Log before throwing so the reason is visible even if the wrapped
            // BeanCreationException stack obscures it.
            log.error(msg);
            throw new IllegalStateException(msg);
        }

        log.info("JWT signing secret validated ({} bytes, HS256-ready).", len);
    }
}
