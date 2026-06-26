package com.valet.auth.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.time.Instant;
import java.util.Map;

/**
 * Emits RFC 7807 problem+json for the two security-layer outcomes that happen
 * BEFORE controllers run: unauthenticated (401) and forbidden (403). Keeps the
 * error envelope consistent with the controller-level GlobalExceptionHandler and
 * carries the {@code userMessage} the legacy client always displays.
 */
@Component
public class ProblemAuthEntryPoint implements AuthenticationEntryPoint, AccessDeniedHandler {

    private final ObjectMapper mapper;

    public ProblemAuthEntryPoint(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response,
                         AuthenticationException authException) throws IOException {
        write(response, request, HttpStatus.UNAUTHORIZED, "AUTH_REQUIRED",
                "You need to sign in to continue.");
    }

    @Override
    public void handle(HttpServletRequest request, HttpServletResponse response,
                       AccessDeniedException accessDeniedException) throws IOException {
        write(response, request, HttpStatus.FORBIDDEN, "FORBIDDEN",
                "You don't have permission to perform this action.");
    }

    private void write(HttpServletResponse response, HttpServletRequest request,
                       HttpStatus status, String code, String userMessage) throws IOException {
        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        Map<String, Object> body = Map.of(
                "type", "about:blank",
                "title", status.getReasonPhrase(),
                "status", status.value(),
                "code", code,
                "userMessage", userMessage,
                "instance", request.getRequestURI(),
                "timestamp", Instant.now().toString()
        );
        mapper.writeValue(response.getOutputStream(), body);
    }
}
