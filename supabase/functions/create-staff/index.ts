import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        // Verify the requester is a 'company' or 'admin'
        const authHeader = req.headers.get("Authorization");
        if (!authHeader) {
            return new Response(JSON.stringify({ error: "No authorization header" }), {
                status: 401,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        const { data: { user: requester }, error: authError } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
        if (authError || !requester) {
            return new Response(JSON.stringify({ error: "Invalid token" }), {
                status: 401,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        // Check requester role and company
        const { data: requesterProfile } = await supabase
            .from("users")
            .select("role, valet_company_id")
            .eq("id", requester.id)
            .single();

        if (!requesterProfile || (requesterProfile.role !== "company" && requesterProfile.role !== "admin")) {
            return new Response(JSON.stringify({ error: "Unauthorized: Insufficient permissions" }), {
                status: 403,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        const { email, password, name, role, company_id, location_id } = await req.json();

        // Ensure company owners can only create users for their own company
        if (requesterProfile.role === "company" && company_id !== requesterProfile.valet_company_id) {
            return new Response(JSON.stringify({ error: "Unauthorized: Cannot create users for other companies" }), {
                status: 403,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        // 1. Create the Auth User
        const { data: authUser, error: createError } = await supabase.auth.admin.createUser({
            email,
            password,
            email_confirm: true,
            user_metadata: { name },
        });

        if (createError) {
            return new Response(JSON.stringify({ error: createError.message }), {
                status: 400,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        // 2. Insert/Update the Profile in 'users' table
        // (Note: Auth triggers usually handle this, but explicit here ensures mapping)
        const { error: profileError } = await supabase
            .from("users")
            .upsert({
                id: authUser.user.id,
                email,
                name,
                role,
                valet_company_id: company_id,
                location_id: location_id || null,
            });

        if (profileError) {
            // Cleanup auth user if profile fails
            await supabase.auth.admin.deleteUser(authUser.user.id);
            return new Response(JSON.stringify({ error: profileError.message }), {
                status: 400,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        return new Response(JSON.stringify({ success: true, user: authUser.user }), {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }
});
