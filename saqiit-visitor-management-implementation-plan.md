# Saqiit — Visitor Management Module: Implementation Plan

Scope of this document: **User Panel + Society Admin Panel only.** Guard Panel does not exist yet — everywhere the flow needs a "gate" actor, the Society Admin panel temporarily plays that role via a **"Log Visitor Entry"** screen built on the exact same server action a future Guard app will call. When the Guard panel is built, it plugs into this schema/API with zero changes — it just gets its own UI calling `createVisitorEntry`, `verifyPreApproval`, and `checkInVisitor` / `checkOutVisitor`.

---

## 1. Research — how NoBrokerHood does it (reference model)

Findings from NoBrokerHood's Visitor Management ("Manage Visitors" app) and Guest Management docs:

- **Two entry paths, one system:**
  1. **Gate-initiated ("Notify Gate" equivalent):** guard/gate pre-registers the visitor (name, phone, purpose), captures a **photo** (and optionally ID), then sends a **host alert** to the resident to Approve/Deny. On approval, a time-limited access pass is granted.
  2. **Resident-initiated pre-approval ("Pre-Approve"):** resident proactively approves an expected visitor *before* they arrive, picking a category — **Cab, Delivery, Guest, Group Invite, Others** (your screenshots) — with **One Day** or **Long Duration** validity. This generates a code/QR the gate can instantly clear without bothering the resident again.
- **Group Invite:** a single pre-approval can cover multiple guests at once (built for parties/events) — this is a newer NoBrokerHood addition per their release notes.
- **"Secure pickup" badge on Cab:** cab pre-approvals get extra verification framing (driver/vehicle details) since they're a higher-risk category.
- **Make it Private:** a pre-approval can be scoped so only the creating resident (not the whole flat/family group) is notified — useful for shared flats.
- **Real-time notifications** fire on both sides: resident gets notified the moment a visitor is at the gate; guard/gate gets notified the moment a resident pre-approves someone.
- **Verification methods supported:** photo capture, OTP, and (in premium tiers) biometric/facial recognition — we'll support **photo + status-based approval** now, with OTP handover reserved for Delivery (already planned in the Delivery module) and left as a future add-on here.
- **Digital gate pass / unique code:** every pre-approval and every approved gate visit produces a record the guard can check against — this becomes our `approval_code`.
- **Overstay alerts:** guard app nudges when a checked-in visitor has been inside unusually long — worth designing the schema to support even though the Guard panel isn't built yet (`checked_in_at` + a cron/edge function later).
- **Frequent/Daily Help:** residents save recurring visitors (maid, driver, tutor) for 1-tap future approval — a natural phase-2 add-on once the base module ships, using the same `visitors` table with a `save_as_frequent` flag.
- **Notification log / call-back:** your reference screenshot (Notifications tab) shows a running log of visitor events with a tap-to-call icon next to each — we'll mirror this as the notification center's default view.

### Decision: features we're building now vs. deferring

| Feature | Now | Later |
|---|---|---|
| Gate-initiated visitor request → resident approve/deny (with photo) | ✅ | |
| Pre-Approve: Delivery / Guest / Group Invite / Cab / Others | ✅ | |
| One Day / Long Duration validity | ✅ | |
| Make It Private | ✅ | |
| Unique approval code + QR | ✅ | |
| Deny with reason | ✅ | |
| Full status history / audit trail | ✅ | |
| Real-time popup notifications (Admin + User) | ✅ | |
| Guard check-in/check-out at gate | schema ready | Guard panel build |
| OTP-based handover | — | reuse Delivery module's OTP pattern |
| Overstay alerts | schema ready (`checked_in_at`) | cron/edge function once Guard exists |
| Frequent/Daily Help visitors | — | phase-2 nice-to-have |
| Facial recognition / biometric | — | out of scope indefinitely |

---

## 2. Schema

