package com.valet.auth.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * In-app help assistant chat turn. The client sends the running conversation
 * (oldest→newest, last entry must be the user's new message). Role/name are
 * derived server-side from the JWT, never trusted from the body.
 *
 * Bounds are enforced here as the FIRST line of defence (bad requests are
 * rejected before any Groq call); the service re-clamps as defence in depth.
 */
public record AssistantChatRequest(
        @NotEmpty @Size(max = 50, message = "Too many messages.") @Valid List<Message> messages
) {
    public record Message(
            // Only "user" or "assistant" — never "system" (blocks fake system-prompt injection).
            @Pattern(regexp = "user|assistant", message = "role must be 'user' or 'assistant'")
            String role,
            @NotBlank @Size(max = 8000, message = "Message too long.")
            String content
    ) {
    }
}
