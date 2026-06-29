package com.valet.auth.dto;

import jakarta.validation.constraints.NotEmpty;

import java.util.List;

/**
 * In-app help assistant chat turn. The client sends the running conversation
 * (oldest→newest, last entry must be the user's new message). Role/name are
 * derived server-side from the JWT, never trusted from the body.
 */
public record AssistantChatRequest(
        @NotEmpty List<Message> messages
) {
    public record Message(String role, String content) {
    }
}
