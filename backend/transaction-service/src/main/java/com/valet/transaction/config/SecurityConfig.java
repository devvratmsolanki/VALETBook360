package com.valet.transaction.config;

import com.valet.transaction.security.JwtAuthenticationFilter;
import com.valet.transaction.security.ProblemAuthEntryPoint;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.util.StringUtils;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

/**
 * Security configuration for the transaction-service.
 *
 * <p><strong>Authorization layers for /api/operator/**</strong> (defence-in-depth):
 * <ol>
 *   <li>Security chain rule here: rejects DRIVER tokens with 403 before the
 *       request reaches any controller. Authority names are {@code ROLE_VALET},
 *       {@code ROLE_MANAGER}, {@code ROLE_ADMIN} as produced by
 *       {@link com.valet.transaction.security.JwtAuthenticationFilter}.</li>
 *   <li>{@code @PreAuthorize} on {@link com.valet.transaction.controller.OperatorController}
 *       (requires {@code @EnableMethodSecurity} below — enabled here).</li>
 *   <li>In-controller {@code operatorPrincipal()} role check — kept as the final
 *       layer so the NOT_AN_OPERATOR error code is returned with a precise
 *       userMessage for any role that somehow slips through.</li>
 * </ol>
 */
@Configuration
@EnableConfigurationProperties(JwtProperties.class)
@EnableMethodSecurity   // activates @PreAuthorize / @PostAuthorize on controllers
public class SecurityConfig {

    /**
     * Comma-separated list of allowed CORS origins/patterns.
     *
     * <p>Dev default: localhost on any port (Flutter hot-reload + web dev-server).
     * In staging/prod set this to the exact origins the Flutter app and web client
     * use, e.g.:
     * {@code CORS_ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com}
     */
    @Value("${CORS_ALLOWED_ORIGINS:http://localhost:*,http://127.0.0.1:*}")
    private String corsAllowedOriginsRaw;

    private final JwtAuthenticationFilter jwtFilter;
    private final ProblemAuthEntryPoint problemAuthEntryPoint;

    public SecurityConfig(JwtAuthenticationFilter jwtFilter, ProblemAuthEntryPoint problemAuthEntryPoint) {
        this.jwtFilter = jwtFilter;
        this.problemAuthEntryPoint = problemAuthEntryPoint;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .cors(cors -> cors.configurationSource(corsConfigurationSource()))
                // Stateless REST API with Bearer auth: CSRF not applicable.
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        // Health/readiness for compose + k8s probes.
                        .requestMatchers("/actuator/health/**", "/actuator/info").permitAll()
                        // Guest portal: public endpoints authenticated only by plate + last4 of phone.
                        .requestMatchers("/api/guest/**").permitAll()
                        // Driver mission endpoints: driver role only. Ownership of the
                        // specific transaction is enforced in the service layer (403).
                        .requestMatchers("/api/driver/**").hasRole("DRIVER")
                        // Operator floor endpoints: valet / manager / admin only.
                        // This is layer 1 of defence-in-depth; the controller adds
                        // @PreAuthorize (layer 2) and an in-method role check (layer 3).
                        // JwtAuthenticationFilter produces ROLE_<ROLE> authorities, so
                        // hasAnyRole("VALET","MANAGER","ADMIN") matches correctly.
                        .requestMatchers("/api/operator/**").hasAnyRole("VALET", "MANAGER", "ADMIN")
                        // Facility owner dashboard: read-only, scoped to their assigned location.
                        .requestMatchers("/api/facility-owner/transactions/**").hasAnyRole("FACILITY_OWNER", "MANAGER", "ADMIN")
                        // Everything else requires any authenticated caller.
                        .anyRequest().authenticated()
                )
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(problemAuthEntryPoint)
                        .accessDeniedHandler(problemAuthEntryPoint))
                .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    /**
     * CORS configuration driven by {@code CORS_ALLOWED_ORIGINS} env var.
     * Uses origin <em>patterns</em> (not plain origins) so wildcard port specs
     * like {@code http://localhost:*} work with bearer-token credentialed requests.
     * No cookies are used (Bearer-only); credentials flag is intentionally off
     * for the transaction-service so cross-site requests cannot piggyback cookies.
     */
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        List<String> allowedPatterns = parseOrigins(corsAllowedOriginsRaw);

        CorsConfiguration cfg = new CorsConfiguration();
        cfg.setAllowedOriginPatterns(allowedPatterns);
        // HEAD is included so that curl -sI / health-check style probes and HTTP
        // caching proxies receive the correct Access-Control-Allow-Origin header.
        // Browsers do not use HEAD for XHR/fetch, but excluding it means tools
        // that test with -sI (which sends HEAD) produce misleading "no ACAO" output.
        cfg.setAllowedMethods(List.of("GET", "HEAD", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"));
        cfg.setAllowedHeaders(List.of("*"));
        cfg.setExposedHeaders(List.of("Location"));
        // No cookies — credentials=false is safe here and avoids the interaction
        // between allowCredentials=true and wildcard patterns on older clients.
        cfg.setAllowCredentials(false);
        cfg.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", cfg);
        return source;
    }

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
