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
 *   { "conversationId": UUID, "sessionId": UUID, "callType": "audio"|"video" }
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
import { RtcTokenBuilder, RtcRole } from "npm:agora-token@2.0.3";

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
    const conversationId: string = body.conversationId;
    const sessionId: string = body.sessionId;
    const callType: string = body.callType;
    // uid from the client. 0 means Agora auto-assigns.
    const uid: number = typeof body.uid === "number" ? body.uid : 0;

    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidPattern.test(conversationId ?? "") || !uuidPattern.test(sessionId ?? "") ||
        (callType !== "audio" && callType !== "video")) {
      return new Response(
        JSON.stringify({ error: "Valid conversationId, sessionId, and callType are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Tokens are issued only for an active participant of a direct chat. The
    // channel is constructed server-side, so a client cannot obtain a token
    // for an arbitrary Agora channel.
    const { data: participant, error: participantError } = await supabaseClient
      .from("conversation_participants")
      .select("conversation_id, conversations!inner(is_group)")
      .eq("conversation_id", conversationId)
      .eq("user_id", user.id)
      .eq("status", "active")
      .maybeSingle();
    if (participantError || !participant || (participant.conversations as { is_group: boolean }).is_group) {
      return new Response(
        JSON.stringify({ error: "Not authorized for this call" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const channelName = `call_${sessionId}`;

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
      RtcRole.PUBLISHER,
      tokenExpirySeconds,
      privilegeExpirySeconds,
    );

    console.log(`Token generated for session=${sessionId} type=${callType} user=${user.id}`);

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
