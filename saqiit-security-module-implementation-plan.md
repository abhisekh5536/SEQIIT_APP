# Saqiit — Security Module (Emergency Contacts) — Implementation Plan

Scope: **Society Admin Panel + User Panel.** No Guard-panel dependency for this module — everything here is either directory data (admin-managed, resident-consumed) or resident-initiated (SOS), so it can ship fully now. When the Guard panel exists later, it can simply be added as an additional recipient of SOS notifications and, optionally, get its own "acknowledge SOS" action — no schema change needed.

---

## 1. Research — what comparable apps actually ship here

Your instinct (admin adds categorized contacts like Plumber/Electrician/Security Guard, multiple numbers per category, resident sees name+number and can call directly, calls get logged against the flat) matches the baseline **"Emergency Contact Directory"** pattern used by smaller society apps (SBM App, AppSociety's "Important Contacts", Servizing). Findings, and where they push beyond your original scope:

- **Categorized, admin-managed directory** is the norm — SBM App: *"Quick access to important contacts like gate security, plumber, electrician, and more."* AppSociety groups them into logical buckets: *"Emergency," "Medical," "Society," "Utilities."* Confirms: categories should be admin-configurable, not a hardcoded enum — different societies will want different buckets.
- **Direct in-app calling** is universal — one-tap to call from the contact card, no manual dialing.
- **NoBrokerHood's SOS button** is the feature your plan is missing entirely, and it's the single most-mentioned safety feature across every review pulled: *"a special SOS button alerts guards in your society to come to your aid in emergency situations."* It's a **distinct concept from the directory** — instead of the resident picking a number and calling out, the resident hits SOS and the *society* (admin/guard) is alerted *in* with the resident's flat and emergency type. NoBrokerHood scopes it to four types: **medical, fire/gas leak, theft/lift emergency, other.** This is a natural, high-value companion to a plain contact directory and turns "Security" from a phonebook into an actual safety feature — recommend adding it.
- **Global/standard emergency numbers** (Police, Ambulance, Fire, Women's helpline, Disaster Management) are typically pre-seeded and pinned above the society-specific list, so residents don't need the admin to remember to add "Police: 100."
- **"Overstay alerts" and digital intercom** are Visitor-module-adjacent (already covered there) — not duplicated here.
- **Call-record capture has a hard technical ceiling** worth flagging up front: a mobile web/PWA app **cannot reliably read whether a `tel:` call actually connected or how long it lasted** — that requires OS-level call-log permissions (`READ_CALL_LOG`), which are invasive, heavily restricted by Google Play policy for non-dialer apps, and not appropriate here. What we **can** honestly capture is **"resident X tapped Call on contact Y at time Z"** — which fully satisfies your actual goal (*"which flat number or tenant calls on the listed numbers"*) without needing OS call-log access. This is called out as a decision in §8.

### Decision: features being added beyond your original scope

| Feature | Included |
|---|---|
| Admin-managed categories + multiple contacts per category | ✅ (your original ask) |
| Resident directory view, tap-to-call | ✅ (your original ask) |
| Call-attempt logging (flat/resident, contact, timestamp) | ✅ (your original ask, scoped per the note above) |
| Pre-seeded global emergency numbers (Police/Ambulance/Fire/etc.) pinned at top | ✅ added |
| SOS button (Medical / Fire / Theft-Security / Other) → alerts admin (+ Guard later) in real time | ✅ added |
| Per-contact availability text (e.g. "24/7", "9 AM–6 PM") | ✅ added |
| Active/inactive toggle (disable without deleting, preserves call history) | ✅ added |
| Admin call-log analytics (most-called contacts, per-flat activity) | ✅ added |
| Actual call connect/duration tracking via OS call logs | ❌ explicitly out of scope — see §8 |

---

## 2. Schema

```sql
-- Admin-defined categories (plus pre-seeded global/system ones shared across all societies)
create table emergency_contact_categories (
  id uuid primary key default gen_random_uuid(),
  society_id uuid references societies(id),        -- NULL = global/system category, visible to every society
  name text not null,                                -- "Utilities", "Medical", "Society Staff", etc.
  icon_key text,                                      -- maps to a frontend icon set
  sort_order int not null default 0,
  is_global boolean not null default false,
  created_at timestamptz not null default now()
);

-- Individual contacts within a category
create table emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  society_id uuid references societies(id),        -- NULL for global contacts (Police/Ambulance/Fire)
  category_id uuid not null references emergency_contact_categories(id),
  name text not null,                                 -- "Ramesh Kumar" or just "Fire Department"
  designation text,                                    -- "Head Electrician", "Security Supervisor" — optional context
  phone_number text not null,
  alternate_phone_number text,
  photo_url text,
  availability text,                                   -- free text: "24/7", "Mon–Sat 9AM–6PM"
  is_active boolean not null default true,              -- soft-disable, preserves call_logs history
  is_global boolean not null default false,
  sort_order int not null default 0,
  created_by uuid,                                      -- society_admin_users.id
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Call-attempt log — "who tapped call, on whom, when" (see §8 for scope of what this can/can't capture)
create table emergency_contact_call_logs (
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null references societies(id),
  contact_id uuid not null references emergency_contacts(id),
  flat_id uuid not null references flats(id),
  caller_type text not null check (caller_type in ('resident','society_admin')),
  caller_id uuid not null,
  called_at timestamptz not null default now()
);

-- SOS alerts — resident-initiated emergency, distinct from directory calling
create table sos_alerts (
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null references societies(id),
  flat_id uuid not null references flats(id),
  raised_by uuid not null references residents(id),
  alert_type text not null check (alert_type in ('medical','fire','theft_security','other')),
  note text,                                             -- optional free text resident can add
  status text not null default 'active' check (status in ('active','acknowledged','resolved','cancelled')),
  acknowledged_by uuid,
  acknowledged_by_role text check (acknowledged_by_role in ('society_admin','guard')),
  acknowledged_at timestamptz,
  resolved_by uuid,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- Audit trail, same pattern as Complaints / Visitors modules
create table sos_alert_status_history (
  id uuid primary key default gen_random_uuid(),
  sos_alert_id uuid not null references sos_alerts(id) on delete cascade,
  from_status text,
  to_status text not null,
  changed_by uuid not null,
  changed_by_role text not null check (changed_by_role in ('resident','society_admin','guard','system')),
  note text,
  created_at timestamptz not null default now()
);

-- notification_queue is REUSED (already exists from Notices / Visitors modules) —
-- new `type` values only: 'sos_alert_raised', 'sos_alert_acknowledged', 'sos_alert_resolved'
```

### Indexes
```sql
create index on emergency_contacts (society_id, category_id, is_active);
create index on emergency_contact_call_logs (society_id, contact_id);
create index on emergency_contact_call_logs (flat_id);
create index on sos_alerts (society_id, status);
```

### RLS
```sql
alter table emergency_contact_categories enable row level security;
alter table emergency_contacts enable row level security;
alter table emergency_contact_call_logs enable row level security;
alter table sos_alerts enable row level security;
alter table sos_alert_status_history enable row level security;

-- Categories & contacts: everyone in a society can READ (global rows + their own society's rows);
-- only that society's admin can WRITE.
create policy read_categories on emergency_contact_categories for select
  using (is_global = true or society_id = (select society_id from residents where id = auth.uid())
         or society_id = (select society_id from society_admin_users where id = auth.uid()));

create policy admin_write_categories on emergency_contact_categories for insert, update, delete
  using (exists (select 1 from society_admin_users sau where sau.id = auth.uid() and sau.society_id = emergency_contact_categories.society_id));

-- (mirror the same read/write split for emergency_contacts)

-- Call logs: resident can INSERT their own (flat_id must match their own flat); 
-- resident can SELECT only their own flat's logs; admin can SELECT all logs for their society.
create policy resident_insert_call_log on emergency_contact_call_logs for insert
  with check (
    caller_type = 'resident' and caller_id = auth.uid()
    and flat_id = (select flat_id from residents where id = auth.uid())
  );

create policy resident_read_own_call_log on emergency_contact_call_logs for select
  using (flat_id = (select flat_id from residents where id = auth.uid()));

create policy admin_read_all_call_logs on emergency_contact_call_logs for select
  using (exists (select 1 from society_admin_users sau where sau.id = auth.uid() and sau.society_id = emergency_contact_call_logs.society_id));

-- SOS: resident can insert/select their own flat's alerts; admin full access scoped to society.
create policy resident_raise_sos on sos_alerts for insert
  with check (raised_by = auth.uid() and flat_id = (select flat_id from residents where id = auth.uid()));

create policy resident_read_own_sos on sos_alerts for select
  using (flat_id = (select flat_id from residents where id = auth.uid()));

create policy admin_full_sos on sos_alerts for all
  using (exists (select 1 from society_admin_users sau where sau.id = auth.uid() and sau.society_id = sos_alerts.society_id));
```

---

## 3. Flows

### Flow A — Admin manages the directory

1. Admin opens **Security → Manage Contacts**.
2. Creates/edits **categories** (name, icon, sort order) — global categories (Police/Ambulance/Fire/Women's Helpline/Disaster Management) are pre-seeded once at platform level (`is_global=true`, `society_id=null`) and appear for every society automatically; admin cannot edit/delete these, only reorder where they sit relative to their own categories.
3. Within a category, admin adds **contacts**: name, designation, phone, optional alternate phone, optional photo, availability text, active toggle.
4. Deactivating a contact (rather than deleting) hides it from the resident view but **keeps its call-log history intact** — this matters for the analytics in Flow C.

### Flow B — Resident views & calls

1. Resident opens **Security** (matches your Image tile — "Emergency contacts").
2. Sees a flat, categorized list: **global numbers pinned at top**, then the society's own categories in admin-defined order, each contact showing name, designation, availability, and a prominent **Call** button.
3. Tapping **Call**:
   - Immediately opens the native dialer via a `tel:` link (no interruption, no confirmation dialog — emergencies shouldn't have friction).
   - **In parallel**, fires a lightweight, non-blocking insert into `emergency_contact_call_logs` (`contact_id`, `flat_id`, `caller_id=self`, `called_at=now()`). This is fire-and-forget — if it fails silently, the call itself is never blocked.
4. Resident can view **My Call History** (their own flat's log only) — mirrors "who did we call and when" for their own reference (e.g., checking when they last called the plumber).

### Flow C — Admin call-log analytics

1. Admin's **Security → Call Logs** dashboard: filterable table (contact, flat, date range).
2. Aggregate views: **most-called contacts this month**, **per-flat call activity**, **calls by category** — useful for spotting an inactive/wrong number (zero calls despite complaints) or a vendor being overused (possible billing conversation).

### Flow D — SOS

1. Resident taps the **SOS button** (placed prominently on the Security screen; a persistent, always-reachable entry point — e.g., also as a small floating action button on Home — is worth considering, flagged in §8).
2. Picks emergency type: **Medical / Fire / Theft & Security / Other**, optionally adds a short note.
3. Confirms → server action `raiseSOSAlert()`:
   - Inserts `sos_alerts` row, `status='active'`.
   - Inserts `sos_alert_status_history` row.
   - Inserts `notification_queue` row(s) targeting **all society_admin_users of that society** (and, once built, all on-duty guards), `type='sos_alert_raised'` — this is the single highest-priority notification type in the whole app.
   - Client shows a "Help is on the way — society management has been alerted" confirmation, with a **Cancel Alert** option (for accidental triggers) that flips status to `cancelled` and notifies admin the alert was a false alarm.
4. Admin's realtime listener treats `sos_alert_raised` as **blocking/interrupt-worthy** — full-screen alert, not a toast, with flat number, resident name, emergency type, and one-tap call-back to the resident.
5. Admin taps **Acknowledge** → `status='acknowledged'`, timestamps who/when — lets the resident see "Admin has seen this and is responding" rather than wondering if the alert went through.
6. Once resolved, admin marks **Resolved** → `status='resolved'`, closes the loop, remains in history for record-keeping.

---

## 4. Real-time notifications (reusing the existing `notification_queue` pattern)

Same Postgres trigger + Supabase Realtime subscription pattern already built for Notices/Visitors — no new infrastructure, just new `type` values:

- `sos_alert_raised` → **blocking, full-screen**, admin panel (and future guard panel).
- `sos_alert_acknowledged` / `sos_alert_resolved` → toast/badge back to the resident who raised it.
- Directory changes (new contact added, contact deactivated) are **not** notification-worthy — the directory is pull, not push.

---

## 5. Screens to build

### Society Admin Panel
1. **Manage Categories** — CRUD + reorder; global categories shown read-only, pinned first.
2. **Manage Contacts** — CRUD within a category: name, designation, phone(s), photo, availability, active toggle, reorder.
3. **Call Logs dashboard** — filterable table + aggregate stats (most-called, per-flat, per-category).
4. **SOS Alerts dashboard** — live list of active alerts (full-screen interrupt on new alert), history of past alerts with acknowledge/resolve timestamps and who handled them.

### User Panel
1. **Security screen** — categorized directory, global numbers pinned at top, tap-to-call contact cards.
2. **SOS button + emergency-type picker + confirmation** (with cancel option).
3. **My Call History** — own flat's call log only.
4. **SOS status view** — "Active — Admin notified" → "Acknowledged — help is on the way" → "Resolved", so the resident isn't left guessing after tapping SOS.

---

## 6. Definition of Done

- Admin can create categories (including seeing pre-seeded global ones), add/edit/deactivate multiple contacts per category with all fields.
- Resident's Security screen renders global + society contacts correctly ordered, tap-to-call opens native dialer.
- Every tap-to-call writes a `emergency_contact_call_logs` row with correct `flat_id`/`caller_id`/`contact_id`/timestamp, without ever blocking or delaying the actual call.
- Admin's Call Logs dashboard correctly filters and aggregates by contact/flat/date.
- Deactivating a contact hides it from residents but its historical call logs remain intact and queryable.
- Resident can raise an SOS with a type (+ optional note); admin receives a **blocking, real-time, full-screen** alert with flat/resident/type; status flow (active → acknowledged → resolved, or → cancelled) works end-to-end and is visible to the resident who raised it.
- All access is correctly scoped by RLS: residents never see another flat's call logs or SOS alerts; admin sees everything within their own society only.
- Schema requires no changes to add a Guard panel later — it just becomes an additional `notification_queue` target and optional `acknowledged_by_role='guard'` actor.

---

## 7. Open items / flagged decisions

- **Call-log accuracy ceiling (important):** we log *call attempts* (tap timestamp), not *actual connects or durations* — reading real call logs would require the invasive `READ_CALL_LOG` Android permission, which is both a privacy concern and against Play Store policy for an app that isn't a dialer/spam-blocker. Recommend proceeding with attempt-logging, which fully answers "which flat called which number and when."
- **SOS button placement:** proposed on the Security screen; worth deciding whether it should *also* live as a persistent floating action on Home (matches NoBrokerHood's pattern of SOS being reachable from anywhere, not buried in a sub-screen) — flagging for your call before I build the nav.
- **Guard escalation timing:** once the Guard panel exists, should SOS notify guards *immediately alongside* admin, or only if admin doesn't acknowledge within a time window (e.g. 60 seconds)? Schema supports either; recommend immediate-to-both for a safety feature — escalation logic can be layered in later without a schema change.
- **False-alarm handling:** currently a resident can self-cancel their own SOS. Worth deciding if repeated false alarms from one flat should be flagged to admin (simple `count(*) where alert_type... and status='cancelled'` query, no schema change needed) — noting as a phase-2 idea, not blocking this build.
