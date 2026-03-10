// deno-lint-ignore-file
// Supabase Edge Function: Server-side proxy for Yeti WhatsApp API
// Handles two-step auth: API Key → JWT → Bearer token

interface YetiAuthResponse {
    access_token?: string;
    token?: string;
    jwt?: string;
    expires_in?: number;
}

interface SendRequest {
    phone: string;
    templateName: string;
    components?: unknown[];
}

// @ts-ignore Deno is available in Supabase Edge Functions
const _Deno = (globalThis as any).Deno;

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const YETI_API_KEY = _Deno.env.get("YETI_ACCESS_TOKEN") || "";
const YETI_PHONE_ID = _Deno.env.get("YETI_PHONE_NUMBER_ID") || "";
const YETI_WABA_ID = _Deno.env.get("YETI_WABA_ID") || "";
const YETI_API_URL = `https://crm.yeti.marketing/api/meta/v19.0/${YETI_PHONE_ID}/messages`;
const YETI_AUTH_URL = "https://crm.yeti.marketing/api/v2/auth/api-token";

// In-memory JWT cache (lives for the duration of the edge function instance)
let cachedJwt: string | null = null;
let jwtExpiresAt = 0;

async function getAccessToken(): Promise<string> {
    // Return cached token if still valid (with 60s buffer)
    if (cachedJwt && Date.now() < jwtExpiresAt - 60_000) {
        console.log("[Yeti Auth] Using cached JWT");
        return cachedJwt;
    }

    console.log("[Yeti Auth] Exchanging API key for JWT...");

    // Strategy 1: POST with x-yeti-apikey header
    const strategies = [
        {
            method: "POST" as const,
            headers: { "Content-Type": "application/json", "x-yeti-apikey": YETI_API_KEY },
            body: JSON.stringify({}),
        },
        {
            method: "POST" as const,
            headers: { "Content-Type": "application/json", "Authorization": `Bearer ${YETI_API_KEY}` },
            body: JSON.stringify({ api_key: YETI_API_KEY }),
        },
        {
            method: "POST" as const,
            headers: { "Content-Type": "application/json", "x-api-key": YETI_API_KEY },
            body: JSON.stringify({}),
        },
    ];

    for (const strategy of strategies) {
        try {
            const res = await fetch(YETI_AUTH_URL, strategy);
            const data = await res.json() as YetiAuthResponse;
            console.log(`[Yeti Auth] Strategy response (${res.status}):`, JSON.stringify(data).substring(0, 300));

            if (res.ok && (data.access_token || data.token || data.jwt)) {
                const token = data.access_token || data.token || data.jwt || "";
                cachedJwt = token;
                // Default: cache for 55 minutes
                jwtExpiresAt = Date.now() + (data.expires_in ? data.expires_in * 1000 : 55 * 60 * 1000);
                console.log("[Yeti Auth] JWT obtained successfully!");
                return token;
            }
        } catch (err) {
            console.warn("[Yeti Auth] Strategy failed:", (err as Error).message);
        }
    }

    // Fallback: use the API key directly as Bearer token (some Yeti setups allow this)
    console.warn("[Yeti Auth] Token exchange failed, falling back to API key as Bearer token");
    return YETI_API_KEY;
}

async function sendWhatsAppMessage(phone: string, templateName: string, components: unknown[]) {
    const cleanPhone = phone.replace(/\D/g, "");
    const accessToken = await getAccessToken();

    const payload = {
        messaging_product: "whatsapp",
        to: cleanPhone,
        type: "template",
        template: {
            name: templateName,
            language: { code: "en" },
            components,
        },
    };

    console.log(`[Yeti Send] Sending template "${templateName}" to ${cleanPhone}`);
    console.log(`[Yeti Send] URL: ${YETI_API_URL}`);
    console.log(`[Yeti Send] Payload:`, JSON.stringify(payload).substring(0, 500));

    // Try with Bearer token first
    const authHeaders = [
        { Authorization: `Bearer ${accessToken}` },
        { Authorization: accessToken }, // Without "Bearer" prefix
    ];

    for (const authHeader of authHeaders) {
        const res = await fetch(YETI_API_URL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                ...authHeader,
            },
            body: JSON.stringify(payload),
        });

        const data = await res.json();

        if (res.ok) {
            console.log("[Yeti Send] SUCCESS!", JSON.stringify(data));
            return { success: true, data };
        }

        console.warn(`[Yeti Send] Failed (${res.status}):`, JSON.stringify(data).substring(0, 500));

        // If 401, the token might be stale — clear cache and retry with next strategy
        if (res.status === 401) {
            cachedJwt = null;
            jwtExpiresAt = 0;
            continue;
        }

        // For non-401 errors, return the error immediately
        return { success: false, status: res.status, error: data };
    }

    return { success: false, error: "All authentication strategies failed" };
}

_Deno.serve(async (req: Request) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const { phone, templateName, components } = await req.json() as SendRequest;

        if (!phone || !templateName) {
            return new Response(
                JSON.stringify({ error: "Missing required fields: phone, templateName" }),
                { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
        }

        if (!YETI_API_KEY || !YETI_PHONE_ID) {
            return new Response(
                JSON.stringify({ error: "Yeti API not configured. Set YETI_ACCESS_TOKEN and YETI_PHONE_NUMBER_ID secrets." }),
                { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
        }

        const result = await sendWhatsAppMessage(phone, templateName, components || []);

        return new Response(JSON.stringify(result), {
            status: result.success ? 200 : 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });

    } catch (err) {
        console.error("[send-whatsapp] Error:", (err as Error).message);
        return new Response(
            JSON.stringify({ error: (err as Error).message }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
    }
});
