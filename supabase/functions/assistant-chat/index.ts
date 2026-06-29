import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// LogBook360 in-app help assistant. Proxies a short, app-aware chat to the
// Google Gemini API (free tier — key from https://aistudio.google.com, no card).
// The GEMINI_API_KEY lives ONLY here (a Supabase secret) — never in the browser.
// Every call is JWT-verified so this is not an open relay, and the conversation
// is bounded to keep cost/abuse in check.
//
// Set the secret before deploying:
//   supabase secrets set GEMINI_API_KEY=AIza...
//   (optional) supabase secrets set ASSISTANT_MODEL=gemini-2.0-flash

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models/";
const MAX_TURNS = 20;
const MAX_CHARS = 4000;

const APP_OVERVIEW = `LogBook360 (ValetBook360) is a multi-tenant valet-management platform.
Hierarchy: Super Admin → Company (owner) → Operator (valet) → Driver.
- Super Admin: manages every company, location, user, and sees all transactions.
- Company owner: manages their own company's locations, operators, drivers, contracts, and key slots.
- Operator (valet): checks cars in/out on the operator floor, assigns key slots and drivers.
- Driver: receives park/retrieve missions and advances them (assigned → en route → arrived → delivered).
Key features: vehicle Check-In, the operator floor/active cars, key-slot pools per location (numbered
1..capacity or custom names; the next free slot is auto-assigned and reused when a car leaves), driver
assignment, transactions history, team management (add/edit/delete operators & drivers, assign
locations), and per-company/location dashboards.`;

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
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      return json({ error: "The help assistant isn't configured yet. Set GEMINI_API_KEY." }, 503);
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

    // --- Validate + clamp the incoming conversation (Gemini roles: user|model) ---
    const body = await req.json().catch(() => null);
    const rawMessages = Array.isArray(body?.messages) ? body.messages : null;
    if (!rawMessages || rawMessages.length === 0) {
      return json({ error: "messages[] is required" }, 400);
    }
    const contents = rawMessages
      .slice(-MAX_TURNS)
      .filter((m: any) => (m?.role === "user" || m?.role === "assistant") && typeof m?.content === "string" && m.content.trim())
      .map((m: any) => ({
        role: m.role === "assistant" ? "model" : "user",
        parts: [{ text: String(m.content).slice(0, MAX_CHARS) }],
      }));
    if (contents.length === 0 || contents[contents.length - 1].role !== "user") {
      return json({ error: "The last message must be from the user." }, 400);
    }

    const model = Deno.env.get("ASSISTANT_MODEL") || "gemini-2.0-flash";

    const upstream = await fetch(
      `${GEMINI_BASE}${encodeURIComponent(model)}:generateContent`,
      {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: systemPrompt(role, name) }] },
          contents,
          generationConfig: { maxOutputTokens: 1024, temperature: 0.4 },
        }),
      },
    );

    if (!upstream.ok) {
      const detail = await upstream.text();
      console.error("Gemini error", upstream.status, detail);
      const msg = upstream.status === 429
        ? "The assistant is busy right now — please try again in a moment."
        : "The assistant couldn't respond right now. Please try again.";
      return json({ error: msg }, 502);
    }

    const data = await upstream.json();
    if (data?.promptFeedback?.blockReason) {
      return json({ reply: "I can't help with that one — I'm here for questions about using LogBook360." });
    }
    const cand = data?.candidates?.[0];
    const reply = Array.isArray(cand?.content?.parts)
      ? cand.content.parts.map((p: any) => p?.text ?? "").join("").trim()
      : "";
    if (!reply && cand?.finishReason === "SAFETY") {
      return json({ reply: "I can't help with that one — I'm here for questions about using LogBook360." });
    }
    return json({ reply: reply || "Sorry, I didn't catch that — could you rephrase?" });
  } catch (err) {
    console.error("assistant-chat error", err);
    return json({ error: "internal_error" }, 500);
  }
});
