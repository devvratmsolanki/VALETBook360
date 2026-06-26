package com.valet.auth.dto;

/**
 * Login / refresh response. {@code accessToken} is the short-lived JWT;
 * {@code refreshToken} is the opaque rotating handle the client stores securely.
 */
public record TokenResponse(
        String accessToken,
        String refreshToken,
        String tokenType,
        long expiresIn,
        UserResponse user
) {
    public static TokenResponse of(String accessToken, String refreshToken,
                                   long expiresIn, UserResponse user) {
        return new TokenResponse(accessToken, refreshToken, "Bearer", expiresIn, user);
    }
}
