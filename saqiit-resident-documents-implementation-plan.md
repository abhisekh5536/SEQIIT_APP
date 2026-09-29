# Saqiit — Resident Documents (Tenant & Owner KYC): Implementation Plan

> **Status (30 Sep 2026): Phase 0 and Phase 1 are implemented.** See §10 for what shipped, how to deploy it, and what is still open. Phases 2–3 are not started.

## Context

The society office needs proof of who lives in each flat:
- **Tenants:** identity plus the rent agreement.
- **Owners of a sold flat:** the sale deed or similar document.

Today the app stores only `aadhar_last4`, `agreement_holder_name` and `agreement_date` on `residents`. There is no file storage for documents, and all four existing buckets are public.

You asked for the full Aadhaar number, the PAN number, a photo of the rent agreement, and a PDF or photo of the ownership document. After the research you chose to **not store the full Aadhaar number** (§1.2).

**On approval:**
1. Save this plan in the repo as `saqiit-resident-documents-implementation-plan.md`, next to the guard-panel and visitor plans.
2. Build Phase 0 and Phase 1.

### Decisions (from your answers)

| Question | Decision |
|---|---|
| Aadhaar | Keep only the last 4 digits (the existing `residents.aadhar_last4`). Optionally upload the UIDAI **masked Aadhaar**. The full 12 digits are never stored. |
| PAN | Full PAN, **encrypted** (pgcrypto, key in Supabase Vault). Shown masked (`••••••234F`). |
| Owner (landlord) | **Opens** the tenant's tenancy documents (rent agreement, police verification, NOC). For identity, sees only the **status plus last-4** of Aadhaar and PAN. The owner can't open the masked-Aadhaar file, because it still shows the tenant's photo, date of birth and address. Never sees the full PAN. |
| Retention | A tenant's or former owner's files and PAN are **deleted automatically 12 months after they move out**. The access log is kept for 2 years. |

---

## 0. Current state: what exists and what must be fixed first

| # | Finding | Where | Impact / fix |
|---|---|---|---|
| **P0-1** | `is_society_admin` lost `status = 'active'` | `11_vehicles_parking_module.sql:33-41` (the `01` version had it) | A deactivated admin passes every admin policy. Fix it in **20 and in 11** (re-running 11 would bring it back). The app also treats any `society_admin_users` row as admin (`app_session.dart:197`); check status there too. |
| **P0-2** | A household member's creator can rewrite **any column** of that row (`user_id`, `flat_id`, `society_id`, `created_by`). Inserts don't check that `society_id` matches the flat. | `04_profile_self_service.sql:123-152`, `03:57-66` | An owner who added their tenant can set `user_id` = themselves, becoming "self" for the tenant, and read the tenant's full PAN. A primary resident can also move a row they created into any flat in any society. Fix: `residents_before_write` trigger (§3.0). |
| 2 | `created_by` = the admin who approved the join request | `05_resident_join_requests.sql:170` | `created_by` can't mean "household head" in document access rules. Use it only for `family` rows, and only while the creator lives in the flat. |
| 3 | All 4 buckets are public, policies check only `bucket_id`, and the app uses only `getPublicUrl` + `Image.network` | `06:410`, `08:308`, `09:920`, `11:750` | A new private bucket, with authenticated `download()` into memory. No URLs. |
| 4 | Everyone in a flat can read every column of every flatmate's `residents` row | `04:107-114` | PAN and document paths go in separate tables, never on `residents`. |
| 5 | Primary residents **hard-delete** members | `profile_screen.dart:846-849` | Document foreign key `set null`, plus a SECURITY DEFINER BEFORE DELETE trigger that starts the retention clock. |
| 6 | No PDF picking or viewing; no `pg_cron` in use; `pg_net` + Vault + Edge Function pattern exists | `pubspec.yaml`, `17_push_notifications.sql:116-182` | Add `file_picker` + `pdfrx`. Copy the push pattern for the nightly purge. |
| 7 | Next free migration number is **20** (17 is used twice; 19 is facilities) | `supabase/` | `20_resident_documents.sql` |

---

## 1. Research summary

### 1.1 What comparable apps do

| App | Collects | Who sees | Workflow | Expiry |
|---|---|---|---|---|
| **MyGate** | Rental agreement and ID at sign-up. Its guide lists ownership proof, society NOC and police verification form. | "Flat documents": the flat's residents + admins with tenant permission. "Personal documents": only the uploader. | Admin approves or rejects. | Renewal reminders. Report by approved / rejected / expired. **Download needs OTP + reason.** |
| **NoBrokerHood** | Agreement, ID proof, police verification receipt | Owner + admin, with "masking controls" and OTP for downloads | **Owner approves the tenant**, then the admin | Alerts before expiry |
| **ApnaComplex** | Admin-configurable form (PAN, lease upload, rules checklist) | "Restricted" (admins only) or whole community | Tenant requests go to the approvers **and** the owner | – |
| **ADDA** | Unit documents, move-in form | Unit members + admins | Admin approvers | Tenancy expiry emails. 2026: consent manager, encrypted fields. |