```sql
-- Core visitor record — covers BOTH flows (gate-initiated and pre-approved)
create table visitors (
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null references societies(id),
  flat_id uuid not null references flats(id),
  block_id uuid references blocks(id),               -- denormalized for fast admin filtering

  -- who created this record
  created_by_type text not null check (created_by_type in ('resident','society_admin','guard')),
  created_by uuid not null,                           -- FK resolved in app layer (polymorphic: residents / society_admin_users / future guards)

  -- visitor identity
  visitor_name text not null,
  visitor_phone text,
  visitor_photo_url text,                              -- captured at gate, or optional on pre-approval
  vehicle_number text,                                 -- for Cab / Delivery

  category text not null check (category in ('delivery','guest','group_invite','cab','others')),
  company_or_context text,                             -- e.g. "Blinkit", "Ola", free text for Others

  entry_type text not null check (entry_type in ('gate_request','pre_approved')),

  status text not null default 'pending_approval' check (status in (
    'pending_approval', 'approved', 'denied', 'expired',
    'checked_in', 'checked_out', 'cancelled'
  )),

  -- pre-approval specific
  approval_code text unique,                           -- short numeric code, always generated on approval
  qr_payload text,                                      -- encodes approval_code for guard scanning
  duration_type text check (duration_type in ('one_day','long_duration')),
  valid_from timestamptz,
  valid_until timestamptz,
  is_private boolean not null default false,            -- notify only created_by, not whole flat

  -- approval / denial
  approved_by uuid references residents(id),
  approved_at timestamptz,
  denied_by uuid references residents(id),
  denied_at timestamptz,
  denied_reason text,

  -- gate check-in/out (Guard panel will populate these later; schema ready now)
  entry_gate text,
  checked_in_at timestamptz,
  checked_in_by uuid,
  checked_out_at timestamptz,
  checked_out_by uuid,

  save_as_frequent boolean not null default false,      -- phase-2 hook, harmless to add now

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Group Invite: multiple guests under a single pre-approval
create table visitor_group_members (
  id uuid primary key default gen_random_uuid(),
  visitor_id uuid not null references visitors(id) on delete cascade,
  guest_name text not null,
  guest_phone text,
  created_at timestamptz not null default now()
);

-- Full audit trail — same pattern as complaint_status_history
create table visitor_status_history (
  id uuid primary key default gen_random_uuid(),
  visitor_id uuid not null references visitors(id) on delete cascade,
  from_status text,
  to_status text not null,
  changed_by uuid not null,
  changed_by_role text not null check (changed_by_role in ('resident','society_admin','guard','system')),
  note text,
  created_at timestamptz not null default now()
);

-- Generic notification queue — SHARED with Notices module (same table, different `type`/`related_type`)
-- If not already created for Notices, create it now; if it already exists, just add new `type` values.
create table if not exists notification_queue (
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null references societies(id),
  target_type text not null check (target_type in ('resident','society_admin','guard')),
  target_id uuid not null,
  type text not null,                    -- e.g. 'visitor_approval_request','visitor_approved','visitor_denied','visitor_preapproved_created'
  title text not null,
  body text,
  related_type text,                     -- 'visitor'
  related_id uuid,                       -- visitors.id
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
```

### Indexes (performance for admin dashboard + resident feed)
```sql
create index on visitors (society_id, status);
create index on visitors (flat_id, status);
create index on visitors (approval_code);
create index on notification_queue (target_type, target_id, is_read);
```

