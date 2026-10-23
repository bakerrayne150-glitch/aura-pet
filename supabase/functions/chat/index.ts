// Aura Pet — `chat` Edge Function (Supabase / Deno).
//
// Request:  { system: string, message: string }
// Response: { reply: string }
// Errors:   401 { error: "unauthenticated" }
//           400 { error: "invalid-argument" }
//           403 { error: "permission-denied" }   (no sub, trial expired)
//           429 { error: "resource-exhausted" }   (daily cap hit)
//           500 { error: "internal" }
//
// The LLM API key lives here, server-side. The app never sees it.
// Entitlement (subscription → 7-day trial → locked) and a daily message
// cap are enforced before a single token is spent.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";

const TRIAL_DAYS = 7;
const DAILY_MESSAGE_CAP = 100;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface Entitlement {
  unlocked: boolean;
  reason: "subscribed" | "trial" | "locked";
  trialDaysLeft: number;
}

async function getEntitlement(
  admin: ReturnType<typeof createClient>,
  uid: string,
): Promise<Entitlement> {
  const { data: profile } = await admin
    .from("profiles")
    .select("trial_start")
    .eq("id", uid)
    .maybeSingle();

  const { data: ent } = await admin
    .from("entitlements")
    .select("status, expiry_time_millis")
    .eq("user_id", uid)
    .maybeSingle();

  const now = Date.now();

  if (
    ent?.status === "active" &&
    typeof ent.expiry_time_millis === "number" &&
    ent.expiry_time_millis > now
  ) {
    return { unlocked: true, reason: "subscribed", trialDaysLeft: 0 };
  }

  const trialStart = profile?.trial_start
    ? new Date(profile.trial_start).getTime()
    : now; // first sighting fallback (trigger normally creates the row)
  const daysUsed = Math.floor((now - trialStart) / 86_400_000);
  const trialDaysLeft = Math.max(0, TRIAL_DAYS - daysUsed);
  if (trialDaysLeft > 0) {
    return { unlocked: true, reason: "trial", trialDaysLeft };
  }
  return { unlocked: false, reason: "locked", trialDaysLeft: 0 };
}

async function completeChat(system: string, message: string): Promise<string> {
  const url = Deno.env.get("LLM_API_URL");
  const key = Deno.env.get("LLM_API_KEY");
  const model = Deno.env.get("LLM_MODEL") ?? "gpt-4o-mini";

  if (!url || !key) {
    throw new Error("LLM_API_URL / LLM_API_KEY not configured");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: system },
          { role: "user", content: message },
        ],
        max_tokens: 300,
        temperature: 0.8,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(`LLM upstream ${res.status}: ${text.slice(0, 200)}`);
    }

    const data = (await res.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const reply = data.choices?.[0]?.message?.content?.trim();
    if (!reply) throw new Error("LLM returned no content");
    return reply;
  } finally {
    clearTimeout(timeout);
  }
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "invalid-argument" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // 1) Who's calling? Verify the user's JWT from the Authorization header.
  const authHeader = req.headers.get("Authorization") ?? "";
  const authed = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
  } = await authed.auth.getUser();
  if (!user) return json({ error: "unauthenticated" }, 401);

  // 2) Validate the payload.
  let payload: { system?: unknown; message?: unknown };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid-argument" }, 400);
  }
  const { system, message } = payload;
  if (
    typeof system !== "string" ||
    typeof message !== "string" ||
    message.trim().length === 0
  ) {
    return json({ error: "invalid-argument" }, 400);
  }
  if (message.length > 2000 || system.length > 4000) {
    return json({ error: "invalid-argument" }, 400);
  }

  // Service-role client: bypasses RLS for the billing tables.
  const admin = createClient(supabaseUrl, serviceKey);

  // 3) Entitlement: subscription → trial → locked.
  const entitlement = await getEntitlement(admin, user.id);
  if (!entitlement.unlocked) {
    return json({ error: "permission-denied" }, 403);
  }

  // 4) Daily cap — atomic check-and-increment in Postgres.
  const { data: allowed, error: capError } = await admin.rpc(
    "check_and_increment_usage",
    { p_user_id: user.id, p_cap: DAILY_MESSAGE_CAP },
  );
  if (capError || allowed !== true) {
    return json({ error: "resource-exhausted" }, 429);
  }

  // 5) Ask the LLM.
  try {
    const reply = await completeChat(system, message.trim());
    return json({ reply });
  } catch (e) {
    console.error("LLM call failed", e);
    return json({ error: "internal" }, 500);
  }
});
