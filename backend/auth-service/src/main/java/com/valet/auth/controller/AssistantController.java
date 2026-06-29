package com.valet.auth.controller;

import com.valet.auth.dto.AssistantChatRequest;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.security.AuthPrincipal;
import com.valet.auth.service.AssistantService;
import jakarta.validation.Valid;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * In-app help assistant endpoint. Any authenticated role may use it; the role is
 * read from the JWT and used to scope the assistant's guidance. The Anthropic API
 * key never leaves the server (see {@link AssistantService}).
 */
@RestController
public class AssistantController {

    private final AssistantService service;

    public AssistantController(AssistantService service) {
        this.service = service;
    }

    /** POST /assistant/chat — returns {"reply": "..."}. */
    @PostMapping("/assistant/chat")
    public Map<String, String> chat(@Valid @RequestBody AssistantChatRequest req) {
        return Map.of("reply", service.chat(principal(), req));
    }

    private AuthPrincipal principal() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof AuthPrincipal p)) {
            throw ServiceException.unauthorized("AUTH_REQUIRED",
                    "You need to sign in to continue.");
        }
        return p;
    }
}
