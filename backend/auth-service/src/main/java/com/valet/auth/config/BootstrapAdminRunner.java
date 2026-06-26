package com.valet.auth.config;

import com.valet.auth.domain.Role;
import com.valet.auth.domain.User;
import com.valet.auth.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.UUID;

/**
 * Solves the bootstrap chicken-and-egg: {@code /auth/register} requires an
 * admin caller, but a fresh DB has none. On startup, IF a bootstrap admin email
 * + password are configured AND no admin exists yet, seed exactly one admin.
 *
 * <p>This preserves the legacy "first user becomes admin" intent from
 * {@code autoCreateProfile} but makes it explicit and config-driven instead of
 * TOCTOU-prone on a public signup path. Disabled by default (no env = no-op).
 * After first boot, set the env back to empty or rotate the password via the
 * future user-service.</p>
 */
@Configuration
public class BootstrapAdminRunner {

    private static final Logger log = LoggerFactory.getLogger(BootstrapAdminRunner.class);

    @Bean
    @ConfigurationProperties(prefix = "auth.bootstrap-admin")
    public BootstrapAdminProps bootstrapAdminProps() {
        return new BootstrapAdminProps();
    }

    @Bean
    public ApplicationRunner bootstrapAdmin(BootstrapAdminProps props,
                                            UserRepository users,
                                            PasswordEncoder encoder,
                                            TransactionTemplate tx) {
        return args -> {
            if (props.getEmail() == null || props.getEmail().isBlank()
                    || props.getPassword() == null || props.getPassword().isBlank()) {
                return; // not configured -> no-op
            }
            tx.executeWithoutResult(status -> seed(props, users, encoder));
        };
    }

    @Transactional
    void seed(BootstrapAdminProps props, UserRepository users, PasswordEncoder encoder) {
        if (users.existsByRole(Role.ADMIN)) {
            log.info("Bootstrap admin skipped: an admin already exists.");
            return;
        }
        String email = props.getEmail().trim().toLowerCase();
        if (users.existsByEmail(email)) {
            log.info("Bootstrap admin skipped: email already present.");
            return;
        }
        users.save(new User(UUID.randomUUID(), email,
                encoder.encode(props.getPassword()), Role.ADMIN,
                null, null, props.getName(), true));
        log.info("Bootstrap admin created: {}", email);
    }

    public static class BootstrapAdminProps {
        private String email;
        private String password;
        private String name = "Administrator";

        public String getEmail() {
            return email;
        }

        public void setEmail(String email) {
            this.email = email;
        }

        public String getPassword() {
            return password;
        }

        public void setPassword(String password) {
            this.password = password;
        }

        public String getName() {
            return name;
        }

        public void setName(String name) {
            this.name = name;
        }
    }
}
