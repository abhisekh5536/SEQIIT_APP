// purge-resident-documents — deletes resident document files that are no
// longer needed, and the PANs and log rows whose time is up.
//
// Called nightly by pg_cron -> public.invoke_document_purge() (migration
// 20) through pg_net. What is due is decided in SQL:
//   documents_due_for_purge()   retention passed (12 months after
//                               move-out), rejected / withdrawn /
//                               abandoned, or stuck uploading > 24 h
//   mark_documents_purged()     only after the files are really gone
//   purge_expired_identities()  PANs past their retention date
//   prune_document_access_log() log rows older than 2 years
//   document_orphan_objects()   files no document points at
//
// Files must be deleted through the Storage API: deleting storage.objects
// rows in SQL is blocked and would not remove the file anyway.
//
// Secrets (supabase secrets set ...):
//   PURGE_WEBHOOK_SECRET   same value as vault secret documents_purge_secret
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform.
//
// Deploy with --no-verify-jwt: the caller is the database, authenticated by
// the shared secret header rather than a user JWT.

import { createClient } from "npm:@supabase/supabase-js@2";

const BUCKET = "resident-documents";
const BATCH = 200;
// Keeps one run inside the Edge Function time limit; whatever is left is
// picked up the next night.
const MAX_BATCHES = 10;
const REMOVE_CHUNK = 100;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

// Compares without leaking, through timing, how much of the secret matched.
function sameSecret(given: string | null, expected: string | undefined): boolean {
  if (!given || !expected) return false;
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

async function removePaths(paths: string[]): Promise<void> {
  for (let i = 0; i < paths.length; i += REMOVE_CHUNK) {
    const { error } = await supabase.storage
      .from(BUCKET)
      .remove(paths.slice(i, i + REMOVE_CHUNK));
    if (error) throw new Error(`remove: ${error.message}`);
  }
}

type DueRow = { document_id: string; storage_path: string | null };

async function purge() {
  const result = { documents: 0, skipped: 0, identities: 0, logRows: 0, orphans: 0 };

  for (let batch = 0; batch < MAX_BATCHES; batch++) {
    const { data, error } = await supabase.rpc("documents_due_for_purge", {
      p_limit: BATCH,
    });
    if (error) throw new Error(`documents_due_for_purge: ${error.message}`);

    const rows = (data ?? []) as DueRow[];
    if (!rows.length) break;

    const ids = [...new Set(rows.map((r) => r.document_id))];
    const paths = rows
      .map((r) => r.storage_path)
      .filter((p): p is string => !!p);

    if (paths.length) await removePaths(paths);

    const { data: marked, error: markErr } = await supabase.rpc(
      "mark_documents_purged",
      { p_ids: ids },
    );
    if (markErr) throw new Error(`mark_documents_purged: ${markErr.message}`);

    result.documents += marked?.purged ?? 0;
    result.skipped += marked?.skipped ?? 0;

    // Nothing moved this round: the rest would only repeat the same rows.
    if ((marked?.purged ?? 0) === 0) break;
    if (ids.length < BATCH) break;
  }

  const { data: identities, error: idErr } = await supabase.rpc(
    "purge_expired_identities",
  );
  if (idErr) throw new Error(`purge_expired_identities: ${idErr.message}`);
  result.identities = identities ?? 0;

  const { data: logRows, error: logErr } = await supabase.rpc(
    "prune_document_access_log",
  );
  if (logErr) throw new Error(`prune_document_access_log: ${logErr.message}`);
  result.logRows = logRows ?? 0;

  const { data: orphans, error: orphanErr } = await supabase.rpc(
    "document_orphan_objects",
    { p_limit: 500 },
  );
  if (orphanErr) throw new Error(`document_orphan_objects: ${orphanErr.message}`);
  const orphanPaths = ((orphans ?? []) as { storage_path: string }[])
    .map((o) => o.storage_path);
  if (orphanPaths.length) {
    await removePaths(orphanPaths);
    result.orphans = orphanPaths.length;
  }

  return result;
}

Deno.serve((req) => {
  if (!sameSecret(req.headers.get("x-purge-secret"), Deno.env.get("PURGE_WEBHOOK_SECRET"))) {
    return new Response("Unauthorized", { status: 401 });
  }

  // pg_net stops waiting long before a big purge finishes, so answer at
  // once and keep working in the background.
  const work = purge()
    .then((r) => console.log("purge-resident-documents", JSON.stringify(r)))
    .catch((e) => console.error("purge-resident-documents failed:", e));

  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(work);
    return new Response(JSON.stringify({ accepted: true }), {
      status: 202,
      headers: { "Content-Type": "application/json" },
    });
  }

  return work.then(
    () => new Response(JSON.stringify({ done: true }), {
      headers: { "Content-Type": "application/json" },
    }),
  );
});
