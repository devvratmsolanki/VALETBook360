package com.valet.auth.web;

import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

/**
 * Registers {@link RequestIdFilter} as a servlet-container filter at
 * {@link Ordered#HIGHEST_PRECEDENCE}.
 *
 * <p>This is deliberately a NEW config class (not {@code SecurityConfig}) so the
 * security chain is left untouched. Spring Boot registers its
 * {@code springSecurityFilterChain} {@code DelegatingFilterProxy} at order
 * {@code SecurityProperties.DEFAULT_FILTER_ORDER} ({@code -100}); registering
 * the request-id filter at {@code HIGHEST_PRECEDENCE} ({@code Integer.MIN_VALUE})
 * guarantees it runs BEFORE the entire security chain — and therefore before
 * {@code JwtAuthenticationFilter} and {@code RateLimitFilter} — so the
 * correlation id is in the MDC for every log line and on every response,
 * including requests the security chain rejects.</p>
 */
@Configuration
public class RequestIdFilterConfig {

    @Bean
    public FilterRegistrationBean<RequestIdFilter> requestIdFilterRegistration() {
        FilterRegistrationBean<RequestIdFilter> reg = new FilterRegistrationBean<>(new RequestIdFilter());
        reg.setOrder(Ordered.HIGHEST_PRECEDENCE);
        // Run for every request, including the actuator health probes (cheap).
        reg.addUrlPatterns("/*");
        reg.setName("requestIdFilter");
        return reg;
    }
}