### RLS
```sql
alter table visitors enable row level security;
alter table visitor_group_members enable row level security;
alter table visitor_status_history enable row level security;
alter table notification_queue enable row level security;

-- Society Admin: full access scoped to own society
create policy admin_full_access on visitors for all
  using (exists (select 1 from society_admin_users sau where sau.id = auth.uid() and sau.society_id = visitors.society_id));

-- Resident: can see/act only on visitors for their own flat
create policy resident_own_flat on visitors for select
  using (exists (select 1 from residents r where r.id = auth.uid() and r.flat_id = visitors.flat_id));

-- Resident: can INSERT only their own pre-approvals (entry_type = 'pre_approved', created_by = self)
create policy resident_create_preapproval on visitors for insert
  with check (
    entry_type = 'pre_approved'
    and created_by_type = 'resident'
    and exists (select 1 from residents r where r.id = auth.uid() and r.id = visitors.created_by and r.flat_id = visitors.flat_id)
  );

-- Resident: can UPDATE only status (approve/deny) on gate_request visitors targeting their flat
create policy resident_approve_deny on visitors for update
  using (
    entry_type = 'gate_request'
    and exists (select 1 from residents r where r.id = auth.uid() and r.flat_id = visitors.flat_id)
  );
-- NOTE: which status transitions are actually legal is enforced in Server Action code (see §4), same rule as Complaints module — RLS only gates row visibility, not transition legality.

-- visitor_group_members / visitor_status_history: inherit access via visitor_id join, same shape as above.

-- notification_queue: each user reads only rows where target matches them
create policy own_notifications on notification_queue for select
  using (
    (target_type = 'resident' and target_id = auth.uid())
    or (target_type = 'society_admin' and exists (select 1 from society_admin_users sau where sau.id = auth.uid() and sau.id = notification_queue.target_id))
  );
```

---

## 3. The two flows in detail

### Flow A — Gate-initiated (Admin stands in for Guard today)

1. Admin opens **"Log Visitor Entry"** (temporary gate stand-in), selects the flat, fills visitor name/phone/category, **taps to capture a photo** (camera input or file upload → Supabase Storage bucket `visitor-photos` → URL saved to `visitor_photo_url`).
2. Submits → calls shared server action `createVisitorEntry()`:
   - Inserts `visitors` row: `entry_type='gate_request'`, `status='pending_approval'`, `created_by_type='society_admin'` (will become `'guard'` once that panel exists — same function, different caller context).
   - Inserts `visitor_status_history` row (`to_status='pending_approval'`).
   - Inserts `notification_queue` row targeting the resident(s) of that flat, `type='visitor_approval_request'`, includes `related_id = visitors.id` so the client can fetch the photo.
