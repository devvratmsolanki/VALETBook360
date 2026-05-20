import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Plate validation. Reject anything that doesn't look like a plate to deter
// automated enumeration. 4–12 alphanumeric chars only.
const PLATE_RE = /^[A-Z0-9]{4,12}$/;

// Token verification: a per-transaction guest token must be supplied alongside
// the car_number. Operators generate this when creating the transaction and
// embed it in the QR code URL. Without the token the endpoint refuses to
// transition any car — preventing plate enumeration attacks.
const REQUIRE_TOKEN = Deno.env.get("REQUEST_CAR_REQUIRE_TOKEN") !== "false";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST" && req.method !== "GET") {
    return new Response(
      JSON.stringify({ success: false, message: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    let car_number: string | null = null;
    let token: string | null = null;

    if (req.method === "GET") {
      const url = new URL(req.url);
      car_number = url.searchParams.get("car_number");
      token = url.searchParams.get("token");
    } else {
      const body = await req.json();
      car_number = body.car_number;
      token = body.token || null;
    }

    if (!car_number || typeof car_number !== "string") {
      return new Response(
        JSON.stringify({ success: false, message: "Missing 'car_number'" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const normalizedCar = car_number.trim().toUpperCase();
    if (!PLATE_RE.test(normalizedCar)) {
      return new Response(
        JSON.stringify({ success: false, message: "Invalid car_number format" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { data: car, error: carError } = await supabase
      .from("cars")
      .select("id, car_number")
      .eq("car_number", normalizedCar)
      .maybeSingle();

    if (carError) {
      console.error("Error looking up car:", carError);
      return new Response(
        JSON.stringify({ success: false, message: "Error looking up car" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!car) {
      // Use a generic message so external callers can't enumerate which
      // plates exist by comparing 404 vs 200 responses.
      return new Response(
        JSON.stringify({ success: false, message: "No active parked car matches" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: transaction, error: txError } = await supabase
      .from("valet_transactions")
      .select("id, status, car_id, guest_request_token")
      .eq("car_id", car.id)
      .eq("status", "parked")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (txError) {
      console.error("Error looking up transaction:", txError);
      return new Response(
        JSON.stringify({ success: false, message: "Error looking up transaction" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!transaction) {
      return new Response(
        JSON.stringify({ success: false, message: "No active parked car matches" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Token check. If the transaction has a token set, the caller must
    // present it; if REQUIRE_TOKEN is on globally, every transaction is
    // required to have one. This blocks plate-enumeration attacks.
    if (transaction.guest_request_token) {
      if (!token || token !== transaction.guest_request_token) {
        return new Response(
          JSON.stringify({ success: false, message: "Invalid or missing token" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    } else if (REQUIRE_TOKEN) {
      return new Response(
        JSON.stringify({ success: false, message: "Token required for this car" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Step 3: Update the transaction status to "requested"
    const now = new Date().toISOString();
    const { data: updated, error: updateError } = await supabase
      .from("valet_transactions")
      .update({
        status: "requested",
        requested_at: now,
        updated_at: now,
      })
      .eq("id", transaction.id)
      .select()
      .single();

    if (updateError) {
      console.error("Error updating transaction:", updateError);
      return new Response(
        JSON.stringify({ success: false, message: "Error updating transaction status" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Success!
    return new Response(
      JSON.stringify({
        success: true,
        message: "Car request submitted successfully",
        transaction_id: updated.id,
        car_number: car.car_number,
        status: updated.status,
        requested_at: updated.requested_at,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(
      JSON.stringify({ success: false, message: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
