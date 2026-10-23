// Aura Pet — `verify-subscription` Edge Function (Supabase / Deno).
//
// The app completes a purchase with Play Billing, then calls this with the
// purchase token. We verify it against the Play Developer API and upsert
// the entitlement row. The app then calls
// AssistantService.refreshEntitlement() to pick it up.
//
// Request:  { packageName, productId, purchaseToken }
// Response: { active: boolean, expiryTimeMillis: number }
//
// Play auth is done with a service-account JWT signed in-process
// (WebCrypto RS256) — no googleapis dependency needed on the edge.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToBytes(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** OAuth2 access token for the Play Developer API via service-account JWT. */
async function playAccessToken(
  clientEmail: string,
  privateKeyPem: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claims = b64url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: clientEmail,
        scope: "https://www.googleapis.com/auth/androidpublisher",
        aud: "https://oauth2.googleapis.com/token",
        exp: now + 3600,
        iat: now,
      }),
    ),
  );
  const signingInput = new TextEncoder().encode(`${header}.${claims}`);
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, signingInput));
  const assertion = `${header}.${claims}.${b64url(signature)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) {
    throw new Error(`Play OAuth failed: ${res.status}`);
  }
  const data = (await res.json()) as { access_token?: string };
  if (!data.access_token) throw new Error("Play OAuth returned no token");
  return data.access_token;
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "invalid-argument" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization") ?? "";
  const authed = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
  } = await authed.auth.getUser();
  if (!user) return json({ error: "unauthenticated" }, 401);

  let payload: {
    packageName?: unknown;
    productId?: unknown;
    purchaseToken?: unknown;
  };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid-argument" }, 400);
  }
  const { packageName, productId, purchaseToken } = payload;
  if (
    typeof packageName !== "string" ||
    typeof productId !== "string" ||
    typeof purchaseToken !== "string" ||
    !packageName ||
    !productId ||
    !purchaseToken
  ) {
    return json({ error: "invalid-argument" }, 400);
  }

  const svcJson = Deno.env.get("PLAY_SERVICE_ACCOUNT");
  if (!svcJson) return json({ error: "failed-precondition" }, 412);
  const svc = JSON.parse(svcJson) as {
    client_email: string;
    private_key: string;
  };

  let accessToken: string;
  try {
    accessToken = await playAccessToken(svc.client_email, svc.private_key);
  } catch (e) {
    console.error("Play auth failed", e);
    return json({ error: "internal" }, 500);
  }

  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/` +
    encodeURIComponent(purchaseToken);
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    return json({ error: "invalid-argument" }, 400); // Play can't verify it
  }
  const info = (await res.json()) as {
    subscriptionState?: string;
    lineItems?: Array<{ expiryTime?: string; autoRenewingPlan?: unknown }>;
  };

  const lineItem = info.lineItems?.[0];
  const expiryTimeMillis = Number(lineItem?.expiryTime ?? 0);
  const active =
    info.subscriptionState === "SUBSCRIPTION_STATE_ACTIVE" &&
    expiryTimeMillis > Date.now();

  const admin = createClient(supabaseUrl, serviceKey);
  const { error: upsertError } = await admin.from("entitlements").upsert(
    {
      user_id: user.id,
      status: active ? "active" : "inactive",
      product_id: productId,
      expiry_time_millis: expiryTimeMillis,
      auto_renewing: lineItem?.autoRenewingPlan != null,
      verified_at: new Date().toISOString(),
    },
    { onConflict: "user_id" },
  );
  if (upsertError) {
    console.error("Entitlement upsert failed", upsertError);
    return json({ error: "internal" }, 500);
  }

  return json({ active, expiryTimeMillis });
});
