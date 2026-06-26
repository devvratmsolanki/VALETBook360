package com.valet.auth.security.ratelimit;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.valet.auth.config.LoginGuardProperties;
import com.valet.auth.exception.ServiceException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Per-IP failure-rate gate for the public auth POST endpoints. Registered BEFORE
 * the JWT filter (and thus before the controller) so {@code /auth/refresh} —
 * which never reaches {@code AuthService.login} — is covered by the coarse
 * per-IP ceiling, and abusive traffic is shed before any DB/BCrypt work.
 *
 * <p>Scope: ONLY {@code POST /auth/login} and {@code POST /auth/refresh}. Health
 * probes ({@code /actuator/health/**}) and every other path skip the filter
 * entirely (see {@link #shouldNotFilter}).
 *
 * <p><b>This filter is read-only with respect to the per-IP counter.</b> It calls
 * {@link LoginGuardService#checkIpFailureLimit} which reads the current failure
 * count but does NOT increment it. Incrementing happens in
 * {@code AuthService.login} via {@code recordFailure(email, clientIp)} only when
 * a login attempt actually fails. This means:
 * <ul>
 *   <li>Successful logins for any account from this IP do not inflate the counter.</li>
 *   <li>Shared-egress IPs (NAT/corporate proxy/CGNAT) are not penalised for
 *       legitimate users' successful logins.</li>
 *   <li>{@code /auth/refresh} requests (success or failure) do not inflate the
 *       login-failure counter (they are a different operation).</li>
 * </ul>
 *
 * <p>Because this runs before Spring MVC's exception handling, it renders the
 * RFC 7807 problem+json envelope itself (matching {@code GlobalExceptionHandler}:
 * {@code code}, {@code userMessage}, {@code timestamp}) and sets {@code Retry-After}.
 *
 * <p><b>Client IP extraction.</b> When {@code trustForwardedFor} is on (prod,
 * behind a reverse proxy) we use the FIRST hop of {@code X-Forwarded-For}. Trust
 * assumption: a single trusted proxy sets/overwrites XFF. If the service is
 * directly internet-exposed, set {@code AUTH_RL_TRUST_XFF=false} — otherwise a
 * client could spoof XFF to rotate its apparent IP and dodge the limit.
 */
@Component
public class RateLimitFilter extends OncePerRequestFilter {

    private final LoginGuardService guard;
    private final LoginGuardProperties props;
    private final ObjectMapper objectMapper;

    public RateLimitFilter(LoginGuardService guard, LoginGuardProperties props,
                           ObjectMapper objectMapper) {
        this.guard = guard;
        this.props = props;
        this.objectMapper = objectMapper;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        // Only POST to the two public auth entry points are checked.
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            return true;
        }
        String path = request.getServletPath();
        return !("/auth/login".equals(path) || "/auth/refresh".equals(path));
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String clientIp = clientIp(request);
        // Expose the resolved IP as a request attribute so AuthService can pass it
        // to recordFailure(email, clientIp) without needing a second extraction.
        request.setAttribute("valet.clientIp", clientIp);
        try {
            guard.checkIpFailureLimit(clientIp);
        } catch (ServiceException ex) {
            writeProblem(request, response, ex);
            return;
        }
        chain.doFilter(request, response);
    }

    /**
     * Resolve the client IP. Prefers the first hop of {@code X-Forwarded-For}
     * when {@code trustForwardedFor} is enabled; otherwise the socket peer.
     */
    private String clientIp(HttpServletRequest request) {
        if (props.isTrustForwardedFor()) {
            String xff = request.getHeader("X-Forwarded-For");
            if (StringUtils.hasText(xff)) {
                // "client, proxy1, proxy2" — the left-most is the original client.
                int comma = xff.indexOf(',');
                String first = (comma >= 0 ? xff.substring(0, comma) : xff).trim();
                if (StringUtils.hasText(first)) {
                    return first;
                }
            }
        }
        return request.getRemoteAddr();
    }

    private void writeProblem(HttpServletRequest req, HttpServletResponse resp,
                              ServiceException ex) throws IOException {
        resp.setStatus(ex.getStatus().value());
        resp.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        if (ex.getRetryAfterSeconds() > 0) {
            resp.setHeader(HttpHeaders.RETRY_AFTER, Long.toString(ex.getRetryAfterSeconds()));
        }
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("type", "about:blank");
        body.put("title", ex.getStatus().getReasonPhrase());
        body.put("status", ex.getStatus().value());
        body.put("instance", req.getRequestURI());
        body.put("code", ex.getCode());
        body.put("userMessage", ex.getUserMessage());
        body.put("timestamp", Instant.now().toString());
        objectMapper.writeValue(resp.getWriter(), body);
    }
}
