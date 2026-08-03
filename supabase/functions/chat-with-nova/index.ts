import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const geminiUrl =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:streamGenerateContent?alt=sse";

const systemInstruction = `You are Nova, a friendly and helpful AI assistant built into a chat app.
Be warm, concise, and conversational. Help with questions, ideas, writing, math, coding, and everyday tasks.
Use short paragraphs and natural language suited to a mobile chat. Never claim to be human.`;

function response(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405);

  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      console.error("GEMINI_API_KEY is not configured");
      return response({ error: "AI service is not configured." }, 503);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return response({ error: "Missing authorization" }, 401);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) return response({ error: "Unauthorized" }, 401);

    const body = await req.json();
    const message = typeof body.message === "string" ? body.message.trim() : "";
    if (!message) return response({ error: "Message cannot be empty." }, 400);
    if (message.length > 8000) {
      return response({ error: "Messages must be 8,000 characters or fewer." }, 400);
    }

    // Context comes from the authenticated user's own database history, rather
    // than from the device. This preserves privacy and prevents prompt/history
    // spoofing by a modified client.
    const { data: recentMessages, error: historyError } = await supabase
      .from("ai_messages")
      .select("role, content")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(12);
    if (historyError) throw historyError;

    const history = [...(recentMessages ?? [])].reverse().map((item) => ({
      role: item.role === "assistant" ? "model" : "user",
      parts: [{ text: item.content }],
    }));

    const geminiRes = await fetch(geminiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: systemInstruction }] },
        contents: [...history, { role: "user", parts: [{ text: message }] }],
        generationConfig: { maxOutputTokens: 1024, temperature: 0.7 },
      }),
    });

    if (!geminiRes.ok) {
      console.error("Gemini request failed", geminiRes.status, await geminiRes.text());
      return response({ error: "AI service is unavailable. Please try again." }, 502);
    }

    if (!geminiRes.body) throw new Error("Gemini returned an empty response stream.");

    // Forward each Gemini chunk immediately so the app can render the answer
    // as it is generated, then save the complete exchange when it finishes.
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const reader = geminiRes.body.getReader();
    let reply = "";
    let pending = "";

    const stream = new ReadableStream<Uint8Array>({
      async start(controller) {
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            pending += decoder.decode(value, { stream: true });
            const lines = pending.split("\n");
            pending = lines.pop() ?? "";

            for (const line of lines) {
              if (!line.startsWith("data: ")) continue;
              const event = JSON.parse(line.substring(6));
              const text = event?.candidates?.[0]?.content?.parts
                ?.map((part: { text?: string }) => part.text ?? "")
                .join("") ?? "";
              if (text.isEmpty) continue;
              reply += text;
              controller.enqueue(encoder.encode(`data: ${JSON.stringify({ text })}\n\n`));
            }
          }

          reply = reply.trim();
          if (!reply) throw new Error("Nova returned an empty reply.");
          const { error: saveError } = await supabase.from("ai_messages").insert([
            { user_id: user.id, role: "user", content: message },
            { user_id: user.id, role: "assistant", content: reply },
          ]);
          if (saveError) throw saveError;
          controller.enqueue(encoder.encode("event: done\ndata: {}\n\n"));
        } catch (error) {
          console.error("Nova streaming failed", error);
          controller.enqueue(encoder.encode(`event: error\ndata: ${JSON.stringify({ error: "Nova could not finish that response. Please try again." })}\n\n`));
        } finally {
          reader.releaseLock();
          controller.close();
        }
      },
    });

    return new Response(stream, {
      headers: {
        ...corsHeaders,
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
      },
    });
  } catch (error) {
    console.error("chat-with-nova failed", error);
    return response({ error: "Unable to send your message right now." }, 500);
  }
});
