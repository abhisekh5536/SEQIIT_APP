// push-visitor — sends FCM notifications for visitor gate events.
//
// Called by the trg_push_visitor_change trigger (migration 17) through
// pg_net. Resolves who should hear about the change, looks up their device
// tokens and sends through the FCM HTTP v1 API.
//
//   INSERT pending_approval          -> active residents of the flat
//   pending_approval -> approved/denied -> the guard/admin who logged it
//
// Secrets (supabase secrets set ...):
//   PUSH_WEBHOOK_SECRET        same value as vault secret push_webhook_secret
//   FIREBASE_SERVICE_ACCOUNT   the service-account JSON from Firebase console
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform.
//
// Deploy with --no-verify-jwt: the caller is the database, authenticated by
// the shared secret header rather than a user JWT.

import { createClient } from "npm:@supabase/supabase-js@2";

type VisitorRow = {
  id: string;
  flat_id: string;
  created_by: string;
  visitor_name: string;
  category: string | null;
  status: string;
  denied_reason: string | null;
};

type Payload = {
  type: "INSERT" | "UPDATE";
  record: VisitorRow;
  old_record: VisitorRow | null;
};

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

Deno.serve(async (req) => {
  if (req.headers.get("x-push-secret") !== Deno.env.get("PUSH_WEBHOOK_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }

  const message = await buildMessage(payload);
  if (!message) return json({ sent: 0, reason: "not a push event" });

  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("token")
    .in("user_id", message.userIds);
  if (error) return json({ error: error.message }, 500);
  if (!tokens?.length) return json({ sent: 0, reason: "no devices" });

  const sa: ServiceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
  const accessToken = await getAccessToken(sa);

  const results = await Promise.all(
    tokens.map(({ token }) => sendFcm(sa.project_id, accessToken, token, message)),
  );

  // FCM tells us which tokens belong to uninstalled apps; drop them so the
  // table does not fill with dead devices.
  const dead = tokens.filter((_, i) => results[i] === "dead").map((t) => t.token);
  if (dead.length) {
    await supabase.from("device_tokens").delete().in("token", dead);
  }

  return json({
    sent: results.filter((r) => r === "ok").length,
    failed: results.filter((r) => r === "error").length,
    removed: dead.length,
  });
});

type Message = {
  userIds: string[];
  title: string;
  body: string;
  tag: string;
};

async function buildMessage(p: Payload): Promise<Message | null> {
  const v = p.record;
  if (!v?.id) return null;
  const tag = `visitor_${v.id}`;

  if (p.type === "INSERT" && v.status === "pending_approval") {
    const { data: residents } = await supabase
      .from("residents")
      .select("user_id")
      .eq("flat_id", v.flat_id)
      .eq("status", "active")
      .not("user_id", "is", null);

    const userIds = [...new Set((residents ?? []).map((r) => r.user_id as string))]
      // The person who logged it does not need to be told.
      .filter((id) => id !== v.created_by);
    if (!userIds.length) return null;

    return {
      userIds,
      title: `🚪 Visitor at Gate: ${v.visitor_name}`,
      body: `${label(v.category ?? "guest")} · Tap to approve or deny`,
      tag,
    };
  }

  if (
    p.type === "UPDATE" &&
    p.old_record?.status === "pending_approval" &&
    (v.status === "approved" || v.status === "denied")
  ) {
    const { data: flat } = await supabase
      .from("flats")
      .select("flat_number")
      .eq("id", v.flat_id)
      .maybeSingle();
    const flatText = flat?.flat_number ? ` · Flat ${flat.flat_number}` : "";
    const approved = v.status === "approved";

    return {
      userIds: [v.created_by],
      title: approved
        ? `✅ Visitor Approved: ${v.visitor_name}`
        : `❌ Visitor Denied: ${v.visitor_name}`,
      body: !approved && v.denied_reason
        ? `${v.denied_reason}${flatText}`
        : `Resident responded${flatText}`,
      tag,
    };
  }

  return null;
}

async function sendFcm(
  projectId: string,
  accessToken: string,
  token: string,
  m: Message,
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
          notification: { title: m.title, body: m.body },
          // The app reads these when the alert is tapped, and uses the tag
          // to replace rather than duplicate its own realtime alert.
          data: { route: "/visitors", tag: m.tag },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "visitor_gate",
              tag: m.tag,
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

function label(category: string): string {
  return category
    .split("_")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