**What they have in common:**
- Documents are scoped per flat.
- The owner is involved in tenant documents.
- Rent agreements are tracked by start and end date.
- Admins verify documents.

**Gaps in all of them:** Aadhaar masking, and deleting data after move-out. Saqiit will do both.

### 1.2 Legal points that shaped the design (India)

- **Aadhaar:**
  - No law authorises an RWA or app to keep full numbers.
  - §8A / Reg. 14A bars storing them for offline-verification entities.
  - Reg. 14(mb) says copies must be masked (first 8 digits redacted).
  - UIDAI said in Dec 2025 that storing copies violates the Act and named housing societies.
  - Penalty under §33A: up to ₹1 crore.
  - → **last 4 digits + masked Aadhaar only.**
- **DPDP Act 2023 + Rules 2025** (core duties start **13 May 2027**):
  - Notice and consent per purpose.
  - Rule 6: encryption/masking, access control, **logs kept ≥ 1 year**.
  - **§8(7): erase once the purpose ends.** → Consent capture, access log, 12-month purge.
- **PAN:** not expressly "sensitive" under SPDI 2011 (which lapses May 2027), but high-risk. → Encrypt, mask, log and rate-limit every reveal.
- **Police verification** is the **landlord's** legal duty (BNSS §163 orders). → Store the acknowledgement receipt and number.
- **Rent agreements:** usually 11 months; Maharashtra requires registration regardless. → Store `valid_from`, `valid_until` and the registration / e-stamp number.
- **Ownership proof:**
  - Sale deed / conveyance deed.
  - Allotment + possession letter.
  - Share certificate + Index II (Maharashtra co-op housing societies).

<details><summary>Sources</summary>

- MyGate: mygate.com/blog/feature-in-focus/tenant-management/ · help.mygate.in/articles/128214 · adminfaq.mygate.com/articles/129847
- NoBrokerHood: nobrokerhood.com/solutions/nobrokerhood-features · nobrokerhood.com/blog/dpdp-act-for-society/
- ApnaComplex: blog.apnacomplex.com/2022/11/22/new-feature-alert-apnacomplex-move-in-move-out/ · blog.apnacomplex.com/2010/08/13/apnacomplex-document-access-control/
- ADDA: blog.ind.adda.io/2026/02/dpdp-act-for-housing-societies-guide-for-rwas/ · blog.ind.adda.io/2026/03/adda-consent-manager-for-residents/
- Aadhaar Act §29: indiankanoon.org/doc/30018477/ · Sharing Regs 2016: uidai.gov.in/images/6_The_Aadhaar_Sharing_of_Information_Regulations_2016.pdf
- UIDAI Dec 2025: medianama.com/2025/12/223-explained-uidais-new-rule-aadhaar-based-verification/
- Data Vault scope (Circular 8/2025): mondaq.com/india/privacy-protection/1719124/
- DPDP: dpdpa.com/dpdparules/rule6.html · dpdpa.com/dpdpa2023/chapter-2/section8.html
- Maharashtra L&L registration: indiankanoon.org/doc/8402442/ · CHS bye-law 43: cubeonebiz.com/blog/co-operative-housing-society-bye-law-43-44/
- Supabase: storage/security/access-control · storage/schema/helper-functions · storage/serving/downloads · database/vault · pgsodium (pending deprecation, so not used)

</details>

---

## 2. Who can see and do what

**"List"** = sees the document row (type, status, dates, last-4). **"Open"** = can download the pages.

| Actor | Own docs | Family members they added (`resident_type='family'`, `created_by = me`, I still live in the flat) | Tenant of a flat I own (`is_owner_of_flat(tenant's current flat)`) | Co-owner of my flat | Full PAN |
|---|---|---|---|---|---|
| Resident (incl. moved-out, until purged) | list, open, upload | list, open, upload | – | – | reveal own |
| Flat owner | list, open, upload | list, open, upload | **tenancy**: list, open, upload · **identity**: list only | **ownership**: list, open | ✗ for others |
| Tenant | list, open, upload | list, open, upload | – | – | reveal own |
| Society admin (**active**) | all in own society, keyed on `doc.society_id` | | | | reveal **with reason**; max 10 per 10 min and 50 per day |
| Master admin, guard, other society | ✗ | ✗ | ✗ | ✗ | ✗ |

