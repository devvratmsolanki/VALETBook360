package com.valet.transaction.security;

import com.valet.transaction.exception.ServiceException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

/**
 * Pulls the {@link AuthPrincipal} out of the SecurityContext for controllers.
 * The security chain guarantees authentication before controllers run, so a
 * missing principal here is a programming error, surfaced as a clean 401.
 */
public final class SecurityUtils {

    private SecurityUtils() {
    }

    public static AuthPrincipal currentPrincipal() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof AuthPrincipal principal)) {
            throw new ServiceException(
                    org.springframework.http.HttpStatus.UNAUTHORIZED,
                    "AUTH_REQUIRED", "You need to sign in to continue.");
        }
        return principal;
    }
}
