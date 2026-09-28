// push-notify — sends an FCM push for every row inserted into
// public.notifications, whichever module wrote it.
//
// Called by the trg_push_notification trigger (migration 18) through
// pg_net with { notification_id, actor_id }. The audience, and each
// user's per-module opt-outs, are resolved in SQL by push_recipients().
//
// Secrets (supabase secrets set ...):
//   PUSH_WEBHOOK_SECRET        same value as vault secret push_webhook_secret
//   FIREBASE_SERVICE_ACCOUNT   the service-account JSON from Firebase console
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform.
//
// Deploy with --no-verify-jwt: the caller is the database, authenticated by
// the shared secret header rather than a user JWT.

import { createClient } from "npm:@supabase/supabase-js@2";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type NotificationRow = {
  id: string;
  title: string;
  body: string;
  type: string;
  entity_type: string | null;
  entity_id: string | null;
  route: string | null;
};

// Must match the Android channels the app creates (LocalPushService) and
// notification_module() in SQL.
function channelFor(type: string): string {
  if (type.startsWith("visitor")) return "visitor_gate";
  if (type.startsWith("complaint")) return "helpdesk";
  if (type === "notice") return "notices";
  if (type.startsWith("sos")) return "security";
  if (type.startsWith("join_request")) return "approvals";
  if (type.startsWith("parking")) return "parking";
  return "general";
}

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

Deno.serve(async (req) => {
  if (req.headers.get("x-push-secret") !== Deno.env.get("PUSH_WEBHOOK_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }

  let notificationId: string | undefined;
  let actorId: string | null = null;
  try {
    const body = await req.json();
    notificationId = body.notification_id;
    actorId = body.actor_id ?? null;
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }
  if (!notificationId) return json({ error: "notification_id required" }, 400);

  const { data: n, error: nErr } = await supabase
    .from("notifications")
    .select("id, title, body, type, entity_type, entity_id, route")
    .eq("id", notificationId)
    .maybeSingle<NotificationRow>();
  if (nErr) return json({ error: nErr.message }, 500);
  if (!n) return json({ sent: 0, reason: "notification not found" });

  const { data: recipients, error: rErr } = await supabase.rpc(
    "push_recipients",
    { p_notification_id: n.id, p_actor_id: actorId },
  );
  if (rErr) return json({ error: rErr.message }, 500);

  const tokens = [...new Set((recipients ?? []).map((r: { token: string }) => r.token))];
  if (!tokens.length) return json({ sent: 0, reason: "no recipients" });

  const sa: ServiceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
  const accessToken = await getAccessToken(sa);

  // One alert per entity: a later update to the same complaint or visitor
  // replaces the earlier one instead of piling up.
  const tag = n.entity_type && n.entity_id
    ? `${n.entity_type}_${n.entity_id}`
    : `notification_${n.id}`;
  const channel = channelFor(n.type);

  const results = await Promise.all(
    tokens.map((token) => sendFcm(sa.project_id, accessToken, token, n, tag, channel)),
  );

  // FCM tells us which tokens belong to uninstalled apps; drop them so the
  // table does not fill with dead devices.
  const dead = tokens.filter((_, i) => results[i] === "dead");
  if (dead.length) {
    await supabase.from("device_tokens").delete().in("token", dead);
  }

  return json({
    type: n.type,
    sent: results.filter((r) => r === "ok").length,
    failed: results.filter((r) => r === "error").length,
    removed: dead.length,
  });
});

async function sendFcm(
  projectId: string,
  accessToken: string,
  token: string,
  n: NotificationRow,
  tag: string,
  channel: string,
): Promise<"ok" | "dead" | "error"> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: n.title, body: n.body },
          // Read by the app on tap and when drawing foreground alerts.
          data: {
            route: n.route ?? "",
            tag,
            channel,
            type: n.type,
          },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: channel,
              tag,
              sound: "default",
              default_vibrate_timings: true,
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    },
  );

  if (res.ok) return "ok";
  const err = await res.text();
  console.error("FCM send failed", res.status, err);
  if (res.status === 404 || err.includes("UNREGISTERED")) return "dead";
  return "error";
}

// ── Google OAuth for the service account ──────────────────────────────

let cachedToken: { value: string; expiresAt: number } | null = null;

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.value;
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(new Uint8Array(signature))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`OAuth token failed: ${await res.text()}`);

  const data = await res.json();
  cachedToken = {
    value: data.access_token,
    expiresAt: Date.now() + data.expires_in * 1000,
  };
  return cachedToken.value;
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

function b64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
