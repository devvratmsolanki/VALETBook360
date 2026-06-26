package com.valet.auth.web;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.lang.NonNull;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

/**
 * Correlation-id filter. For EVERY request (including health probes — cheap):
 * <ol>
 *   <li>Read the incoming {@code X-Request-Id} header.</li>
 *   <li>If absent or blank, generate a UUID so every request is always
 *       correlatable even without client cooperation.</li>
 *   <li>Put it in the SLF4J {@link MDC} under {@code requestId} so the log
 *       pattern ({@code [%X{requestId}]}) stamps every line for this request.</li>
 *   <li>Echo it back on the response {@code X-Request-Id} header so a client /
 *       support engineer can quote it.</li>
 *   <li>ALWAYS clear the MDC in a finally block — servlet thread pools reuse
 *       threads, so a leaked MDC value would bleed into the next request on the
 *       same thread.</li>
 * </ol>
 *
 * <p><strong>Ordering.</strong> This filter is registered via
 * {@link RequestIdFilterConfig} as a servlet-container {@code FilterRegistrationBean}
 * at {@code Ordered.HIGHEST_PRECEDENCE}, which places it before Spring Security's
 * {@code springSecurityFilterChain} (registered at order {@code -100}) and thus
 * before {@code JwtAuthenticationFilter} / {@code RateLimitFilter}. So even a
 * request rejected by the security chain (401/403) carries a request id in its
 * logs and response header.</p>
 *
 * <p>It is intentionally NOT a {@code @Component}: registering it solely through
 * the {@code FilterRegistrationBean} avoids a double registration and keeps the
 * explicit ordering as the single source of truth.</p>
 */
public class RequestIdFilter extends OncePerRequestFilter {

    public static final String HEADER = "X-Request-Id";
    public static final String MDC_KEY = "requestId";

    @Override
    protected void doFilterInternal(@NonNull HttpServletRequest request,
                                    @NonNull HttpServletResponse response,
                                    @NonNull FilterChain chain)
            throws ServletException, IOException {

        String requestId = request.getHeader(HEADER);
        if (!StringUtils.hasText(requestId)) {
            requestId = UUID.randomUUID().toString();
        }
        MDC.put(MDC_KEY, requestId);
        response.setHeader(HEADER, requestId);
        try {
            chain.doFilter(request, response);
        } finally {
            // Critical: thread pools reuse threads; never leak the id.
            MDC.remove(MDC_KEY);
        }
    }
}
