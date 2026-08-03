/**
 * Supabase Edge Function: generate-agora-token
 *
 * Generates a signed Agora RTC token for a given channel.
 * Called by the Flutter app before joining an Agora channel.
 *
 * Required Supabase Secrets (set via CLI or dashboard):
 *   AGORA_APP_ID          — Your Agora App ID
 *   AGORA_APP_CERTIFICATE — Your Agora Primary App Certificate (keep secret!)
 *
 * Request body (JSON):
 *   { "channelName": string, "uid": number }
 *
 * Response (JSON):
 *   { "token": string, "uid": number, "appId": string }
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// Use Agora's maintained token builder rather than a local binary-token
// implementation. A token with an invalid AccessToken2 payload is rejected by
// Agora during joinChannel, which used to end the caller's setup before the
// recipient was notified.
import { RtcTokenBuilder, Role } from "npm:agora-token@2.0.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Authenticate the caller ──────────────────────────────────────────
    // Only authenticated Supabase users can generate tokens
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── 2. Parse request body ───────────────────────────────────────────────
    const body = await req.json();
    const channelName: string = body.channelName;
    // uid from the client. 0 means Agora auto-assigns.
    const uid: number = typeof body.uid === "number" ? body.uid : 0;

    if (!channelName || typeof channelName !== "string") {
      return new Response(
        JSON.stringify({ error: "channelName is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── 3. Load Agora credentials from environment (Supabase Secrets) ────────
    const appId = Deno.env.get("AGORA_APP_ID");
    const appCertificate = Deno.env.get("AGORA_APP_CERTIFICATE");

    if (!appId || !appCertificate) {
      console.error("AGORA_APP_ID or AGORA_APP_CERTIFICATE secret not set");
      return new Response(
        JSON.stringify({ error: "Agora credentials not configured on server" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── 4. Generate the token ───────────────────────────────────────────────
    const tokenExpirySeconds = 3600;      // Token valid for 1 hour
    const privilegeExpirySeconds = 3600; // Privileges valid for 1 hour

    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelName,
      uid,
      Role.PUBLISHER,
      tokenExpirySeconds,
      privilegeExpirySeconds,
    );

    console.log(`Token generated for channel=${channelName} uid=${uid} user=${user.id}`);

    // ── 5. Return token to client ───────────────────────────────────────────
    return new Response(
      JSON.stringify({ token, uid, appId }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("generate-agora-token error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error", detail: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
