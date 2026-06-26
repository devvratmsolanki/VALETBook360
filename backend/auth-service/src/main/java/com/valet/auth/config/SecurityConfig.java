package com.valet.auth.config;

import com.valet.auth.security.JwtAuthenticationFilter;
import com.valet.auth.security.ProblemAuthEntryPoint;
import com.valet.auth.security.ratelimit.RateLimitFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.util.StringUtils;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

@Configuration
@EnableConfigurationProperties({JwtProperties.class, LoginGuardProperties.class})
public class SecurityConfig {

    /**
     * Comma-separated list of allowed CORS origins/patterns.
     *
     * <p>Dev default permits localhost on any port (Flutter hot-reload + web
     * dev-server). In every real environment (staging, prod) override this with
     * the exact origins the Flutter app and web front-end run on, e.g.:
     * {@code CORS_ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com}
     *
     * <p>Wildcard patterns such as {@code http://localhost:*} use Spring's
     * origin-pattern matching so credentialed requests ({@code Authorization}
     * header) remain permitted even when the pattern contains {@code *}.
     */
    @Value("${CORS_ALLOWED_ORIGINS:http://localhost:*,http://127.0.0.1:*}")
    private String corsAllowedOriginsRaw;

    private final JwtAuthenticationFilter jwtFilter;
    private final ProblemAuthEntryPoint problemAuthEntryPoint;
    private final RateLimitFilter rateLimitFilter;

    public SecurityConfig(JwtAuthenticationFilter jwtFilter, ProblemAuthEntryPoint problemAuthEntryPoint,
                          RateLimitFilter rateLimitFilter) {
        this.jwtFilter = jwtFilter;
        this.problemAuthEntryPoint = problemAuthEntryPoint;
        this.rateLimitFilter = rateLimitFilter;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .cors(c -> c.configurationSource(corsConfigurationSource()))
                // Stateless REST API with Bearer auth: CSRF not applicable.
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        // Public auth entry points.
                        .requestMatchers("/auth/login", "/auth/refresh").permitAll()
                        // Health/readiness for compose + k8s probes.
                        .requestMatchers("/actuator/health/**", "/actuator/info").permitAll()
                        // Super-admin cross-tenant views: ADMIN only at the chain.
                        // (The service re-checks for precise RFC7807 codes; this is
                        // the coarse first gate so a valet/driver token never even
                        // reaches the handler — mirrors the operator-fix pattern.)
                        .requestMatchers("/api/admin/**").hasRole("ADMIN")
                        // Tenant management (companies + locations): ADMIN or MANAGER.
                        // Per-tenant scoping (a manager only their own company) and
                        // the admin-only POST /api/companies are enforced in-service.
                        .requestMatchers("/api/companies/**", "/api/locations/**")
                                .hasAnyRole("ADMIN", "MANAGER")
                        // Everything else (register, me, logout) requires a valid token.
                        // Fine-grained role checks (admin/manager only on register) live
                        // in the service layer so we can return precise userMessages.
                        .anyRequest().authenticated()
                )
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(problemAuthEntryPoint)
                        .accessDeniedHandler(problemAuthEntryPoint))
                // Rate-limit gate runs FIRST (before JWT auth) so abusive
                // login/refresh traffic is shed before any DB/BCrypt work and so
                // unauthenticated refresh floods are covered. Both custom filters
                // anchor on UsernamePasswordAuthenticationFilter (a registered
                // Security filter — a custom class such as JwtAuthenticationFilter
                // is NOT a valid position reference). Successive addFilterBefore
                // calls on the same anchor insert each new filter immediately
                // before it, so the FIRST-added (rate-limit) ends up earliest in
                // the chain and the JWT filter runs after it. The rate-limit
                // filter self-scopes to POST /auth/login + /auth/refresh only.
                .addFilterBefore(rateLimitFilter, UsernamePasswordAuthenticationFilter.class)
                .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        List<String> allowedPatterns = parseOrigins(corsAllowedOriginsRaw);

        CorsConfiguration cfg = new CorsConfiguration();
        // Origin patterns (not plain origins) so credentialed requests are still
        // permitted even when a wildcard port pattern like http://localhost:* is used.
        cfg.setAllowedOriginPatterns(allowedPatterns);
        // HEAD is included so that curl -sI / health-check style probes and HTTP
        // caching proxies receive the correct Access-Control-Allow-Origin header.
        // Browsers do not use HEAD for XHR/fetch, but excluding it means tools
        // that test with -sI (which sends HEAD) produce misleading "no ACAO" output.
        cfg.setAllowedMethods(List.of("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        cfg.setAllowedHeaders(List.of("*"));
        cfg.setExposedHeaders(List.of("Authorization"));
        cfg.setAllowCredentials(true);
        cfg.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", cfg);
        return source;
    }

    /**
     * Stop Spring Boot from ALSO auto-registering {@link RateLimitFilter} (a
     * {@code @Component} extending {@code OncePerRequestFilter}) directly in the
     * servlet container. It must run exactly once, inside the Spring Security
     * chain where we place it via {@code addFilterBefore} — double registration
     * would double-count attempts.
     */
    @Bean
    public FilterRegistrationBean<RateLimitFilter> rateLimitFilterRegistration(RateLimitFilter filter) {
        FilterRegistrationBean<RateLimitFilter> reg = new FilterRegistrationBean<>(filter);
        reg.setEnabled(false);
        return reg;
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        // Strength 12: stronger than the BCrypt default (10) without being so slow
        // it harms login throughput. Tune via load testing under real traffic.
        return new BCryptPasswordEncoder(12);
    }

    /**
     * Split the comma-separated {@code CORS_ALLOWED_ORIGINS} value, trimming
     * whitespace. Returns a dev-localhost-only list as the fallback so an
     * empty/missing env var is never treated as "allow everything".
     */
    private static List<String> parseOrigins(String raw) {
        if (!StringUtils.hasText(raw)) {
            return List.of("http://localhost:*", "http://127.0.0.1:*");
        }
        return Arrays.stream(raw.split(","))
                .map(String::trim)
                .filter(StringUtils::hasText)
                .toList();
    }
}
