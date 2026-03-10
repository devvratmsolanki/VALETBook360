import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const YETI_WABA_ID = Deno.env.get("YETI_WABA_ID");
const YETI_PHONE_ID = Deno.env.get("YETI_PHONE_NUMBER_ID");
const YETI_API_URL = Deno.env.get("YETI_API_URL") || `https://crm.yeti.marketing/api/meta/v19.0/${YETI_PHONE_ID}/messages`;
const YETI_ACCESS_TOKEN = Deno.env.get("YETI_ACCESS_TOKEN");

Deno.serve(async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

    try {
        const body = await req.json();
        console.log("Webhook received:", JSON.stringify(body, null, 2));

        // 1. Extract sender and text from Yeti/Meta webhook
        // Meta standard: entry[0].changes[0].value.messages[0]
        const message = body.entry?.[0]?.changes?.[0]?.value?.messages?.[0];

        const sender = (
            body.sender ||
            body.from ||
            message?.from ||
            ""
        ).toString();

        const text = (
            body.text ||
            message?.button?.text ||
            message?.interactive?.button_reply?.title ||
            message?.text?.body ||
            ""
        ).toString().toLowerCase();

        console.log(`Extracted: sender=${sender}, text="${text}"`);

        // Check if this is the "Get my car back" request
        if (!sender || !text.includes("get my car back")) {
            console.log("Skipping message: Not a 'get my car back' request.");
            return new Response(JSON.stringify({ skip: true, reason: "ignoring_message" }), {
                status: 200,
                headers: { ...corsHeaders, "Content-Type": "application/json" }
            });
        }

        const supabase = createClient(
            Deno.env.get("SUPABASE_URL")!,
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
        );

        // 2. Find the visitor by phone
        const cleanPhone = sender.replace(/\D/g, "");
        console.log(`Searching for visitor with phone: ${cleanPhone}`);

        const { data: visitor, error: vError } = await supabase
            .from("visitors")
            .select("id, name, phone")
            .or(`phone.eq.+${cleanPhone},phone.eq.${cleanPhone}`)
            .limit(1)
            .maybeSingle();

        if (vError) throw vError;
        if (!visitor) {
            console.warn(`Visitor not found for phone: ${sender}`);
            // Return 200 to acknowledge receipt to Meta, but log failure
            return new Response(JSON.stringify({ success: false, error: "visitor_not_found" }), {
                status: 200,
                headers: { ...corsHeaders, "Content-Type": "application/json" }
            });
        }

        // 2. Find latest parked transaction
        console.log(`Searching for parked transaction for visitor: ${visitor.id}`);
        const { data: tx, error: txError } = await supabase
            .from("valet_transactions")
            .select("id, car_id, cars(car_number)")
            .eq("visitor_id", visitor.id)
            .eq("status", "parked")
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();

        if (txError) throw txError;
        if (!tx) {
            console.warn(`No parked car found for visitor: ${visitor.id}`);
            return new Response(JSON.stringify({ success: false, error: "no_parked_car" }), {
                status: 200,
                headers: { ...corsHeaders, "Content-Type": "application/json" }
            });
        }

        // 3. Update status to requested
        const now = new Date().toISOString();
        const { error: updateError } = await supabase
            .from("valet_transactions")
            .update({
                status: "requested",
                requested_at: now,
                updated_at: now
            })
            .eq("id", tx.id);

        if (updateError) throw updateError;
        console.log(`Updated transaction ${tx.id} status to 'requested'`);

        // 4. Send confirmation back via Yeti (two-step auth: API key → JWT → Bearer)
        if (YETI_ACCESS_TOKEN) {
            console.log(`Sending confirmation template to ${cleanPhone}`);

            // Step 1: Exchange API key for JWT
            let accessToken = YETI_ACCESS_TOKEN;
            try {
                const authRes = await fetch("https://crm.yeti.marketing/api/v2/auth/api-token", {
                    method: "POST",
                    headers: { "Content-Type": "application/json", "x-yeti-apikey": YETI_ACCESS_TOKEN },
                    body: JSON.stringify({})
                });
                const authData = await authRes.json() as { access_token?: string; token?: string };
                if (authRes.ok && (authData.access_token || authData.token)) {
                    accessToken = authData.access_token || authData.token || YETI_ACCESS_TOKEN;
                    console.log("JWT obtained for confirmation message");
                } else {
                    console.warn("Token exchange failed, using API key directly:", JSON.stringify(authData));
                }
            } catch (authErr) {
                console.warn("Token exchange error:", (authErr as Error).message);
            }

            // Step 2: Send template with Bearer JWT
            const response = await fetch(YETI_API_URL, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${accessToken}`
                },
                body: JSON.stringify({
                    messaging_product: "whatsapp",
                    to: cleanPhone,
                    type: "template",
                    template: {
                        name: "received_request_notification",
                        language: { code: "en" },
                        components: [
                            {
                                type: "body",
                                parameters: [{ type: "text", text: tx.cars?.car_number || "your car" }]
                            }
                        ]
                    }
                })
            });

            if (!response.ok) {
                const errorData = await response.json();
                console.error("Yeti API delivery failed:", JSON.stringify(errorData));
            } else {
                console.log("Confirmation message sent via Yeti");
            }
        } else {
            console.warn("YETI_ACCESS_TOKEN not found, skipping confirmation message");
        }

        return new Response(JSON.stringify({ success: true }), {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" }
        });

    } catch (err) {
        console.error("Webhook processing error:", err.message);
        return new Response(JSON.stringify({ error: err.message }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" }
        });
    }
});