3. Resident's app receives a **Supabase Realtime** event on `notification_queue` → shows a **popup modal with the visitor's photo**, name, category, and **Approve / Deny** buttons (this is the screen your reference image 3 style informs, but for gate-approval rather than pre-approval).
4. Resident taps Approve → server action `respondToVisitorRequest(status: 'approved')`:
   - Validates the resident belongs to `visitors.flat_id` (defense in depth beyond RLS).
   - Validates current status is `pending_approval` (can't approve an already-resolved request).
   - Sets `status='approved'`, `approved_by`, `approved_at`, generates `approval_code` + `qr_payload`.
   - Inserts `visitor_status_history` row.
   - Inserts `notification_queue` row back to admin (and, later, guard): `type='visitor_approved'`.
   - Once Guard panel exists: guard sees this flip in real time and physically lets the visitor in, then calls `checkInVisitor()` → `status='checked_in'`.
5. Resident taps Deny → same action with `status:'denied'`, **requires `denied_reason`** (enforced server-side, not just UI) → notifies admin.

### Flow B — Resident-initiated Pre-Approval

1. Resident taps **Pre-Approve** on Home → bottom sheet (matches your Image 1): **Delivery / Guest / Group Invite (New) / Cab (Secure pickup) / Others**.
2. Picks a category → form (matches your Image 3): **One Day / Long Duration** tabs, category icon carousel, **Date** picker, **+ Add Guest** (only shown for Group Invite — adds rows into `visitor_group_members`), **Make It Private** checkbox, **Create Invite**.
3. Submits → server action `createPreApproval()`:
   - Inserts `visitors` row directly with `entry_type='pre_approved'`, `status='approved'` (no gate action needed to approve — the resident *is* the approver), `approved_by = self`, `approved_at = now()`.
   - Computes `valid_from`/`valid_until` from the One Day / Long Duration choice.
   - Generates `approval_code` + `qr_payload` immediately (this is the digital pass).
   - For Group Invite, bulk-inserts `visitor_group_members`.
   - Inserts `notification_queue` row(s): if `is_private = false`, notify all residents of that flat; if `true`, notify only the creator. Also inserts an informational notification for admin (and later guard) — `type='visitor_preapproved_created'` — no action required, just visibility ("Rahul from Anand Dham pre-approved a Zomato delivery for today").
4. **Until Guard exists:** Admin's Visitors dashboard shows this as an "Upcoming Pre-Approved" entry. Admin gets a **"Verify Pre-Approval"** lookup (search by `approval_code`) as a manual stand-in for what will be the guard's gate scanner — this lets you test the full loop end-to-end today without a physical gate device.
5. **Once Guard panel exists:** guard scans/enters the code at the gate → `checkInVisitor()` looks up by `approval_code`, validates `status='approved'` and `now() between valid_from and valid_until`, flips to `checked_in`. On departure, `checkOutVisitor()` flips to `checked_out`. No resident interruption needed — this is the whole point of pre-approval.

---

## 4. Status-transition rules (enforced in Server Action code, not just RLS/UI)

Same pattern as the Complaints module — RLS controls *row visibility*, application code controls *which transitions are legal*:

```
gate_request:   pending_approval → approved | denied  (resident only)
                approved → checked_in → checked_out    (guard only, future)
                pending_approval → cancelled            (admin/guard only, e.g. visitor left before response)

pre_approved:   (created directly as 'approved')
                approved → checked_in → checked_out    (guard only, future)
                approved → expired                      (system, when valid_until passes — see §6)
                approved → cancelled                     (resident only, "cancel my invite")
```

Any transition not in this table is rejected server-side with an explicit error, even if RLS would technically allow the row update.

---

## 5. Real-time popup notifications (Admin + User panels)

Reuse (or create, if not already built for Notices) the generic `notification_queue` table + a Postgres trigger, exactly per the architectural pattern already established for Notices:

```sql
create or replace function notify_on_queue_insert() returns trigger as $$
begin
  perform pg_notify('notification_queue_channel', row_to_json(new)::text);
  return new;
end;
$$ language plpgsql;

create trigger trg_notify_on_queue_insert
after insert on notification_queue
for each row execute function notify_on_queue_insert();
```

Client side (both User and Admin panels), subscribe via Supabase Realtime:

```ts
supabase
  .channel('visitor-notifications')
  .on('postgres_changes',
    { event: 'INSERT', schema: 'public', table: 'notification_queue',
      filter: `target_id=eq.${currentUserId}` },
    (payload) => {
      // high-priority types (visitor_approval_request) → open the Approve/Deny modal directly with the photo
      // other types → toast + increment unread badge, land in Notifications tab (your Image 2 layout)
    })
  .subscribe();
```

`type='visitor_approval_request'` is treated as **interrupt-worthy** (opens the modal immediately, photo included) since a visitor is physically waiting at the gate. All other visitor notification types are toast + badge only, non-blocking.

---

## 6. Expiry handling for pre-approvals

Reuse the `pg_cron` pattern from the Notices module: a job every few minutes flips `visitors.status` from `approved` → `expired` where `entry_type='pre_approved'` and `valid_until < now()` and status is still `approved` (i.e., never checked in). This keeps the admin's "Upcoming" list clean and stops stale codes from being usable at the gate.

---

## 7. Screens to build

### User Panel
1. **Home widget** — "Pending approval" banner if a `gate_request` is awaiting response (deep-links straight to the modal).
2. **Gate Approval Modal** — visitor photo (large, prominent), name, category, company/vehicle, Approve / Deny buttons; Deny opens a reason field before submitting.
3. **Pre-Approve bottom sheet** — category tiles: Delivery, Guest, Group Invite (New badge), Cab (Secure pickup badge), Others.
4. **Pre-Approve form** — One Day / Long Duration tabs, date picker, + Add Guest (Group Invite only), Make It Private, Create Invite.
5. **My Visitors** — tabs: Pending / Upcoming (pre-approved) / Past / All, status badges, tap-through to detail.
6. **Visitor detail** — full `visitor_status_history` timeline, QR/code display for pre-approvals, Cancel button (pre-approved + not yet checked in only).
7. **Notifications tab** — chronological visitor + notice events, tap-to-call icon where a phone number exists (matches your reference Image 2).

### Society Admin Panel
1. **Visitors dashboard** — live table, today's visitors across all flats, filters by status/category/block.
2. **Log Visitor Entry** (gate stand-in) — visitor form + photo capture + flat selector → triggers Flow A.
3. **Verify Pre-Approval** (gate stand-in) — lookup by `approval_code` → shows visitor + guest list (if group invite) + flat, manual "Mark Checked In / Out" (stand-in for the guard scanner).
4. **Visitor detail / per-flat history**.
5. **Notification bell** — same realtime popup pattern, admin-relevant `type`s only.

Both admin stand-in screens (`Log Visitor Entry`, `Verify Pre-Approval`) are explicitly temporary UI wrapping permanent server actions — when the Guard panel ships, only its UI needs to be built; no backend changes.

---

## 8. Definition of Done (this phase — User + Admin, no Guard)

- Admin logs a walk-in visitor with a captured photo → resident receives a **real-time popup with the photo** and can Approve/Deny.
- Approve/Deny is enforced server-side against legal transitions (§4), writes to `visitor_status_history`, and notifies admin back.
- Deny without a reason is rejected.
- Resident creates a Pre-Approval for each category (Delivery, Guest, Group Invite, Cab, Others), both One Day and Long Duration, and it appears correctly in Admin's Upcoming list with a valid `approval_code`.
- Group Invite correctly stores multiple `visitor_group_members` under one `visitors` row.
- "Make It Private" suppresses notifications to other residents of the same flat.
- Admin's "Verify Pre-Approval" correctly looks up by code, respects the validity window, and can mark checked-in/out as a manual stand-in.
- Expired pre-approvals auto-flip via cron and disappear from the active "Upcoming" list but remain visible in history.
- Full status-history timeline renders correctly on both panels for every visitor record.
- Realtime popups fire correctly on both User and Admin panels without a page refresh.
- Schema requires **zero migrations** to plug in a future Guard panel — only new UI calling existing server actions (`createVisitorEntry`, `checkInVisitor`, `checkOutVisitor`, code lookup).

---

## 9. Open items / flagged decisions

- **OTP handover for deliveries:** the original project notes specify OTP-based delivery handoff as part of the Delivery module. Recommend the Visitor module's Delivery category reuse that exact OTP mechanism once Delivery is built, rather than inventing a second OTP flow here.
- **QR vs numeric code:** building both now (`approval_code` numeric + `qr_payload` encoding it) so a future guard scanner can use either, based on device capability.
- **"Collect at Gate" category:** NoBrokerHood also offers this as a distinct pre-approval type (visitor's item is collected at the gate rather than them entering). Your reference screenshot doesn't include it — leaving it out of the enum for now, but `category` is a `check` constraint so it's a one-line migration to add later if wanted.
- **Frequent/Daily Help visitors:** flagged as phase-2 in your original roadmap notes (Staff Management ties in here too) — `save_as_frequent` column added now so no migration is needed when that feature is built.
- **Admin's manual stand-in screens' longevity:** recommend keeping `Log Visitor Entry` and `Verify Pre-Approval` in the Admin panel permanently as an override/backup path (e.g., gate device is down), just deprioritized in the nav once Guard panel ships — rather than removing them.
