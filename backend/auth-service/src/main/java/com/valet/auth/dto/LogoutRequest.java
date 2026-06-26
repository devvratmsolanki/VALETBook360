package com.valet.auth.dto;

/**
 * Logout payload. The refresh token is optional: if present we revoke just that
 * session; the {@code allSessions} flag revokes every active refresh token for
 * the authenticated user (e.g. "sign out everywhere").
 */
public record LogoutRequest(
        String refreshToken,
        boolean allSessions
) {
}
