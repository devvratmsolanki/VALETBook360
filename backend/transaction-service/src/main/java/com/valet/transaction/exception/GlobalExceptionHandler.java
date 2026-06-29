package com.valet.transaction.exception;

import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.net.URI;
import java.time.Instant;
import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * Translates exceptions into RFC 7807 problem+json with the legacy error
 * envelope fields ({@code code}, {@code userMessage}). We never leak stack
 * traces or raw SQL/driver messages to the client; unexpected errors are
 * logged server-side and returned as a generic 500.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(ServiceException.class)
    public ResponseEntity<ProblemDetail> handleService(ServiceException ex, HttpServletRequest req) {
        return build(ex.getStatus(), ex.getCode(), ex.getUserMessage(), null, req);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ProblemDetail> handleValidation(MethodArgumentNotValidException ex,
                                                          HttpServletRequest req) {
        String detail = ex.getBindingResult().getFieldErrors().stream()
                .map(f -> f.getField() + ": " + f.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return build(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR",
                "Please check the highlighted fields and try again.", detail, req);
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class})
    public ResponseEntity<ProblemDetail> handleUnreadable(Exception ex, HttpServletRequest req) {
        return build(HttpStatus.BAD_REQUEST, "MALFORMED_REQUEST",
                "The request was malformed.", null, req);
    }

    /**
     * Out-of-range request parameters (e.g. a page index whose offset exceeds
     * {@code Integer.MAX_VALUE}) surface as {@link IllegalArgumentException}. That
     * is a client error, so map it to 400 rather than the catch-all 500.
     */
    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ProblemDetail> handleIllegalArgument(IllegalArgumentException ex,
                                                               HttpServletRequest req) {
        return build(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR",
                "One or more request parameters were out of range.", null, req);
    }

    /**
     * Concurrent modification of the same transaction. JPA optimistic locking
     * (the {@code @Version} column) raises this when two callers mutate the same
     * row from the same prior version — e.g. two operators double-assigning, or a
     * double-deliver. Surface a clean 409 so the client refreshes and retries
     * instead of silently losing one update (last-write-wins).
     */
    @ExceptionHandler(org.springframework.dao.OptimisticLockingFailureException.class)
    public ResponseEntity<ProblemDetail> handleOptimisticLock(
            org.springframework.dao.OptimisticLockingFailureException ex, HttpServletRequest req) {
        return build(HttpStatus.CONFLICT, "CONCURRENT_UPDATE",
                "This car was just updated by someone else — refresh and retry.", null, req);
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ProblemDetail> handleIntegrity(DataIntegrityViolationException ex,
                                                         HttpServletRequest req) {
        log.warn("Data integrity violation: {}", ex.getMostSpecificCause().getMessage());
        return build(HttpStatus.CONFLICT, "CONFLICT",
                "That change conflicts with the current state.", null, req);
    }

    /**
     * Spring throws this when a route exists but the HTTP method is wrong (e.g.
     * {@code GET} on a POST-only endpoint). Without this handler it falls through
     * to the catch-all 500, which is wrong — wrong-method is a client error, not
     * a server error, and the 500 pollutes monitoring with phantom alerts.
     * The {@code Allow} header lists the methods the endpoint actually supports,
     * per RFC 9110 §15.5.6.
     */
    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ProblemDetail> handleMethodNotSupported(
            HttpRequestMethodNotSupportedException ex, HttpServletRequest req) {
        ResponseEntity<ProblemDetail> resp = build(HttpStatus.METHOD_NOT_ALLOWED,
                "METHOD_NOT_ALLOWED",
                "HTTP method '" + ex.getMethod() + "' is not supported on this endpoint.",
                null, req);
        String[] supported = ex.getSupportedMethods();
        if (supported != null && supported.length > 0) {
            return ResponseEntity.status(resp.getStatusCode())
                    .headers(resp.getHeaders())
                    .header(HttpHeaders.ALLOW, String.join(", ", Arrays.asList(supported)))
                    .body(resp.getBody());
        }
        return resp;
    }

    /**
     * Spring 6 / Boot 3 maps unknown paths to {@code NoResourceFoundException}
     * (not {@code NoHandlerFoundException}) when the default servlet is disabled.
     * Without this handler it would also fall to the catch-all 500.
     */
    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<ProblemDetail> handleNoResource(NoResourceFoundException ex,
                                                          HttpServletRequest req) {
        return build(HttpStatus.NOT_FOUND, "NOT_FOUND",
                "The requested resource was not found.", null, req);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ProblemDetail> handleUnexpected(Exception ex, HttpServletRequest req) {
        log.error("Unhandled exception on {} {}", req.getMethod(), req.getRequestURI(), ex);
        return build(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR",
                "Something went wrong on our end. Please try again.", null, req);
    }

    private ResponseEntity<ProblemDetail> build(HttpStatus status, String code, String userMessage,
                                                String detail, HttpServletRequest req) {
        ProblemDetail pd = ProblemDetail.forStatus(status);
        pd.setTitle(status.getReasonPhrase());
        pd.setType(URI.create("about:blank"));
        pd.setInstance(URI.create(req.getRequestURI()));
        pd.setProperty("code", code);
        pd.setProperty("userMessage", userMessage);
        if (detail != null) {
            pd.setProperty("detail", detail);
        }
        // Correlation id (set by RequestIdFilter, MDC key "requestId") so a
        // client/support engineer can tie this error to the server logs. May be
        // absent for errors raised outside a request scope.
        String requestId = MDC.get("requestId");
        if (requestId != null) {
            pd.setProperty("requestId", requestId);
        }
        pd.setProperty("timestamp", Instant.now().toString());
        return ResponseEntity.status(status)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(pd);
    }
}