- Only active admins verify or reject.
- Every open and every PAN reveal writes a `document_access_log` row. No API role can write, update or delete log rows directly.

---

## 3. Schema: `supabase/20_resident_documents.sql`

Follow the existing RPC conventions:
- `security definer set search_path = public`
- auth check first
- `jsonb {success, error}` return envelope
- grants name the argument list

Hardening:
- `revoke all` on the new tables from `anon, authenticated`, then grant only the SELECTs that are needed.
- Keep the new tables out of `supabase_realtime`.

### 3.0 Phase 0 (top of 20; also patch `11` and `04` in place)
- Re-create `is_society_admin(uuid)` with `and a.status = 'active'`.
- **`residents_before_write` trigger** (copy `society_guards_before_write`, `17_guard_identity.sql:97-148`). The name sorts before `trg_residents_link_on_insert`, so it runs first. When the caller is `authenticated` and not `is_society_admin(new.society_id)`:
  - **INSERT:** `created_by := auth.uid()`; `user_id := null` so linking by email decides it; `society_id :=` the flat's block's society.
  - **UPDATE:** `user_id`, `flat_id`, `society_id`, `created_by`, `resident_type` and `is_primary` can't change.
- Add `and public.lives_in_flat(flat_id)` to `residents_update_household` and `residents_delete_household`.
- **Pre-deploy check** (goes in the deploy notes): `select status, count(*) from society_admin_users group by 1`. Any non-`active` admin is locked out after the fix.

### 3.1 Extensions and helpers
- `create extension if not exists pgcrypto with schema extensions;`
- `is_owner_of_flat(p_flat_id)`: active `residents` row, `resident_type = 'owner'`, `user_id = auth.uid()`.
- `document_category(doc_type)` (immutable) → `identity | tenancy | ownership`.
- Two helpers implement §2 on the document's **current** resident and flat. The admin branch uses `doc.society_id` directly.
  - `can_list_resident_document(p_document_id)`
  - `can_open_resident_document(p_document_id)`
- `can_upload_resident_document(p_resident_id, p_doc_type)`: §2 rules, plus the category must suit the subject's `resident_type`. Tenancy is for tenant households; ownership is for owners.

### 3.2 Tables

**`resident_documents`**
- `id`
- `society_id` (**restrict**)
- `flat_id`, `resident_id` (**set null**)
- `doc_type` check:
  - `masked_aadhaar`
  - `rent_agreement`, `police_verification`, `owner_noc`
  - `sale_deed`, `conveyance_deed`, `allotment_letter`, `possession_letter`, `share_certificate`, `index_ii`, `other_ownership`
- `category`
- `valid_from`, `valid_until` (CHECK: required for `rent_agreement`, and `valid_until >= valid_from`)
- `reference_number`, `note`
- `status` in `uploading | pending | verified | rejected | withdrawn | superseded | abandoned | purged`
- `review_note`
- `uploaded_by`, `verified_by` (auth.users, **set null**)
- `created_at`, `submitted_at`, `verified_at`
- `retention_until` (**move-out clock only**), `files_purged_at`
- CHECK `resident_id is not null or retention_until is not null or status in ('purged','abandoned','rejected','withdrawn')`, so a failed retention trigger raises an error instead of silently leaving documents that are never purged.
- RLS: SELECT `using (can_list_resident_document(id))`. No write policies (RPC only).

**`resident_document_files`**
- `document_id` (cascade)
- `page_no` 1–10
- `storage_path` (unique)
- `mime_type` in (`image/jpeg`, `image/png`, `application/pdf`)
- `size_bytes` ≤ 10 MB
- A document is **either 1 PDF or up to 10 images**.
- RLS: SELECT via `can_open_resident_document(document_id)`.

**`resident_identity`**
- `resident_id` PK (FK **cascade**: removing a member erases the PAN at once)
- `society_id`, `flat_id`
- `pan_enc bytea not null`
- `pan_last4` (check `^[0-9]{3}[A-Z]$`)
- `key_version smallint default 1`
- `updated_by` (set null), `updated_at`, `retention_until`
- RLS on, **no policies**: RPC only.

**`document_access_log`**
- `society_id`
- `actor_id`, `resident_id`, `document_id`: **no FKs** (set null semantics), so deleting a user or resident never deletes log rows.
- `actor_role`
- `action` in (`upload`, `view`, `reveal_pan`, `verify`, `reject`, `withdraw`, `purge`)
- `reason`, `accessed_at`
- RLS: admins read their society; actors read their own rows; a resident reads rows about themselves. No insert/update/delete policies. `revoke insert, update, delete` from `anon, authenticated`.
- Index on `(actor_id, document_id, accessed_at desc)`.

