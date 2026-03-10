import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Allow POST and GET (GET is needed for WhatsApp button URLs)
  if (req.method !== "POST" && req.method !== "GET") {
    return new Response(
      JSON.stringify({ success: false, message: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    let car_number: string | null = null;

    if (req.method === "GET") {
      const url = new URL(req.url);
      car_number = url.searchParams.get("car_number");
    } else {
      const body = await req.json();
      car_number = body.car_number;
    }

    if (!car_number || typeof car_number !== "string" || car_number.trim() === "") {
      return new Response(
        JSON.stringify({
          success: false,
          message: "Missing or invalid 'car_number' parameter",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client using the service role key (set in Edge Function secrets)
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Step 1: Find the car by car_number
    const { data: car, error: carError } = await supabase
      .from("cars")
      .select("id, car_number")
      .eq("car_number", car_number.trim().toUpperCase())
      .maybeSingle();

    if (carError) {
      console.error("Error looking up car:", carError);
      return new Response(
        JSON.stringify({ success: false, message: "Error looking up car" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!car) {
      return new Response(
        JSON.stringify({
          success: false,
          message: `No car found with number: ${car_number}`,
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Step 2: Find the latest parked transaction for this car
    const { data: transaction, error: txError } = await supabase
      .from("valet_transactions")
      .select("id, status, car_id")
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
        JSON.stringify({
          success: false,
          message: `No active parked transaction found for car: ${car_number}`,
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
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
