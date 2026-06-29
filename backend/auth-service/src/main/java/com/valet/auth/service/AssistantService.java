package com.valet.auth.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.valet.auth.dto.AssistantChatRequest;
import com.valet.auth.exception.ServiceException;
import com.valet.auth.security.AuthPrincipal;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * In-app help assistant — proxies a short, app-aware chat to the Anthropic
 * Messages API. The API key lives ONLY here (server env), never in the client.
 * Raw HTTP (java.net.http) keeps the service dependency-light; the conversation
 * is bounded and the system prompt is role-scoped to THIS product.
 *
 * Configure via env: ANTHROPIC_API_KEY (required to enable), ASSISTANT_MODEL
 * (optional, default claude-opus-4-8).
 */
@Service
public class AssistantService {

    private static final String ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
    private static final int MAX_TURNS = 20;
    private static final int MAX_CHARS = 4000;

    private static final String APP_OVERVIEW = """
            LogBook360 (ValetBook360) is a multi-tenant valet-management platform.
            Hierarchy: Super Admin -> Company (owner) -> Operator (valet) -> Driver.
            - Super Admin manages every company, location, user, and all transactions.
            - Company owner manages their own company's locations, operators, drivers, contracts, key slots.
            - Operator (valet) checks cars in/out on the floor and assigns key slots + drivers.
            - Driver receives park/retrieve missions and advances them (assigned -> en route -> arrived -> delivered).
            Key features: vehicle check-in, the operator floor, per-location key-slot pools (numbered 1..capacity or
            custom names; the next free slot auto-assigns and is reused when a car leaves), driver assignment,
            transactions, team management (add/edit/delete operators & drivers, assign locations), and dashboards.""";

    private final ObjectMapper mapper;
    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    @Value("${ANTHROPIC_API_KEY:}")
    private String apiKey;

    @Value("${ASSISTANT_MODEL:claude-opus-4-8}")
    private String model;

    public AssistantService(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    public String chat(AuthPrincipal caller, AssistantChatRequest req) {
        if (apiKey == null || apiKey.isBlank()) {
            throw ServiceException.badRequest("ASSISTANT_DISABLED",
                    "The help assistant isn't configured yet. Set ANTHROPIC_API_KEY.");
        }

        // Validate + clamp the conversation.
        List<AssistantChatRequest.Message> raw = req.messages();
        List<Map<String, String>> messages = new ArrayList<>();
        int from = Math.max(0, raw.size() - MAX_TURNS);
        for (int i = from; i < raw.size(); i++) {
            AssistantChatRequest.Message m = raw.get(i);
            if (m == null || m.content() == null || m.content().isBlank()) continue;
            String role = "assistant".equals(m.role()) ? "assistant" : "user";
            String content = m.content().length() > MAX_CHARS
                    ? m.content().substring(0, MAX_CHARS) : m.content();
            Map<String, String> entry = new LinkedHashMap<>();
            entry.put("role", role);
            entry.put("content", content);
            messages.add(entry);
        }
        if (messages.isEmpty() || !"user".equals(messages.get(messages.size() - 1).get("role"))) {
            throw ServiceException.badRequest("INVALID_MESSAGES",
                    "The last message must be from the user.");
        }

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("model", model);
        body.put("max_tokens", 1024);
        body.put("system", systemPrompt(caller));
        body.put("messages", messages);

        final HttpResponse<String> resp;
        try {
            String payload = mapper.writeValueAsString(body);
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(ANTHROPIC_URL))
                    .timeout(Duration.ofSeconds(45))
                    .header("x-api-key", apiKey)
                    .header("anthropic-version", "2023-06-01")
                    .header("content-type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(payload))
                    .build();
            resp = http.send(request, HttpResponse.BodyHandlers.ofString());
        } catch (Exception e) {
            throw new ServiceException(org.springframework.http.HttpStatus.BAD_GATEWAY,
                    "ASSISTANT_UNAVAILABLE", "The assistant couldn't respond right now. Please try again.");
        }

        if (resp.statusCode() / 100 != 2) {
            // Don't leak upstream internals.
            String msg = resp.statusCode() == 429
                    ? "The assistant is busy right now — please try again in a moment."
                    : "The assistant couldn't respond right now. Please try again.";
            throw new ServiceException(org.springframework.http.HttpStatus.BAD_GATEWAY,
                    "ASSISTANT_UNAVAILABLE", msg);
        }

        try {
            JsonNode root = mapper.readTree(resp.body());
            if ("refusal".equals(root.path("stop_reason").asText())) {
                return "I can't help with that one — I'm here for questions about using LogBook360.";
            }
            StringBuilder sb = new StringBuilder();
            for (JsonNode block : root.path("content")) {
                if ("text".equals(block.path("type").asText())) {
                    sb.append(block.path("text").asText());
                }
            }
            String reply = sb.toString().trim();
            return reply.isEmpty() ? "Sorry, I didn't catch that — could you rephrase?" : reply;
        } catch (Exception e) {
            throw new ServiceException(org.springframework.http.HttpStatus.BAD_GATEWAY,
                    "ASSISTANT_UNAVAILABLE", "The assistant couldn't respond right now. Please try again.");
        }
    }

    private String systemPrompt(AuthPrincipal caller) {
        String role = caller.role() == null ? "unknown" : caller.role();
        String name = caller.name() == null ? "" : (" Their name is " + caller.name() + ".");
        return "You are the in-app help assistant for LogBook360, embedded in the app. "
                + "The user's role is \"" + role + "\"." + name + "\n\n" + APP_OVERVIEW + "\n\n"
                + "Guidelines:\n"
                + "- Help the user understand and operate THIS app. Give short, concrete, step-by-step answers using the real screen/button names above.\n"
                + "- Tailor guidance to the user's role; if they ask about something only a higher role can do, say so.\n"
                + "- If you don't know an app-specific detail, say so plainly rather than inventing menus.\n"
                + "- Stay on-topic: you assist with using LogBook360. Politely decline unrelated requests.\n"
                + "- Be concise — a few sentences or a short numbered list. No preamble.";
    }
}