**`resident_document_consents`**
- `resident_id` (set null), `user_id`
- `on_behalf_of_resident` bool
- `notice_version`, `given_at`, `withdrawn_at`

### 3.3 Private bucket `resident-documents`
- `public = false`, `file_size_limit = 10 MB`, `allowed_mime_types = {image/jpeg, image/png, application/pdf}`. Use `on conflict … do update`.
- Path, **generated by the server**: `{society_id}/{flat_id}/{document_id}/{page_no}-{uuid}.{ext}`

`storage.objects` policies:
- **INSERT:** `bucket_id = 'resident-documents' and public.can_upload_document_file(name)`. Allowed only if a file row reserves exactly this path, its document is `uploading`, the caller uploaded it, and it's under 1 hour old. Upload with `upsert: false` needs INSERT only.
- **SELECT:** `bucket_id = 'resident-documents' and storage.allow_only_operation('object.get_authenticated') and public.has_document_view_grant(name)`.
  - The grant is a `view` log row by the caller for that document from the last 10 minutes, and `can_open_resident_document` must still be true.
  - `allow_only_operation` blocks `createSignedUrl`, `copy` and `info`, which would otherwise mint unlogged bearer URLs or copy files into public buckets.
  - **Check on staging:** `to_regprocedure('storage.allow_only_operation(text)')` exists; `download()` works; `createSignedUrl` fails.
  - If the function isn't available, the guarantee is weaker: "every access starts with a logged open".
- **No UPDATE or DELETE policies.** Deletion happens only through the Storage API with the service role. Deleting `storage.objects` rows in SQL is blocked by `storage.protect_delete` and wouldn't remove the file anyway.

### 3.4 RPCs

