package com.valet.transaction.config;

import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.StringRedisTemplate;

/**
 * Realtime fan-out wiring. The connection factory (Lettuce) is auto-configured
 * from {@code spring.data.redis.host}/{@code .port} (env {@code REDIS_HOST} /
 * {@code REDIS_PORT}). Lettuce connects lazily, so the service still boots when
 * Redis is unreachable; the {@code RealtimeEventPublisher} swallows publish
 * failures so an outage never affects committed work or the HTTP response.
 *
 * <p>The {@link StringRedisTemplate} bean is normally auto-configured; this
 * declaration is explicit (and conditional) so the realtime contract has a
 * single reviewable home and is never silently dropped.</p>
 */
@Configuration
public class RedisConfig {

    @Bean
    @ConditionalOnMissingBean
    public StringRedisTemplate stringRedisTemplate(RedisConnectionFactory connectionFactory) {
        return new StringRedisTemplate(connectionFactory);
    }
}
