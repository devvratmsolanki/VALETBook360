package com.valet.auth.security.ratelimit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

/**
 * Redis-backed {@link LoginGuardStore} using plain {@code INCR + EXPIRE} fixed
 * windows and string flags for lockouts. Cluster-safe: all auth-service replicas
 * share the same counters, so a per-IP / per-account limit holds across the
 * fleet rather than per-JVM.
 *
 * <p><b>Fails open.</b> Every Redis call is wrapped: on any exception
 * (connection refused, timeout) we log at WARN and return a non-blocking value.
 * Rationale — a Redis outage must degrade us to "no rate limiting", never to
 * "nobody can log in". The dev/compose Redis is healthchecked so this path is
 * exceptional.
 *
 * <p>{@code StringRedisTemplate} is always autoconfigured by Spring Boot because
 * {@code spring-boot-starter-data-redis} is a hard dependency of this service, so
 * this bean is unconditional. (A no-op fail-open store is intentionally NOT
 * provided — if Redis config were ever removed the app should fail at wiring time
 * so the missing guard is noticed, rather than silently disabling protection.)
 */
@Component
public class RedisLoginGuardStore implements LoginGuardStore {

    private static final Logger log = LoggerFactory.getLogger(RedisLoginGuardStore.class);

    private final StringRedisTemplate redis;

    public RedisLoginGuardStore(StringRedisTemplate redis) {
        this.redis = redis;
    }

    @Override
    public long incrementAndGet(String key, int windowSeconds) {
        try {
            Long count = redis.opsForValue().increment(key);
            if (count != null && count == 1L) {
                // First hit in this window: stamp the TTL once.
                redis.expire(key, Duration.ofSeconds(windowSeconds));
            }
            return count == null ? 0L : count;
        } catch (RuntimeException ex) {
            log.warn("LoginGuard Redis incrementAndGet failed for '{}' (failing open): {}",
                    key, ex.getMessage());
            return 0L;
        }
    }

    @Override
    public long get(String key) {
        try {
            String v = redis.opsForValue().get(key);
            return v == null ? 0L : Long.parseLong(v);
        } catch (RuntimeException ex) {
            log.warn("LoginGuard Redis get failed for '{}' (failing open): {}", key, ex.getMessage());
            return 0L;
        }
    }

    @Override
    public void delete(String key) {
        try {
            redis.delete(key);
        } catch (RuntimeException ex) {
            log.warn("LoginGuard Redis delete failed for '{}': {}", key, ex.getMessage());
        }
    }

    @Override
    public void setWithTtl(String key, String value, int ttlSeconds) {
        try {
            redis.opsForValue().set(key, value, Duration.ofSeconds(ttlSeconds));
        } catch (RuntimeException ex) {
            log.warn("LoginGuard Redis setWithTtl failed for '{}': {}", key, ex.getMessage());
        }
    }

    @Override
    public boolean exists(String key) {
        try {
            return Boolean.TRUE.equals(redis.hasKey(key));
        } catch (RuntimeException ex) {
            log.warn("LoginGuard Redis exists failed for '{}' (failing open): {}",
                    key, ex.getMessage());
            return false;
        }
    }

    @Override
    public long ttlSeconds(String key) {
        try {
            Long ttl = redis.getExpire(key, TimeUnit.SECONDS);
            return ttl == null || ttl < 0 ? 0L : ttl;
        } catch (RuntimeException ex) {
            log.warn("LoginGuard Redis ttl failed for '{}': {}", key, ex.getMessage());
            return 0L;
        }
    }
}
