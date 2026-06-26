package com.valet.auth.service;

import com.valet.auth.domain.Role;
import com.valet.auth.domain.User;
import com.valet.auth.dto.LoginRequest;
import com.valet.auth.dto.RegisterRequest;
import com.valet.auth.dto.TokenResponse;
import com.valet.auth.dto.UserResponse;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.repository.UserRepository;
import com.valet.auth.security.AuthPrincipal;
import com.valet.auth.security.JwtService;
import com.valet.auth.security.ratelimit.LoginGuardService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.util.Objects;
import java.util.UUID;

/**
 * Core identity orchestration. Preserves the legacy product's role + tenancy
 * rules exactly:
 *
 * <ul>
 *   <li><b>register</b>: only admin or manager may create staff (legacy
 *       create-staff edge fn). A manager may only create users for its OWN
 *       company. Tenancy must be present for non-admin roles.</li>
 *   <li><b>login</b>: verify BCrypt hash; inactive users are rejected; a single
 *       generic message is used for both "no such user" and "bad password" to
 *       avoid account enumeration.</li>
 *   <li><b>me</b>: re-reads the live profile so a revoked/disabled account or a
 *       changed role is reflected even while an access token is still valid for
 *       its (short) TTL.</li>
 * </ul>
 */
@Service
public class AuthService {

    private final UserRepository users;
    private final RefreshTokenService refreshTokens;
    private final JwtService jwtService;
    private final PasswordEncoder passwordEncoder;
    private final LoginGuardService loginGuard;

    public AuthService(UserRepository users, RefreshTokenService refreshTokens,
                       JwtService jwtService, PasswordEncoder passwordEncoder,
                       LoginGuardService loginGuard) {
        this.users = users;
        this.refreshTokens = refreshTokens;
        this.jwtService = jwtService;
        this.passwordEncoder = passwordEncoder;
        this.loginGuard = loginGuard;
    }

    // ---------------------------------------------------------------- register

    @Transactional
    public UserResponse register(RegisterRequest req, AuthPrincipal caller) {
        Role callerRole = Role.valueOf(caller.role().toUpperCase());

        // 1) Only admin/manager may create staff (legacy create-staff rule).
        if (!callerRole.canCreateStaff()) {
            throw ServiceException.forbidden("INSUFFICIENT_PERMISSIONS",
                    "You don't have permission to create accounts.");
        }

        // 2) Managers are tenant-bound: they can only create users for their own
        //    company, and may not mint admins.
        if (callerRole == Role.MANAGER) {
            if (req.role() == Role.ADMIN) {
                throw ServiceException.forbidden("INSUFFICIENT_PERMISSIONS",
                        "Managers cannot create admin accounts.");
            }
            if (caller.companyId() == null) {
                throw ServiceException.forbidden("TENANT_MISSING",
                        "Your account is not linked to a company.");
            }
            if (!Objects.equals(req.companyId(), caller.companyId())) {
                throw ServiceException.forbidden("CROSS_TENANT",
                        "You cannot create users for another company.");
            }
        }

        // 3) Tenancy integrity: every non-admin must belong to a company.
        if (req.role() != Role.ADMIN && req.companyId() == null) {
            throw ServiceException.badRequest("TENANT_REQUIRED",
                    "A company is required for this role.");
        }

        String email = normalizeEmail(req.email());
        if (users.existsByEmail(email)) {
            throw ServiceException.conflict("EMAIL_TAKEN",
                    "An account with that email already exists.");
        }

        User user = new User(
                UUID.randomUUID(),
                email,
                passwordEncoder.encode(req.password()),
                req.role(),
                req.companyId(),
                req.locationId(),
                req.name().trim(),
                true
        );
        users.save(user);
        return UserResponse.from(user);
    }

    // ------------------------------------------------------------------- login