| RPC | Who | Does |
|---|---|---|
| `create_resident_document(p_resident_id, p_doc_type, p_mime_types text[], p_sizes int[], p_valid_from, p_valid_until, p_reference_number, p_note, p_consent_version)` | `can_upload…` | Validates the page rule (1 PDF or ≤ 10 images), MIME types and sizes. Records consent (`on_behalf` if the uploader isn't the subject). Inserts the document (`uploading`) and file rows. Returns `{document_id, paths[]}`. |
| `submit_resident_document(p_document_id)` | uploader | Checks every path exists in `storage.objects` **and** that `metadata->>'mimetype'` / `size` match what was reserved. Sets `pending`. Logs `upload`. Notifies admins. Notifies the subject if the upload was on their behalf. |
| `cancel_resident_document` / `withdraw_resident_document` | uploader | `uploading → abandoned` / `pending → withdrawn`. Files are purged on the next run. |
| `open_resident_document(p_document_id, p_reason default null)` | `can_open…` | Logs `view`. Returns pages (path, mime, page_no) and watermark text. |
| `review_resident_document(p_document_id, p_decision, p_note)` | active admin | `verified` or `rejected` (note required). Verify marks older verified docs of the same (resident, type) as `superseded`, except `other_ownership`. Rejected files are purged on the next run; the row stays so the reason can be read. Logs and notifies. |
| `set_resident_pan(p_resident_id, p_pan)` | self, family-creator, admin | Normalise; `^[A-Z]{5}[0-9]{4}[A-Z]$`; key = Vault `resident_pii_key_v{key_version}`. **If the key is null, error "PAN storage not configured"**, because `pgp_sym_encrypt` is STRICT and would otherwise save a null. `extensions.pgp_sym_encrypt(pan, key, 'cipher-algo=aes256')`. Never put the PAN in an error or in dynamic SQL. |
| `reveal_resident_pan(p_resident_id, p_reason)` | self; admin (reason ≥ 5 chars) | Rate limits from §2. Catches decrypt errors and returns a generic error. Logs `reveal_pan`. |
| `get_resident_identities(p_flat_id)` | filtered by the list rules | `resident_id`, `has_pan`, `pan_last4` only |
| `admin_documents_overview(p_society_id)` | active admin | To verify; expiring ≤ 30 days; expired; tenants without a verified rent agreement; owners without verified ownership proof |
| `documents_due_for_purge(p_limit)`, `mark_documents_purged(p_ids)`, `purge_expired_identities()`, `prune_document_access_log()` | **service_role only**: `revoke all … from public, anon, authenticated; grant execute … to service_role` | See §3.6 |

**Notifications** (`document_submitted`, `document_verified`, `document_rejected`, `document_expiring`):
- Re-create `notifications_type_check` with the full current list from `12_parking_bay_requests.sql:315-323` plus these four, in the same `do $$ … exception` block.
- Bodies contain **no personal data** (e.g. "A document needs review").
- Always addressed to a specific `user_id`, or `target_role = 'society_admin'`. Never `resident` / `all`.
- Inserts are wrapped in `exception when others`, like migration 18.

### 3.5 Retention triggers (`security definer set search_path = public`)
- **`residents` AFTER UPDATE OF status, when `old.status is distinct from new.status`:**
  - `active → moved_out`: `retention_until = coalesce(retention_until, current_date + interval '12 months')` on the resident's not-purged documents and identity row.
  - `moved_out → active`: clear it.
- **`residents` BEFORE DELETE:** same as `→ moved_out`. The identity row cascades away.
- **`invoke_document_purge()`:**
  - Copies `fn_push_visitor_change`: Vault `documents_purge_url` + `documents_purge_secret`, then `net.http_post(…, timeout_milliseconds := 60000)`.
  - A commented SETUP block, like `17_push_notifications.sql:173-182`, gives:
    - the `vault.create_secret` calls, including `resident_pii_key_v1`
    - `cron.schedule('purge-resident-documents', '30 21 * * *', …)` (03:00 IST)
- Add rows for 20 to `supabase/check_applied_migrations.sql`.

### 3.6 Edge Function `supabase/functions/purge-resident-documents/index.ts`
Copy the structure of `push-visitor/index.ts`:
- **constant-time** `x-purge-secret` check
- service-role client
- `--no-verify-jwt`

Behaviour:
- Returns 202 at once and does the work in `EdgeRuntime.waitUntil`.
- Caps the batches per run.

Due for purge:
- retention passed
- `rejected`, `withdrawn` or `abandoned`
- `uploading` older than 24 h

Loop:
1. `documents_due_for_purge(200)`
2. `remove(paths)`, in chunks
3. `mark_documents_purged(ids)`. It checks the objects are really gone from `storage.objects` before deleting file rows. It clears `reference_number`, `note` and `review_note` and sets `purged` (retention-expired) or `files_purged_at`.

Then:
- `purge_expired_identities()`
- `prune_document_access_log()` (older than 2 years)
- a sweep for files in the bucket older than 24 h that have no file row

---

## 4. App (Flutter): mobile and web first

**Dependencies:**
- `file_picker`: **PDF only**, `withData: true`.
- `pdfrx`: `PdfViewer.data(bytes)`; supports all six platforms, the repo has linux/windows/macos runners, and pdfx doesn't support Linux. Confirm Windows support when adding it.
- Photos keep using `image_picker` at `maxWidth: 2000, imageQuality: 85`. That also converts HEIC to JPEG.
- Hide the camera option on desktop.

**`lib/models/resident_document_models.dart`**
- `ResidentDocType`: `dbValue`, `label`, `category`, `requiresValidity`, `allowedFor(resident_type)`.
- `ResidentDocStatus`.
- `ResidentDocument.fromMap` + `expiryState(now)`: `none | valid | expiringSoon (≤ 30 d) | expired`.
- `ResidentDocumentFile`, `ResidentIdentityMasked`.
- `PanNumber.normalize / isValid / mask`.
- `DocumentFileCheck.sniffMime(bytes)`: magic bytes `FF D8 FF`, `89 50 4E 47`, `%PDF`, plus the 10 MB limit.

**`lib/services/resident_documents_service.dart`**
- Singleton `ChangeNotifier`, same pattern as `vehicles_parking_service.dart` (`_safeClient`, `_humanize`, per-key load errors).
- Unwraps RPC results like `visitors_service.dart` `_rpcOk`. **Never falls back to direct table writes.**
- **Upload:**
  - create → pages uploaded **one at a time**, each with `uploadBinary(path, bytes, FileOptions(contentType: mime, upsert: false, cacheControl: '0'))`, dropping the bytes after each → submit.
  - A 409 on retry counts as OK; submit re-checks the file is there.
  - On failure → cancel.
- **View:**
  - `open_resident_document`, then `storage.from('resident-documents').download(path)`, **lazily per page**.
  - If a page returns "Object not found" (the grant expired), call `open` again once, then retry.
  - **No URLs are ever created.**

**Screens, `lib/screens/documents/`:**
- `documents_root_screen.dart`: admin/resident switch, copied from `complaints/complaints_root_screen.dart`.
- `resident_documents_screen.dart`: one card per person I can list (me, family I added; for owners, the tenant household too). Each card has three sections:
  - **ID:** Aadhaar `•••• 1234` + masked-Aadhaar status; PAN `••••••234F` with Add/Change and Show (own only).
  - **Tenancy:** rent agreement with validity and countdown, police verification, owner NOC.
  - **Ownership:** sale deed, allotment letter, etc.
- `document_upload_sheet.dart`:
  - Type picker from `allowedFor`.
  - Up to 10 photos (camera/gallery) **or** 1 PDF.
  - Dates and reference number.
  - Masked-Aadhaar help text: "Download from myaadhaar.uidai.gov.in; cards showing all 12 digits will be rejected".
  - On first upload: a DPDP notice and consent checkbox.
- `document_viewer_screen.dart`:
  - `PageView` of `InteractiveViewer(Image.memory(cacheWidth: …))` or a `pdfrx` viewer.
  - Diagonal watermark overlay: "Viewed by {name} · {date} · Saqiit".
  - Admin bar: Verify / Reject (required reason via `showTextInputDialog`). Masked Aadhaar needs an "Only last 4 digits visible" tick before Verify is enabled.
- `admin_documents_dashboard.dart`: tabs **To verify · Expiring · Missing**, with a block filter. The access-log tab comes in Phase 2.

**PAN entry and reveal:**
- Add an optional `validator` parameter to `showTextInputDialog` (`lib/widgets/text_input_dialog.dart`), plus `enableSuggestions`/`autocorrect` flags. The PAN field uses `TextCapitalization.characters`, no suggestions and no autocorrect.
- Admin reveal asks for a reason, then shows the PAN for 30 s.

**Wiring (kept small):**
- `lib/main.dart`: `/documents` → `_NotForGuards(child: DocumentsRootScreen())`.
- `lib/screens/home_screen.dart`: "Documents" tile in both `_servicesFor` lists. `_badgeFor` shows the to-verify count (admin) or "action needed" (resident).
- `lib/screens/directory_screen.dart` `_FlatDetailSheet` (:1181-1193): "Documents" action for admins.
- `lib/models/notification_model.dart` (switches at :110 and :151): the 4 new types.
- `lib/services/app_session.dart:197`: admin only if the row is `status == 'active'`.
- `ios/Runner/Info.plist:32-35`: add "documents" to the usage strings.

---

## 5. Flows

- **D1. Tenant moves in:**
  1. Admin approves the join request (existing flow).
  2. The Home tile shows "action needed".
  3. Tenant adds PAN, masked Aadhaar, and the rent agreement (3 photos, validity dates).
  4. Admin is notified, opens it (logged), and verifies.
  5. Tenant and owner see "Verified · expires in 11 months".
- **D2. Owner uploads for the tenant:** rent agreement or police receipt, recorded as consent "on behalf". The tenant is notified.
- **D3. Renewal:** a new agreement is verified and the old one becomes `superseded`. Expiring and badges clear.
- **D4. Flat sold:**
  1. The new owner joins as an owner.
  2. They upload the sale deed PDF (plus other proof as the society requires).
  3. Admin verifies.
  4. Admin marks the old owner `moved_out`, which starts their 12-month clock.
  5. A guided "Transfer ownership" flow comes in Phase 2.
- **D5. Move-out:** `moved_out` → `retention_until = +12 months` → the nightly purge deletes files and PAN and logs `purge`.
- **D6. Admin PAN reveal:** reason → PAN shown for 30 s → log row written. Limits apply.

---

## 6. Build phases

| Phase | Contents | Size |
|---|---|---|
| **0** | `is_society_admin` status fix (20 + patch 11) · `residents_before_write` trigger + tighter household policies · `app_session` admin status check · tests | S |
| **1** | Rest of migration 20 · purge Edge Function · models · service · 4 screens · wiring (§4) · tests + staging RLS script | L |
| **2** | Expiry reminders (daily cron → `document_expiring` at 60/30/7 days) · guided **ownership transfer** (`flat_ownership_transfers`, requires a verified sale deed, auto `moved_out` for the seller) · admin access-log tab + "who viewed my documents" · screenshot blocking on the viewer · consent withdrawal ("delete my documents") + data export · per-society retention setting · move `vehicle-rc-docs` to a private bucket | M |
| **3** | Server-side watermarking on export · bulk export with OTP + reason · admin MFA (`aal2`) for document access · Aadhaar Secure-QR / DigiLocker verification (needs UIDAI OVSE registration) · OCR check that an Aadhaar upload is masked | L |

---

## 7. Verification

**Static tests** (same style as `test/guard_panel_sql_test.dart`):
- `test/resident_documents_sql_test.dart`:
  - **every** `supabase/*.sql` definition of `is_society_admin` contains `status = 'active'`
  - `residents_before_write` exists and freezes the 6 columns
  - bucket `public = false` with limits
  - no storage policy in any repo SQL file skips `bucket_id`
  - the SELECT policy uses `allow_only_operation`
  - no UPDATE/DELETE storage policy for the bucket
  - non-trigger, non-service `security definer` functions have an auth check
  - grants name argument lists
  - service-role functions are revoked from `public, anon, authenticated`
  - retention trigger functions are `security definer`
  - `resident_identity` has no policies
  - no insert or `all` policy on `document_access_log`
  - no column matching `aadha?r_(number|full|no)`
  - `set_resident_pan` never puts `p_pan` into an error string, `format(` or `execute`
  - `notifications_type_check` keeps every earlier type
- `test/resident_document_models_test.dart`:
  - `fromMap` and enums
  - `allowedFor`
  - `expiryState` boundaries
  - PAN normalise/validate/mask
  - `sniffMime`
  - 10 MB limit
  - the page rule
- `test/documents_screen_test.dart`: resident and admin views offline, 320 px layout.
- Extend `test/text_input_dialog_test.dart` for `validator`.

**Checks:** `flutter analyze` is clean and `flutter test` passes.

**Staging** (after running 20, creating the Vault secrets and deploying the function):
- `supabase/check_resident_documents_access.sql` (new, read-only). It impersonates each actor from §2 with `set local role authenticated; set local request.jwt.claims = '{"sub":"…","role":"authenticated"}'` and asserts list/open/reveal results.
- `select policyname, qual, with_check from pg_policies where schemaname = 'storage' and tablename = 'objects'`: every row mentions `bucket_id`.

Manual:
- [ ] An owner can't change their tenant's `user_id` or `flat_id` (P0-2).
- [ ] A deactivated admin can't list documents or open admin screens.
- [ ] The public URL for the bucket fails, and `createSignedUrl` fails.
- [ ] `download()` without first calling `open_resident_document` fails; with it, it works. Each open writes 1 log row.
- [ ] Flat 101 can't see flat 102. A guard and the master admin get nothing. A tenant can't see the owner's sale deed.
- [ ] The owner opens the tenant's rent agreement, sees the masked-Aadhaar **status** only, and gets *Permission denied* from `reveal_resident_pan`.
- [ ] `pan_enc` is ciphertext. Admin reveal needs a reason, and the 11th reveal in 10 min is refused.
- [ ] 3-photo rent agreement + PDF sale deed → verify → notifications arrive → a renewal supersedes the old agreement. Expiring and expired states show correctly.
- [ ] Rejecting a document removes its files on the next purge, and the rejection reason is still visible.
- [ ] Move-out → `retention_until` is set. Set it to yesterday and invoke the function → files are gone, status is `purged`, the identity row is deleted, and a `purge` log row exists.

**Deploy notes** (to go in the repo plan doc):
- Run the pre-deploy admin-status check first.
- Create Vault `resident_pii_key_v1` (random 32 bytes, base64) and **back it up offline**: losing it makes every PAN unreadable.
- Enable `pg_cron` and `pg_net`, deploy the function, set `PURGE_WEBHOOK_SECRET`, then run the schedule.
- Never turn on statement or parameter logging (`log_min_duration_statement`, pgaudit parameter logging): it would write PANs from RPC calls into the logs.
- Make sure "Confirm email" is on in Supabase Auth. Residents are linked to accounts by email at sign-up.

---

## 8. Files touched (Phase 0 + 1)

| File | Change |
|---|---|
| `supabase/20_resident_documents.sql` | new |
| `supabase/11_vehicles_parking_module.sql` | `is_society_admin` status check |
| `supabase/functions/purge-resident-documents/index.ts` | new |
| `supabase/check_applied_migrations.sql` | + rows for 20 |
| `supabase/check_resident_documents_access.sql` | new (staging RLS check) |
| `pubspec.yaml` | + `file_picker`, `pdfrx` |
| `lib/models/resident_document_models.dart` | new |
| `lib/services/resident_documents_service.dart` | new |
| `lib/screens/documents/` (root, resident, admin dashboard, upload sheet, viewer) | new |
| `lib/widgets/text_input_dialog.dart` | `validator`, keyboard flags |
| `lib/services/app_session.dart` | admin requires `status == 'active'` |
| `lib/main.dart`, `lib/screens/home_screen.dart`, `lib/screens/directory_screen.dart`, `lib/models/notification_model.dart` | entry points, badges, notification types |
| `ios/Runner/Info.plist` | usage strings |
| `test/resident_documents_sql_test.dart`, `test/resident_document_models_test.dart`, `test/documents_screen_test.dart`, `test/text_input_dialog_test.dart` | new / extended |

## 9. Noted, not in scope

- Existing public buckets (`vehicle-rc-docs` holds RC documents) → Phase 2.
- Aadhaar photocopy rules and the DPDP start date (13 May 2027) are moving targets. Re-check before Phase 2.
- The 12-month retention period is a policy choice, not a statute; the society should confirm it with counsel.
- macOS release entitlements lack `network.client` and `files.user-selected.read-only` (already broken today). Documents target mobile and web first.

---

## 10. Implementation status: Phase 0 + 1 (30 Sep 2026)

### Deploy

1. **Check who stays an admin** (read-only):
   `select status, count(*) from public.society_admin_users group by 1;`
   Only rows with `status = 'active'` keep admin access after this change, in the app and on the server.
2. In the Supabase SQL editor, run `supabase/check_applied_migrations.sql`. Run anything **MISSING** in number order, then run `supabase/20_resident_documents.sql` **after 19**. Its notification type list is the union of every module's; `19_facilities_module.sql` on its own drops the five marketplace types.
3. Create the PAN key and **keep an offline copy**; losing it makes every stored PAN unreadable:
   `select vault.create_secret(encode(extensions.gen_random_bytes(32), 'base64'), 'resident_pii_key_v1');`
4. Deploy the purge function:
   - `supabase functions deploy purge-resident-documents --no-verify-jwt`
   - `supabase secrets set PURGE_WEBHOOK_SECRET=<long random string>`
   - Vault secrets `documents_purge_url` and `documents_purge_secret` (see the SETUP block at the end of migration 20).
5. Enable `pg_cron`, then schedule the nightly run:
   `select cron.schedule('purge-resident-documents', '30 21 * * *', $cron$ select public.invoke_document_purge() $cron$);`
6. On staging, fill in the ids in `supabase/check_resident_documents_access.sql` and run it. Every row must say PASS, including the storage-policy audit at the end.
7. Never turn on statement or parameter logging: RPC arguments, including a PAN being saved, would be written to the logs.

### What shipped

| Area | Where |
|---|---|
| P0-1: deactivated admins are not admins (SQL + app) | `20_resident_documents.sql` §1, `11_vehicles_parking_module.sql`, `lib/services/app_session.dart` |
| P0-2: a household member's creator can no longer change who the row belongs to, or edit it after leaving the flat | `20` §2 (`residents_before_write`), `04_profile_self_service.sql` |
| Tables, RLS, private bucket, storage policies, RPCs, retention triggers, purge functions | `supabase/20_resident_documents.sql` |
| Nightly purge | `supabase/functions/purge-resident-documents/index.ts` |
| Staging access check (impersonates each actor) | `supabase/check_resident_documents_access.sql` |
| Models, service | `lib/models/resident_document_models.dart`, `lib/services/resident_documents_service.dart` |
| Screens: Documents (resident / per flat), office dashboard (To verify · Expiring · Missing), upload sheet, viewer with watermark and Verify / Reject | `lib/screens/documents/` |
| Entry points: Home tile + badge, `/documents` route (blocked for guards), "Documents" in the directory's flat sheet, notification icons | `home_screen.dart`, `main.dart`, `directory_screen.dart`, `notification_model.dart` |
| PAN entry: validator and no keyboard learning | `lib/widgets/text_input_dialog.dart` |

### Changed from the plan

- **Migration number 20, not 19.** `19_facilities_module.sql` arrived on this branch meanwhile.
- **Signed URLs are blocked with a check of `storage.operation`**, not `storage.allow_only_operation()`: the read policy refuses sign, copy and move operations and allows everything else, so a Storage version that names its operations differently still serves downloads. Confirm on staging that `createSignedUrl` on this bucket fails.
- **The uploader may read their own pages while the upload is in progress**, in case Storage's insert uses `RETURNING` (Postgres then applies the SELECT policy).
- **Notification type list is the union of all modules** (fixes the facilities/marketplace mismatch above).

### Tests

- `test/resident_documents_sql_test.dart`: static checks on migration 20 and on every migration (admin status, storage policies naming `bucket_id`, no full-Aadhaar column, notification types kept).
- `test/resident_document_models_test.dart`: types, expiry boundaries, PAN, file sniffing, page rules.
- `test/documents_screen_test.dart`: offline screens, upload sheet (tenancy types only, validation, 320 px), rejected-document tile.
- `test/text_input_dialog_test.dart`: the new validator.
- `flutter analyze` is clean and the full suite passes (197 tests).
- Migration 20, the patched 04 and 11, and both check scripts were parsed with libpg_query (pglast), including every PL/pgSQL body. **They have not been run against a live database.** Do that on staging with the checklist in §7 and the access script.

### Still open

- Not built yet: expiry push reminders, guided ownership transfer, screenshot blocking, "who viewed my documents", consent withdrawal and data export, per-society retention (Phase 2); server-side watermarking, OTP bulk export, admin MFA, Aadhaar QR verification (Phase 3).
- `vehicle-rc-docs` and the other older buckets are still public.

