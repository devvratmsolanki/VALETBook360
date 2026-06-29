import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// LogBook360 in-app help assistant. Proxies a short, app-aware chat to the
// Anthropic Messages API. The ANTHROPIC_API_KEY lives ONLY here (a Supabase
// secret) — it is never shipped to the browser. Every call is JWT-verified so
// this is not an open relay, and the conversation is bounded to keep cost and
// abuse in check.
//
// Set the secret before deploying:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   (optional) supabase secrets set ASSISTANT_MODEL=claude-opus-4-8
//
// claude-opus-4-8 is the default per Anthropic guidance; for a high-volume help
// bot you can switch to a cheaper tier with ASSISTANT_MODEL=claude-haiku-4-5.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const MAX_TURNS = 20; // cap conversation length sent upstream
const MAX_CHARS = 4000; // per-message clamp

// Role-scoped product knowledge so answers are concrete and grounded in THIS app.
const APP_OVERVIEW = `LogBook360 (ValetBook360) is a multi-tenant valet-management platform.
Hierarchy: Super Admin → Company (owner) → Operator (valet) → Driver.
- Super Admin: manages every company, location, user, and sees all transactions.
- Company owner: manages their own company's locations, operators, drivers, contracts, and key slots.
- Operator (valet): checks cars in/out on the operator floor, assigns key slots and drivers.
- Driver: receives park/retrieve missions and advances them (assigned → en route → arrived → delivered).
Key features: vehicle Check-In (guest, car, location, driver, auto-assigned key slot), the operator
floor/active cars, key-slot pools per location (numbered 1..capacity or custom names like A,B,C; the
next free slot is auto-assigned and reused when a car leaves), driver assignment, transactions history,
team management (add/edit operators & drivers, assign locations), and per-company/location dashboards.`;

function systemPrompt(role: string, name: string | null): string {
  const who = role ? `The user's role is "${role}".` : "The user's role is unknown.";
  return `You are the in-app help assistant for LogBook360, embedded in the web app. ${who}${
    name ? ` Their name is ${name}.` : ""
  }

${APP_OVERVIEW}

Guidelines:
- Help the user understand and operate THIS app. Give short, concrete, step-by-step answers (use the real screen/button names above).
- Tailor guidance to the user's role; if they ask about something only a higher role can do, say so and who to contact.
- If you don't know an app-specific detail, say so plainly rather than inventing menus or buttons.
- Stay on-topic: you assist with using LogBook360. Politely decline unrelated requests.
- Be concise — a few sentences or a short numbered list. No preamble like "Sure!" or "Great question".`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  try {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return json({ error: "The help assistant isn't configured yet. Set ANTHROPIC_API_KEY." }, 503);
    }

    // --- AuthN: require a valid Supabase session (any authenticated role) ---
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "No authorization header" }, 401);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );
    if (authError || !user) return json({ error: "Invalid token" }, 401);

    // Derive the role server-side from the DB — never trust a client-supplied role.
    const { data: profile } = await supabase
      .from("users")
      .select("role, name")
      .eq("id", user.id)
      .single();
    const role = profile?.role ?? "";
    const name = profile?.name ?? null;

    // --- Validate + clamp the incoming conversation ---
    const body = await req.json().catch(() => null);
    const rawMessages = Array.isArray(body?.messages) ? body.messages : null;
    if (!rawMessages || rawMessages.length === 0) {
      return json({ error: "messages[] is required" }, 400);
    }
    const messages = rawMessages
      .slice(-MAX_TURNS)
      .filter((m: any) => (m?.role === "user" || m?.role === "assistant") && typeof m?.content === "string" && m.content.trim())
      .map((m: any) => ({ role: m.role, content: String(m.content).slice(0, MAX_CHARS) }));
    if (messages.length === 0) return json({ error: "No valid messages" }, 400);
    if (messages[messages.length - 1].role !== "user") {
      return json({ error: "The last message must be from the user." }, 400);
    }

    const model = Deno.env.get("ASSISTANT_MODEL") || "claude-opus-4-8";

    const upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        max_tokens: 1024,
        system: systemPrompt(role, name),
        messages,
      }),
    });

    if (!upstream.ok) {
      const detail = await upstream.text();
      console.error("Anthropic error", upstream.status, detail);
      // Don't leak upstream internals to the client.
      const msg = upstream.status === 429
        ? "The assistant is busy right now — please try again in a moment."
        : "The assistant couldn't respond right now. Please try again.";
      return json({ error: msg }, 502);
    }

    const data = await upstream.json();
    // Guard the refusal stop reason before reading content.
    if (data?.stop_reason === "refusal") {
      return json({ reply: "I can't help with that one — I'm here for questions about using LogBook360." });
    }
    const reply = Array.isArray(data?.content)
      ? data.content.filter((b: any) => b?.type === "text").map((b: any) => b.text).join("\n").trim()
      : "";
    return json({ reply: reply || "Sorry, I didn't catch that — could you rephrase?" });
  } catch (err) {
    console.error("assistant-chat error", err);
    return json({ error: "internal_error" }, 500);
  }
});