    @Transactional
    public TokenResponse login(LoginRequest req) {
        String email = normalizeEmail(req.email());

        // Account lockout is checked BEFORE the password so a locked account is
        // blocked even with the correct password until the lock window expires.
        // (Per-IP rate limiting is enforced earlier, in RateLimitFilter.)
        loginGuard.assertNotLocked(email);

        User user = users.findByEmail(email).orElse(null);

        // Constant-ish behaviour: same generic error whether the user is absent
        // or the password is wrong, to avoid account enumeration. We still run a
        // hash comparison against a dummy when the user is missing to reduce a
        // timing oracle.
        if (user == null) {
            passwordEncoder.matches(req.password(),
                    "$2a$12$0000000000000000000000000000000000000000000000000000");
            // Count failures against the presented email so password-spray over
            // a non-existent (or guessed) account still triggers lockout/backoff.
            // Also increments the per-IP failure counter so genuine credential-
            // stuffing from one IP eventually trips the coarse ceiling.
            loginGuard.recordFailure(email, resolveClientIp());
            throw invalidCredentials();
        }
        if (!passwordEncoder.matches(req.password(), user.getPasswordHash())) {
            loginGuard.recordFailure(email, resolveClientIp());
            throw invalidCredentials();
        }
        if (!user.isActive()) {
            throw ServiceException.forbidden("ACCOUNT_DISABLED",
                    "Your account has been disabled. Contact your administrator.");
        }

        // Success resets the failure counter (and clears any stale lock).
        loginGuard.recordSuccess(email);
        return issueTokens(user);
    }

    // ----------------------------------------------------------------- refresh

    @Transactional
    public TokenResponse refresh(String rawRefreshToken) {
        RefreshTokenService.Rotated rotated;
        try {
            rotated = refreshTokens.rotate(rawRefreshToken);
        } catch (RefreshTokenService.InvalidRefreshTokenException ex) {
            throw ServiceException.unauthorized("INVALID_REFRESH_TOKEN",
                    "Your session has expired. Please sign in again.");
        }

        User user = users.findById(rotated.userId())
                .orElseThrow(() -> ServiceException.unauthorized("INVALID_REFRESH_TOKEN",
                        "Your session has expired. Please sign in again."));

        if (!user.isActive()) {
            refreshTokens.revokeAll(user.getId());
            throw ServiceException.forbidden("ACCOUNT_DISABLED",
                    "Your account has been disabled. Contact your administrator.");
        }

        JwtService.IssuedToken access = jwtService.issueAccessToken(user);
        return TokenResponse.of(access.token(), rotated.rawToken(),
                access.expiresInSeconds(), UserResponse.from(user));
    }

    // ---------------------------------------------------------------------- me

    @Transactional(readOnly = true)
    public UserResponse me(AuthPrincipal principal) {
        User user = users.findById(principal.userId())
                .orElseThrow(() -> ServiceException.unauthorized("USER_NOT_FOUND",
                        "Your session is no longer valid. Please sign in again."));
        if (!user.isActive()) {
            throw ServiceException.forbidden("ACCOUNT_DISABLED",
                    "Your account has been disabled. Contact your administrator.");
        }
        return UserResponse.from(user);
    }

    // ------------------------------------------------------------------ logout

    @Transactional
    public void logout(AuthPrincipal principal, String rawRefreshToken, boolean allSessions) {
        if (allSessions) {
            refreshTokens.revokeAll(principal.userId());
        } else if (rawRefreshToken != null && !rawRefreshToken.isBlank()) {
            refreshTokens.revokeOne(rawRefreshToken);
        }
        // Access token is stateless and short-lived; nothing else to do.
    }

    // ----------------------------------------------------------------- helpers

    private TokenResponse issueTokens(User user) {
        JwtService.IssuedToken access = jwtService.issueAccessToken(user);
        String refresh = refreshTokens.issue(user.getId());
        return TokenResponse.of(access.token(), refresh,
                access.expiresInSeconds(), UserResponse.from(user));
    }

    private static ServiceException invalidCredentials() {
        return ServiceException.unauthorized("INVALID_CREDENTIALS",
                "Invalid email or password.");
    }

    /**
     * Resolve the client IP from the current request. {@code RateLimitFilter}
     * stamps the resolved IP as the {@code valet.clientIp} request attribute so
     * both the filter and this service agree on the same IP value (same XFF logic)
     * without duplicating the extraction code. Falls back to the raw remote address
     * if the attribute is absent (e.g. in tests or non-HTTP call paths).
     */
    private static String resolveClientIp() {
        try {
            ServletRequestAttributes attrs =
                    (ServletRequestAttributes) RequestContextHolder.currentRequestAttributes();
            HttpServletRequest request = attrs.getRequest();
            Object attr = request.getAttribute("valet.clientIp");
            if (attr instanceof String ip && !ip.isBlank()) {
                return ip;
            }
            return request.getRemoteAddr();
        } catch (IllegalStateException ex) {
            // No active request context (unit test or async execution).
            return null;
        }
    }

    private static String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase();
    }
}
