package com.valet.auth.exception;

import org.springframework.http.HttpStatus;

/**
 * Domain-level failure carrying an HTTP status, a stable machine {@code code},
 * and a toast-safe {@code userMessage} — the direct port of the legacy
 * {@code ServiceError.userMessage} contract from src/lib/errors.js. The client
 * always shows {@code userMessage}; {@code code} is for programmatic handling.
 */
public class ServiceException extends RuntimeException {

    private final HttpStatus status;
    private final String code;
    private final String userMessage;
    /** Optional hint for a {@code Retry-After} header (seconds). 0 = omit. */
    private final long retryAfterSeconds;

    public ServiceException(HttpStatus status, String code, String userMessage) {
        this(status, code, userMessage, 0L);
    }

    public ServiceException(HttpStatus status, String code, String userMessage, long retryAfterSeconds) {
        super(userMessage);
        this.status = status;
        this.code = code;
        this.userMessage = userMessage;
        this.retryAfterSeconds = retryAfterSeconds;
    }

    public static ServiceException unauthorized(String code, String userMessage) {
        return new ServiceException(HttpStatus.UNAUTHORIZED, code, userMessage);
    }

    public static ServiceException forbidden(String code, String userMessage) {
        return new ServiceException(HttpStatus.FORBIDDEN, code, userMessage);
    }

    public static ServiceException conflict(String code, String userMessage) {
        return new ServiceException(HttpStatus.CONFLICT, code, userMessage);
    }

    public static ServiceException badRequest(String code, String userMessage) {
        return new ServiceException(HttpStatus.BAD_REQUEST, code, userMessage);
    }

    public static ServiceException notFound(String code, String userMessage) {
        return new ServiceException(HttpStatus.NOT_FOUND, code, userMessage);
    }

    public static ServiceException tooManyRequests(String code, String userMessage) {
        return new ServiceException(HttpStatus.TOO_MANY_REQUESTS, code, userMessage);
    }

    public static ServiceException tooManyRequests(String code, String userMessage, long retryAfterSeconds) {
        return new ServiceException(HttpStatus.TOO_MANY_REQUESTS, code, userMessage, retryAfterSeconds);
    }

    public HttpStatus getStatus() {
        return status;
    }

    public String getCode() {
        return code;
    }

    public String getUserMessage() {
        return userMessage;
    }

    public long getRetryAfterSeconds() {
        return retryAfterSeconds;
    }
}
