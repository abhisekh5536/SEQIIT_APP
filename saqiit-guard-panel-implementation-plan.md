# Saqiit — Guard Panel (Gate App): Implementation Plan

Scope: **Guard panel**, plus the small **Society Admin** screens needed to manage guards. Resident-side changes are listed only where a guard flow needs them (e.g. "Leave at gate", parcel notifications).

Every earlier module plan (Visitors, Security/SOS, Vehicles) said *"the Guard panel plugs in later"*. This plan is that "later". It reuses those modules' tables and RPCs wherever possible.

> **Status (28 Sep 2026): Phase 0 and Phase 1 are implemented.** See §10 for what shipped, how to deploy it, and what is still open. Phases 2–4 are not started.

---

## 0. Current state: is the guard panel built?

**No, not as a panel. About 30% exists.** A guard account can log in and gets a gate-first home screen, but it runs on the admin's screens, has security holes, and is missing most of what a guard does in a shift.

### What already exists

| Piece | Where | Status |
|---|---|---|
| Guard role detection (`isGuard`) | `lib/services/app_session.dart:184`, reads `user_metadata.role = 'guard' \| 'security'` | ✅ works, but insecure (see P0-1) |
| SQL helper `is_guard_or_admin(society_id)` | `supabase/11_vehicles_parking_module.sql:54` | ✅ used by all gate RLS/RPCs, but insecure (see P0-1) |
| Guard bottom nav: Home · Notices · **Gate** · Settings | `lib/screens/main_shell.dart` | ✅ |
| Guard home tiles: Gate check · Visitors · Emergency · Notices | `lib/screens/home_screen.dart:59` | ✅ |
| Vehicle plate lookup + entry/exit log + today's gate register | `lib/screens/vehicles/guard/vehicle_gate_lookup_screen.dart` | ✅ |
| Log walk-in visitor → resident approves/denies (live) | `admin_log_visitor_screen.dart` (admin screen reused) | ✅ works for guard |
| Verify pre-approval code | `admin_verify_preapproval_screen.dart` (admin screen reused) | ✅ works for guard |
| Visitor check-in / check-out | RPCs in `supabase/15_security_hardening.sql` | ✅ guarded by `is_guard_or_admin` |
| Guard RLS on visitors: read, create gate request, check-in/out, **cannot approve/deny** | `supabase/14_guard_gate_access.sql` | ✅ |
| Realtime visitor approval events to the gate | `supabase/13_realtime_approvals.sql`, `VisitorsService.initRealtime` | ✅ |

### P0: security holes to fix before building anything else

**P0-1. Any user can make themselves a guard of any society.**
Guard status is read from `user_metadata`. In Supabase, a signed-in user can change their own `user_metadata` with `auth.updateUser(UserAttributes(data: {'role': 'guard', 'society_id': '<uuid>'}))`. Society IDs are readable by every signed-in user (`05_resident_join_requests.sql:83`, `using (status = 'active')`, which the join screen needs). So any resident, or any stranger who signs up, can become a guard of any society and then:
- read every visitor's name, phone and photo in that society (migration 14),
- look up any plate and get the owner's name and phone,
- send fake "visitor at gate" requests to any flat.

Fix: guard identity must come from a table only admins can write (`society_guards`, §3.1), not from `user_metadata`. `app_metadata` also works (only the service role can write it), but it can't be managed from the app without an Edge Function, so a table is the better fit here.

**P0-2. `lookup_vehicle_by_plate` has no authorization check.**
`supabase/11_vehicles_parking_module.sql:466` is `security definer` and granted to `authenticated`, and it never checks the caller. It returns `resident_name` and `resident_phone` for any plate in any society. Migration 15 fixed the other four gate functions but missed this one. Fix: add `if not public.is_guard_or_admin(p_society_id) then return ...` at the top, like `log_vehicle_entry`.

**P0-3. `create_visitor_entry` has no authorization check and records the wrong role.**
`supabase/09_visitors_module.sql:295` checks only that the caller is signed in. Anyone can create a pending gate request for any flat in any society, which sends a push "Visitor at Gate" to real residents. It also hardcodes `created_by_type = 'society_admin'` and `changed_by_role = 'society_admin'`, so every guard entry is recorded in the audit trail as an admin entry. The Dart fallback does the same (`lib/services/visitors_service.dart:441`, `:462`, `:712`, `:748`). Fix: require `is_guard_or_admin`, and use `caller_gate_role()` (already in migration 15) for both columns.

### Functional gaps

| # | Gap | Evidence |
|---|---|---|
| G-1 | **Guards never see SOS alerts.** RLS lets only admins and the resident's own flat read `sos_alerts`. `acknowledge_sos_alert` and `resolve_sos_alert` are admin-only. The home popup only fires for admins. Meanwhile the resident SOS button says *"Instant alert to Guards & Admin"*, which is false today. | `10_security_emergency_module.sql:227`, `:439`, `:516`; `home_screen.dart:299`; `security_root_screen.dart:393` |
| G-2 | **No way to create or remove a guard.** No `guards` table and no admin screen. Someone has to run `auth.admin.updateUserById` by hand. A guard who leaves the job can't be switched off from the app. | `14_guard_gate_access.sql:20` |
| G-3 | **Guards can't receive notifications.** `notifications.target_role` only allows `resident`, `society_admin`, `all`. | `07_notifications.sql:14` |
| G-4 | **Guards can't see society emergency contacts.** They see only the global ones (Police, Fire, …). `is_society_member()` counts only admins and residents. | `10_security_emergency_module.sql:156`, `01_residents_migration.sql:129` |
| G-5 | **Guard sees resident-only buttons.** Approve/Deny appears on a pending visitor for the guard (the server then rejects the tap). | `visitor_detail_screen.dart:114` |
| G-6 | **Guard home shows fake resident cards.** The hero carousel shows hardcoded "Gate pass GP-4471", "Community Hall booking", "Request #C-118 Plumbing". | `home_screen.dart:620–660` |
| G-7 | **Guard runs on the admin visitor dashboard**, which is built for reviewing history rather than working the gate: no "expected today" list, no "waiting for resident" timer, no "inside now" list. | `visitors_root_screen.dart:25` |
| G-8 | Profile shows the guard as "Member". There's no shift, gate or duty status anywhere. | `profile_screen.dart:266` |
| G-9 | **Not built at all:** parcels, daily-help attendance (`/staff` is a placeholder, `main.dart:144`), guard shifts/attendance, patrol, incident reports, overstay alerts, blocked visitors, multiple gates, offline mode. | — |

---

## 1. Research: what comparable apps give the guard

Sources: Play Store listings and screenshots, help-centre articles and product pages for **MyGate** (guard app `com.mygate.guardapp.byod`), **NoBrokerHood**, **ADDA GateKeeper** (`com.threefiveeight.addagatekeeper`), **ApnaComplex/ANACITY Gatekeeper** (`com.apnacomplex.visitor`) and **JioGate Society Guard** (`com.jio.jiogate.jiosociety.guard`). Links are at the end of this section.

### 1.1 What the guard's screen looks like in each app

- **MyGate:**
  - The home screen *is* a big number keypad for typing a visitor's 6-digit code. About 70% of the screen is numbers, because many guards have little formal schooling.
  - Top tabs: Enter Code · Frequent Visitor · Visitor · Notice.
  - Bottom row: Guest · Delivery · Cab · More.
  - The Visitor tab has two lists:
    - **Waiting:** entries waiting for the resident, with call and message buttons.
    - **Inside:** photo, name, flat, minutes inside, and a red OUT button.
  - Comes in 9+ languages and works offline.
- **ADDA GateKeeper:**
  - Tabs: Visitor · Staff · Parcel · Clubhouse · More.
  - The Visitor tab has an Entry · Waiting · Exit switch, a "Visitor code" box, category tiles (Delivery, Service, Cab, Guest, Others), and floating Scan QR and Report incident buttons.
  - Each guard has a passcode, and the app locks itself after a few minutes of no use.
- **ApnaComplex:** a grid of tiles on the home screen:
  - Visitor
  - Staff
  - Search pass
  - Expected visitor
  - Member directory
  - School bus
  - Attendance
  - Water tanker
- **JioGate** (the closest to what we're building):
  - Login with phone OTP, then a PIN at the start of every shift, and a selfie so the society knows who is on duty.
  - The admin creates guard accounts; guards can't register themselves.
  - Home screen: gate selector, an "On duty: <name>" chip, tiles for Visitor · Delivery · Daily help, and an "Enter 6-digit code" box.
  - Bottom tabs: Home · Activity log · Me.

### 1.2 How a walk-in visitor works in every app

1. Guard picks a category, then takes a photo and enters name, flat and vehicle. The visitor's phone number is now **optional** in MyGate.
2. Resident gets a push: **Approve · Deny · Leave at gate**.
3. If nobody answers (ADDA waits **55 seconds**), an automatic phone call (IVR) goes to the flat's first number, then the second.
4. If there's still no answer, the guard calls the flat directly. In MyGate the guard can then **allow or deny by hand, and that is recorded** in a report the admin can see.
5. The guard keeps logging other visitors while earlier ones wait (a "waiting" list).
6. A delivery can go to **several flats at once**, and the first flat to answer decides.

### 1.3 Features by how common they are

| How common | Features |
|---|---|
| **Every app has these** | Separate guard screens · photo + flat + push approval · code entry for pre-approved visitors · daily help entry/exit with a code · "Inside" list with checkout · delivery to several flats · regional languages · multiple gates · offline entry |
| **Most apps have these** | Waiting list · automatic call (IVR) when the resident doesn't answer · calling residents **without seeing their number** · QR scan · autofill for repeat visitors · full-screen **SOS siren** on the guard phone · QR patrol checkpoints with location check · incident reports · parcels ("Leave at gate" + pickup code) · overstay alarm · material in/out pass · number-plate camera / RFID gate barrier |
| **Only one or two apps** | Guard PIN per shift + selfie (JioGate) · search a vehicle by the **last 4 digits** and call the owner (MyGate) · face match for maid attendance · child exit permission · guard-to-guard push-to-talk (NoBrokerHood) · level-by-level SOS escalation (ADDA) · Swiggy/Zomato/Blinkit integration |
| **Weak or missing in all of them** | **Blocking a visitor in the app** (MyGate's own help centre says it isn't supported; staff are told manually instead) · a **panic button for the guard** · shift login with selfie (only JioGate) |

### 1.4 What guards are **not** allowed to see (the same across all apps)

- **Resident phone numbers are hidden:**
  - MyGate: "hidden to all… even on intercom calls".
  - ADDA: its SOS screen shows `+91 XXXXX XXXXX`.
  - NoBrokerHood and JioGate: calls go through the app, not the phone number.
- **No money, dues, complaints, polls or documents** in any guard app.
- **Guard phones don't keep data.** MyGate and NoBrokerHood supply locked phones that run only the guard app.
- **Visitor data is deleted after a while.** MyGate deletes it after 60 days; the society can extend this to 180.
- ADDA took phone numbers and ID proofs out of admin list views and exports in Feb 2026.
- Only admins can add maids, drivers and other daily help (ADDA requires police verification first). Only admins can create guard accounts (JioGate).

### 1.5 Decisions for Saqiit based on this

| Feature | Decision |
|---|---|
| Walk-in, pre-approval code, Inside list + checkout | ✅ Phase 1. Mostly built already; needs a guard-first screen. |
| Code box at the **top** of the guard home screen | ✅ Phase 1. This is what guards do most often. |
| Waiting list with "call flat" after 60 s | ✅ Phase 1 (logged call). An automatic IVR call → Phase 4, because it needs a paid calling service. |
| Guard approves by hand after calling the flat | ✅ Phase 1, only through a logged RPC (see Flow G2 and §9). |
| SOS full-screen siren on guard phone | ✅ Phase 1. The resident SOS screen already promises it. |
| Admin-created guard accounts | ✅ Phase 0/1 |
| Parcels / Leave at gate · delivery to several flats · repeat-visitor autofill · overstay alarm · multiple gates · QR scan | ✅ Phase 2 |
| **Blocking visitors in the app** and a **guard panic button** | ✅ Phase 2. Most competitors don't have these, so they set Saqiit apart. |
| Vehicle search by **last 4 digits** | ✅ Phase 2. Small change to the existing plate lookup. |
| Daily help code entry | ✅ Phase 3. Every competitor has it, so don't push it beyond Phase 3. |
| Shift PIN + selfie, Hindi and other languages | ✅ Phase 3 |
| Patrol checkpoints, incidents, offline queue, locked-phone/tablet mode, hidden-number calls through a calling service, number-plate camera, material pass, child exit | Phase 4 |

<details><summary>Sources</summary>

- MyGate guard app: https://play.google.com/store/apps/details?id=com.mygate.guardapp.byod
- MyGate IVR fallback: https://help.mygate.in/articles/133747-why-am-i-not-getting-call-notifications-for-visitor-entry
- MyGate Leave at Gate: https://help.mygate.in/articles/133767-what-is-the-leave-at-gate-module-and-how-does-it-work-in-mygate
- MyGate: blocking visitors not supported: https://help.mygate.in/articles/134068-how-can-i-block-a-visitor
- MyGate overstay alert: https://mygate.com/blog/feature-in-focus/overstay-alert/
- MyGate vehicle owner search: https://mygate.com/blog/feature-in-focus/call-vehicle-owners-from-guard-app/
- MyGate patrolling: https://adminfaq.mygate.com/articles/128299-what-is-the-guard-patrolling-feature-and-how-does-it-work
- MyGate data privacy: https://mygate.com/data-privacy/
- MyGate guard UI design: https://inc42.com/startups/how-mygate-is-making-apartment-living-secure-in-indian-cities/
- NoBrokerHood features: https://www.nobrokerhood.com/solutions/nobrokerhood-features
- NoBrokerHood SOS: https://www.nobrokerhood.com/blog/keep-your-safety-worries-at-bay-with-nobrokerhoods-sos-button/
- NoBrokerHood GuardTalky: https://www.nobrokerhood.com/blog/improving-guard-efficiency-with-the-right-tools-nobrokerhood-guardtalky/
- ADDA GateKeeper: https://play.google.com/store/apps/details?id=com.threefiveeight.addagatekeeper
- ADDA approval timeouts: https://support.adda.io/portal/en/kb/articles/what-types-of-notifications-are-available-for-visitor-entry-approvals-on-the-adda-app
- ADDA panic alert: https://support.adda.io/portal/en/kb/articles/what-is-panic-alert-how-do-i-raise-one-using-the-adda-app
- ApnaComplex Gatekeeper: https://play.google.com/store/apps/details?id=com.apnacomplex.visitor
- JioGate Society Guard: https://play.google.com/store/apps/details?id=com.jio.jiogate.jiosociety.guard

</details>

---

## 2. What the guard can and cannot see

Rule of thumb from every app studied: **the guard sees who is at the gate and which flat they're for. The guard does not see how residents live, what they pay, or what they complain about.**

### 2.1 Allowed

| Data | Guard can | Guard cannot |
|---|---|---|
| **Visitors** | See today's visitors and the last 7 days; log a walk-in; verify a code/QR; check in and check out; call the flat if nobody answers | Approve or deny for a resident; edit or delete a visitor; see visitors older than 7 days (admin can) |
| **Expected visitors** (pre-approvals) | See today's list: name, flat, time window, category. Not the code; the visitor must show it. | See the approval code in the list |
| **Flats & residents** | Flat picker (block → flat); resident **first name + flat** to confirm "who am I calling" | See the resident directory, family members, email, Aadhaar, owner/tenant type, move-in data |
| **Resident phone** | Tap "Call flat" → the app gets the number through an RPC that logs the call, and dials it. The number isn't shown on screen. | See or copy phone numbers in any list |
| **Vehicles** | Plate lookup → registered or not, flat, make/model/colour, parking slot; log entry and exit | See RC photos; edit vehicles; see bay requests or allocation history |
| **Parcels** | Log a parcel at the gate, notify the flat, hand it over | — |
| **Daily help** | Search staff by name/code, see photo and linked flats, mark in/out | Edit staff records or ratings |
| **SOS** | See **all active SOS alerts in the society** (flat, type, time, resident name); acknowledge; mark "reached flat"; resolve with a note; call the flat | Cancel a resident's alert; see SOS history older than 30 days |
| **Emergency contacts** | Read the society and global lists; tap to call | Add, edit or deactivate contacts |
| **Notices** | Read notices targeted to "All" or to "Staff/Guards" | Create notices; see read/ack statistics |
| **Own shift** | Start/end shift, see own shift history | See other guards' attendance |

### 2.2 Never visible to a guard

Maintenance/dues/payments · complaints & helpdesk · admin approvals & join requests · flats management · the full resident directory · household members · documents, meetings, polls, facility bookings · analytics and reports · other societies' data.

These are all enforced with RLS or RPC checks, not only by hiding UI. §3.4 lists the policy changes.

---

## 3. Schema changes

New migration files, continuing the existing numbering:
`17_guard_identity.sql` (Phase 0) · `18_guard_panel.sql` (Phase 1) · `19_parcels.sql` (Phase 2) · `20_daily_help_and_shifts.sql` (Phase 3).

### 3.1 Guard identity (fixes P0-1)

```sql
create table public.society_guards (
  id              uuid primary key default gen_random_uuid(),
  society_id      uuid not null references public.societies(id) on delete cascade,
  user_id         uuid unique references auth.users(id) on delete set null, -- null until the guard first logs in
  full_name       text not null,
  email           text not null,                  -- used to link the login, same pattern as residents (03_link_fix)
  phone           text not null,
  photo_url       text,
  employee_code   text,                           -- agency badge number
  agency_name     text,                           -- "SIS Security", "In-house"
  default_gate_id uuid,                           -- FK added after society_gates exists
  status          text not null default 'active' check (status in ('active','inactive')),
  created_by      uuid references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint uq_guard_email_per_society unique (society_id, email)
);

create table public.society_gates (
  id          uuid primary key default gen_random_uuid(),
  society_id  uuid not null references public.societies(id) on delete cascade,
  name        text not null,                      -- "Main Gate", "Gate 2 (Service)"
  is_active   boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

alter table public.society_guards
  add constraint fk_guard_default_gate foreign key (default_gate_id)
  references public.society_gates(id) on delete set null;

-- Link user_id by email on insert and on sign-up. Same trigger pattern as
-- link_resident_on_insert in 03_link_fix_and_family.sql.
create or replace function public.link_guard_on_insert() ...
create or replace function public.link_guard_on_signup() ...   -- on auth.users insert

-- Guard identity comes from the table only.
create or replace function public.is_society_guard(p_society_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.society_guards g
     where g.user_id = auth.uid()
       and g.society_id = p_society_id
       and g.status = 'active'
  );
$$;

-- Same signature, so migrations 11/14/15 pick it up without edits.
-- The user_metadata branch is removed.
create or replace function public.is_guard_or_admin(p_society_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_society_admin(p_society_id)
      or public.is_master_admin()
      or public.is_society_guard(p_society_id);
$$;
```

RLS: admin has full CRUD on both tables for their society. A guard can `select` their own `society_guards` row and the society's `society_gates`. Residents get nothing.

Setting `status = 'inactive'` removes a guard's access on their **next request**, because every policy goes through `is_society_guard()`.

### 3.2 Guard panel core (Phase 1)

```sql
-- Notifications can target guards
alter table public.notifications drop constraint notifications_target_role_check;
alter table public.notifications add constraint notifications_target_role_check
  check (target_role in ('resident','society_admin','guard','all'));

-- Which gate a visitor/vehicle used (text entry_gate stays for old rows)
alter table public.visitors           add column gate_id uuid references public.society_gates(id);
alter table public.vehicle_entry_logs add column gate_id uuid references public.society_gates(id);

-- Notices can target staff
--   extend notices.target_type with 'guards' (same pattern as 'all' / block)

-- Every time a guard dials a resident
create table public.guard_call_logs (
  id          uuid primary key default gen_random_uuid(),
  society_id  uuid not null references public.societies(id) on delete cascade,
  guard_id    uuid not null references public.society_guards(id),
  flat_id     uuid not null references public.flats(id),
  resident_id uuid references public.residents(id),
  reason      text check (reason in ('visitor_no_response','parcel','sos','vehicle','other')),
  visitor_id  uuid references public.visitors(id),
  called_at   timestamptz not null default now()
);

-- Blocked visitors (admin-managed; guard sees a warning at entry)
create table public.visitor_blocklist (
  id          uuid primary key default gen_random_uuid(),
  society_id  uuid not null references public.societies(id) on delete cascade,
  phone       text,
  name        text,
  reason      text not null,
  added_by    uuid references auth.users(id),
  created_at  timestamptz not null default now()
);
```

### 3.3 Parcels (Phase 2)

```sql
create table public.parcels (
  id               uuid primary key default gen_random_uuid(),
  society_id       uuid not null references public.societies(id) on delete cascade,
  flat_id          uuid not null references public.flats(id),
  visitor_id       uuid references public.visitors(id),        -- set when it came from a "Leave at gate" delivery
  courier          text,                                       -- "Amazon", "Swiggy Instamart", "Blue Dart"
  description      text,
  photo_url        text,
  pickup_code      text,                                       -- 4 digits, shown to the resident
  status           text not null default 'at_gate'
                     check (status in ('at_gate','collected','returned')),
  received_by      uuid not null references public.society_guards(id),
  received_at      timestamptz not null default now(),
  gate_id          uuid references public.society_gates(id),
  collected_by_name text,
  handed_over_by   uuid references public.society_guards(id),
  collected_at     timestamptz
);
```

### 3.4 Daily help, shifts, patrol, incidents (Phase 3–4)

```sql
create table public.daily_helps (            -- the '/staff' module; residents add their own help
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null references public.societies(id) on delete cascade,
  full_name text not null, phone text, photo_url text,
  help_type text not null check (help_type in ('maid','cook','driver','nanny','car_cleaner','laundry','other')),
  gate_pass_code text unique,                 -- 6 chars, the helper shows it at the gate
  status text not null default 'active' check (status in ('active','inactive','blocked')),
  created_at timestamptz not null default now()
);
create table public.daily_help_flats (help_id uuid references public.daily_helps(id) on delete cascade,
                                      flat_id uuid references public.flats(id) on delete cascade,
                                      primary key (help_id, flat_id));
create table public.daily_help_attendance (
  id uuid primary key default gen_random_uuid(),
  help_id uuid not null references public.daily_helps(id) on delete cascade,
  society_id uuid not null,
  entry_at timestamptz not null default now(), exit_at timestamptz,
  gate_id uuid references public.society_gates(id),
  entry_logged_by uuid references public.society_guards(id),
  exit_logged_by  uuid references public.society_guards(id)
);

create table public.guard_shifts (
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null, guard_id uuid not null references public.society_guards(id),
  gate_id uuid references public.society_gates(id),
  started_at timestamptz not null default now(), ended_at timestamptz,
  start_selfie_url text, end_note text
);

create table public.gate_incidents (
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null, reported_by uuid not null references public.society_guards(id),
  incident_type text not null check (incident_type in ('suspicious_person','altercation','damage','theft','fire','medical','other')),
  description text not null, photo_url text, flat_id uuid references public.flats(id),
  status text not null default 'open' check (status in ('open','reviewed','closed')),
  created_at timestamptz not null default now()
);

-- Phase 4: patrol_checkpoints (QR per checkpoint) + patrol_scans
```

### 3.5 RLS / RPC changes on existing tables

| Object | Change |
|---|---|
| `lookup_vehicle_by_plate` | Add `is_guard_or_admin` check (P0-2). Stop returning `resident_phone`; return `resident_first_name` instead. Calls go through `guard_call_flat`. |
| `create_visitor_entry` | Add `is_guard_or_admin` check; use `caller_gate_role()` for `created_by_type` / `changed_by_role`; accept `p_gate_id`; check the blocklist and return `blocked: true, reason` (P0-3). |
| **new** `guard_call_flat(p_flat_id, p_reason, p_visitor_id)` | Guard-only, `security definer`. Returns the primary active resident's phone and writes a `guard_call_logs` row. |
| **new** `fetch_expected_visitors(p_society_id)` | Today's `pre_approved` + `approved` visitors whose window covers now. Returns name, flat, window, category. **No code.** |
| `sos_alerts` select policy | Add `or public.is_society_guard(society_id)` |
| `acknowledge_sos_alert` / `resolve_sos_alert` | Allow guards; set `acknowledged_by_role` / `changed_by_role` from `caller_gate_role()`; notify admins that "Guard X acknowledged". |
| `raise_sos_alert` | Also insert notifications with `target_role = 'guard'` for on-duty guards (all active guards if shifts aren't built yet). |
| `emergency_contacts`, `emergency_contact_categories` select | Add `or public.is_society_guard(society_id)` (G-4) |
| `notices` select | Guard sees `target_type in ('all','guards')` **for their own society**. |
| `visitors` select for guard | Limit to `created_at > now() - interval '7 days'` or `status in ('approved','checked_in')` |
| `residents`, `complaints`, `resident_join_requests`, dues tables | **No guard policy.** Leaving them out is deliberate; add a comment in the migration saying so, as migration 14 did. |

---

## 4. App structure

### 4.1 A separate `GuardShell`

Stop adding more `if (isGuard)` branches to `MainShell`. After `AppSession.load()`:

```dart
home: !_loggedIn ? const AuthScreen()
    : session.isGuard ? const GuardShell()
    : MainShell(themeController: ...)
```

`AppSession` changes:
- `isGuard` comes from a `society_guards` row (`user_id = auth.uid(), status = 'active'`), **not** metadata.
- New fields: `guardProfile` (name, photo, employee code, default gate), `currentShift`, `currentGate`.
- An inactive guard gets a *"Your gate access has been turned off. Contact the society office."* screen.

### 4.2 Guard bottom nav (4 tabs)

| Tab | Screen | Purpose |
|---|---|---|
| **Gate** | `GuardHomeScreen` | The working screen. Everything that needs action now. |
| **Inside** | `GuardRegisterScreen` | Who is inside right now, and today's log. Visitors · Vehicles · Staff · Parcels segments. |
| **Alerts** | `GuardAlertsScreen` | SOS (active + today), guard-targeted notices, notifications |
| **Me** | `GuardProfileScreen` | Profile, shift start/end, shift history, gate switch, language, theme, logout |

### 4.3 Gate home (`GuardHomeScreen`), top to bottom

1. **Duty bar:** "Ramesh · Main Gate · On duty since 08:02" with a Switch gate / End shift chip.
2. **SOS takeover:** if any SOS is active, a red pinned card that can't be dismissed: *"🚨 MEDICAL · B-204 · 2 min ago"* [Acknowledge] [Call flat]. A new SOS also opens a full-screen dialog with a looping alarm and vibration (reuse `AdminSosAlertDialog`).
3. **Code box first:** a large "Enter visitor / staff code" field with a number keypad and a QR-scan button. Guards use this more than anything else (MyGate makes the keypad the whole home screen).
4. **Action grid (big buttons, one tap each):**
   `Guest` · `Delivery` · `Cab` · `Service` · `Vehicle plate` · `Daily help` · `Parcel` · `Emergency contacts`
5. **Waiting for resident** (live): pending gate requests with a count-up timer. After 60 s a **Call flat** button appears. The row turns green or red as the resident answers (already live through migration 13). The guard can keep logging new visitors while these wait.
6. **Expected today:** pre-approvals active now. Tapping one opens verify with the code field focused.
7. **Inside now** counter → Inside tab. Visitors past their window are highlighted as **overstay**.

Guard UI rules:
- Big touch targets (≥ 56 dp) and icon + text on every button; most guards use the app standing up with one hand.
- Hindi and English (Phase 3). Short labels, few paragraphs.
- Numeric keypad for codes and plates. The camera opens directly with no extra confirm step.
- No hero carousel and no marketing cards (fixes G-6).

### 4.4 Screen list

**Guard panel (new or refactored)**

| Screen | Build | Notes |
|---|---|---|
| `GuardShell` | new | §4.1 |
| `GuardHomeScreen` | new | §4.3 |
| `GuardNewVisitorFlow` | refactor `admin_log_visitor_screen.dart` into a shared widget | Stepper: category → flat → name + phone → photo → vehicle (optional) → Send → **waiting screen** |
| `GuardVerifyCodeScreen` | refactor `admin_verify_preapproval_screen.dart` | Code keypad + QR scanner (`mobile_scanner`) |
| `GuardRegisterScreen` | new | Inside now + today's log, checkout buttons, search by name / flat / plate |
| `VehicleGateLookupScreen` | exists | Move into the Gate flow; route calls through `guard_call_flat` |
| `GuardSosScreen` / dialog | reuse the admin dialog | Acknowledge → "Reached flat" → Resolve with note |
| `GuardParcelsScreen` | new (Phase 2) | Log · pending pickups · hand over with pickup code |
| `GuardDailyHelpScreen` | new (Phase 3) | Search / code → photo → Mark in / Mark out |
| `GuardShiftScreen` | new (Phase 3) | Start shift (gate + selfie), end shift |
| `IncidentReportSheet` | new (Phase 4) | Type, description, photo, optional flat |
| `GuardProfileScreen` | new | Shows "Security Guard · Main Gate", not "Member" |

**Society Admin panel (new)**

| Screen | Purpose |
|---|---|
| `SecurityStaffScreen` | List guards; **Add guard** (name, email, phone, agency, employee code, default gate); deactivate/reactivate; see last shift and entries logged |
| `GatesSettingsSheet` | Add, rename or disable gates |
| `VisitorBlocklistScreen` | Add or remove blocked people (phone/name + reason) |
| `GuardActivityScreen` (Phase 3) | Shift log, entries per guard, SOS response times, call logs, incidents |

**Resident side (small)**

| Change | Phase |
|---|---|
| "Leave at gate" as a third answer for **delivery** gate requests → guard gets a parcel task | 2 |
| "Parcel at gate · code 4821" notification + a Parcels list in My Flat | 2 |
| SOS screen: show "Guard Ramesh acknowledged · 1 min" in the timeline | 1 |
| Daily help: add, share gate code, see attendance ("Sunita arrived 7:58") | 3 |

---

## 5. Flows

### Flow G1: Guard onboarding (admin-created, no service key on the phone)
1. Admin → Security Staff → **Add guard**: name, email, phone, agency, default gate.
2. A `society_guards` row is created with `user_id = null`.
3. The guard installs the app and signs up or logs in with **that email** (existing email/password or OTP flow).
4. The `link_guard_on_signup` trigger (or the insert trigger if the account already existed) fills in `user_id`.
5. `AppSession.load()` finds an active guard row → opens `GuardShell`.
6. Admin deactivates → next request fails RLS → app shows the "access turned off" screen.

> Uses the same email-link method residents already use (`03_link_fix_and_family.sql`), so there's no new infrastructure. Phone-OTP login is Phase 3 and needs an SMS provider in Supabase (§9).

### Flow G2: Unexpected walk-in visitor (guest / service person)
1. Gate → **New visitor** → pick category.
2. Pick block → flat. The guard sees "B-204 · Mr. Sharma (first name only)".
3. Enter name + phone. Blocklist is checked right away; a match shows a red *"Blocked by society: reason"* banner, and only an admin can override.
4. Take a photo (required for guest/service, optional for delivery). Add vehicle number (optional; prefilled if the plate was just looked up).
5. **Send** → `create_visitor_entry` → resident gets a push (existing).
6. **Waiting screen** with a live timer:
   - Resident **approves** → green → **Check in** (one tap) → `check_in_visitor(gate_id)`.
   - Resident **denies** → red → "Ask visitor to leave" → done.
   - **No answer after 60 s** → **Call flat** (`guard_call_flat`, logged). If the resident approves by phone, the guard taps **Approved on call**. The row is marked approved with `approved_via = 'guard_call'` and the call log attached, so the audit trail shows the guard didn't approve it on their own.
   - No answer after 5 min → **Expire** → visitor is turned away.

> ⚠️ "Approved on call" is the one place a guard sets `approved`. It must go through its own RPC that requires a `guard_call_logs` row for that visitor from the last 10 minutes, and it notifies the resident afterwards ("Guard marked Amit approved after calling you"). Otherwise it undermines the rule migration 14 set up. This is flagged in §9.

### Flow G3: Pre-approved visitor (code or QR)
1. Gate → **Enter code** (or tap a row in *Expected today*) → type the 8-character code or scan the QR.
2. `verify_pre_approval` (exists, throttled) → shows name, photo, flat, window, group size.
3. **Check in** → done. The resident gets "Your guest Amit has entered".
4. Group invite: check in the whole group, or count people in (`visitor_group_members`).

### Flow G4: Delivery
1. Gate → **Delivery** → company chips (Amazon, Flipkart, Swiggy, Zomato, Blinkit, Other) → flat.
2. Resident answers **Allow in**, **Leave at gate**, or **Deny**.
3. Leave at gate → a `parcels` row is created (`at_gate`), the resident gets the pickup code, and the delivery person leaves.
4. Allow in → check in; the guard checks them out on exit (15-minute overstay threshold for deliveries).

### Flow G5: Vehicle at the gate (exists, small changes)
1. Gate → **Vehicle plate** → type the full plate, or just the **last 4 digits** (Phase 2; show a pick list if more than one car matches) → `lookup_vehicle_by_plate` (now authorized).
2. Registered → green card (flat, model, slot) → **Log entry**.
3. Not registered → amber card → **Log as visitor vehicle**, which jumps into Flow G2 with the plate prefilled.
4. Exit → Inside tab → Vehicles → **Mark exit** (exists).

### Flow G6: Visitor exit and overstay
1. Inside tab lists everyone checked in, oldest first.
2. Tap → **Check out** (`check_out_visitor`, exists).
3. Overstay: a row turns amber past `valid_until` (pre-approved) or past category thresholds (delivery 15 min, cab 10 min, guest 6 h). Phase 2 adds a scheduled job that also notifies the flat and the admin.

### Flow G7: SOS response
1. A resident raises SOS → `raise_sos_alert` notifies admins **and guards** → realtime channel `public:sos_alerts:<society>` (exists) → a guard device now receives it because RLS allows it.
2. The guard sees a full-screen alarm: type, flat, resident name, time → **Acknowledge** (`acknowledge_sos_alert`, now guard-allowed). The resident sees "Guard Ramesh is on the way".
3. **Call flat** (logged) / **Reached flat** (status note).
4. **Resolve** with a note. The admin sees the full timeline and response time.
5. The alert stays pinned on the guard home until it's resolved or cancelled.

### Flow G8: Parcel handover (Phase 2)
1. Gate → **Parcel** → flat → courier → photo → Save → resident gets "Parcel at gate · code 4821".
2. Resident or family comes to the gate → guard opens Parcels → pending → enters the code or taps the flat → **Hand over** (name of who collected).

### Flow G9: Daily help (Phase 3)
1. Helper arrives → guard enters their gate code or searches by name → photo, name and flats shown → **Mark in**.
2. Linked flats get "Sunita (maid) arrived 7:58". **Mark out** on exit.
3. A helper marked `blocked` shows red and can't be marked in.

### Flow G10: Shift (Phase 3)
1. Opening the app with no open shift → "Start shift" sheet: pick gate, take a selfie → `guard_shifts` row.
2. All entries in the shift carry `gate_id` from the shift.
3. **End shift** → optional handover note ("Parcel for C-101 still at gate").

---

## 6. Build phases

| Phase | Contents | Size |
|---|---|---|
| **0: Security fixes** (before anything else) | `17_guard_identity.sql`: `society_guards`, `society_gates`, link triggers, new `is_society_guard` + `is_guard_or_admin` (no metadata). Authorize `lookup_vehicle_by_plate` and `create_visitor_entry`; use real role attribution. `AppSession.isGuard` reads the table. Remove the metadata branch in Dart. | S |
| **1: Guard panel MVP** | `GuardShell` + 4 tabs; `GuardHomeScreen` (SOS card, action grid, waiting list, expected today); refactor log-visitor and verify-code into shared widgets; waiting screen with call fallback; `guard_call_flat`; SOS for guards (RLS + ack/resolve + alarm dialog); notifications `target_role = 'guard'`; emergency contacts for guards; hide Approve/Deny and fake hero cards; admin **Security Staff** + **Gates** screens. | L |
| **2: Gate operations** | Parcels + "Leave at gate"; QR scanning; one delivery sent to **several flats** (first answer decides); autofill for repeat visitors by phone; plate search by last 4 digits; overstay highlighting + scheduled alert; visitor blocklist; **guard panic button** (alerts admin + other guards); `gate_id` on visitors/vehicles; guard-targeted notices. | M |
| **3: Staff & attendance** | Daily help module (resident + guard sides, fills the `/staff` placeholder); guard shifts + selfie; admin guard activity report; Hindi; phone-OTP login. | L |
| **4: Advanced** | Patrol checkpoints (QR + location check), incident reports, offline queue for entries, shared gate-tablet mode with guard PIN, automatic IVR call + hidden-number calling through a telephony provider (Exotel / Knowlarity), number-plate camera (ANPR), material in/out pass, child exit permission. | L |

---

## 7. Definition of Done (Phase 0 + 1)

- [ ] A user who sets `user_metadata.role = 'guard'` on themselves gets **no** guard access (test with a resident account and a stranger account).
- [ ] `lookup_vehicle_by_plate` returns *Permission denied* to a resident and to a guard of another society.
- [ ] `create_visitor_entry` returns *Permission denied* to a resident; a guard's entry is stored with `created_by_type = 'guard'`.
- [ ] Admin can add a guard by email. The guard signs up and lands on `GuardShell`. Admin deactivates them and the next action fails with the "access turned off" screen.
- [ ] The guard never sees Approve/Deny, resident phone numbers in any list, dues, complaints, the directory or admin approvals, even by typing a route like `/directory` or `/complaints`.
- [ ] Walk-in: log → resident approves on another phone → guard's waiting screen turns green in < 2 s without a refresh → check in → check out. Every step appears in `visitor_status_history` with role `guard`.
- [ ] No answer for 60 s → Call flat → a `guard_call_logs` row is written.
- [ ] Resident raises SOS → guard phone shows the alarm in < 3 s → guard acknowledges → resident sees "Guard X acknowledged" → guard resolves → admin sees the full timeline.
- [ ] Guard sees society-specific emergency contacts.
- [ ] `flutter analyze` is clean. `test/security_hardening_test.dart` gets the same static checks for `lookup_vehicle_by_plate`, `create_visitor_entry`, `guard_call_flat`, and for `is_guard_or_admin` no longer reading `user_metadata`.

---

## 8. Files touched (Phase 0 + 1)

| File | Change |
|---|---|
| `supabase/17_guard_identity.sql` | new |
| `supabase/18_guard_panel.sql` | new |
| `lib/services/app_session.dart` | guard from `society_guards`; `guardProfile`, `currentGate` |
| `lib/main.dart` | route to `GuardShell`; guard gate on admin-only and resident-only routes |
| `lib/screens/guard/` | new folder: shell, home, register, alerts, profile, waiting screen |
| `lib/screens/visitors/admin_log_visitor_screen.dart`, `admin_verify_preapproval_screen.dart` | pull the body into shared widgets used by admin and guard |
| `lib/screens/visitors/visitor_detail_screen.dart` | hide Approve/Deny unless the viewer is the flat's resident |
| `lib/screens/home_screen.dart`, `main_shell.dart` | remove guard branches (moved to `GuardShell`) |
| `lib/services/visitors_service.dart` | remove hardcoded `'society_admin'` roles; `guardCallFlat`, `fetchExpectedVisitors` |
| `lib/services/security_service.dart` | guard can ack/resolve; `caller_type` from real role |
| `lib/screens/security/…` | guard SOS dialog reuse |
| `lib/screens/admin/security_staff_screen.dart` | new |
| `lib/models/guard_models.dart` | new: `GuardProfile`, `SocietyGate`, `GuardCallLog` |

---

## 9. Open decisions

1. **Guard login method.** MVP links by email, like residents. Many guards don't have an email address. Options: (a) admin creates a society email per guard (`gate1@yoursociety.in`), (b) phone OTP, which needs an SMS provider (MSG91 / Twilio) set up in Supabase Auth and costs per SMS, (c) shared gate tablet signed in once, with each guard entering a 4-digit PIN. Recommendation: (a) for Phase 1, (c) in Phase 4.
2. **"Approved on call"** (Flow G2). Every major app allows it, since residents often answer the phone and not the push. It's the one exception to "guards never approve". Recommendation: allow it only through the logged-call RPC described in Flow G2, and notify the resident afterwards.
3. **Showing resident phone numbers.** The plan never shows the number on screen, but after dialing it's in the phone's call log. Real masking needs a telephony provider (Exotel / Knowlarity click-to-call) → Phase 4. Is the "logged dial" approach enough for now?
4. **How long guards can look back.** The plan says 7 days of visitors and 30 days of SOS. Societies may want less (privacy) or more (investigations; the admin keeps full history either way).
5. **Who resolves SOS.** The plan lets the guard resolve with a note. Some committees want only an admin to close an SOS. If so, the guard gets Acknowledge and Reached flat only.
6. **One app or a separate guard app.** This plan keeps one app with a `GuardShell`, which is less to maintain and ship. A separate "Saqiit Gate" build (tablet-first, kiosk mode) only makes sense in Phase 4.

---

## 10. Implementation status: Phase 0 + 1 (28 Sep 2026)

### Deploy

1. In the Supabase SQL editor, run `supabase/check_applied_migrations.sql`. It's read-only.
   - Run any migration it reports as **MISSING**, in number order.
   - Then run `supabase/17_guard_identity.sql` and `supabase/18_guard_panel.sql` last, even if they're already applied. Both are safe to re-run, and running them last makes their guard rules override the older ones from 14.
   - Migration 15 matters most. It closes other gate security holes. If it's missing, the gate app used to fail with `function public.caller_gate_role(uuid) does not exist`; 17 now re-creates that function, but 15's other fixes still only come from running 15.
2. **Guards set up the old way stop working at once.** Any account that was made a guard with `user_metadata.role = 'guard'` loses guard access. That is the fix. Re-add them: Admin → Settings → **Guards & Gates** → Add guard, using the email they sign in with.
3. On the same screen, add at least one gate (e.g. "Main Gate").

### What shipped

| Area | Where |
|---|---|
| Guard identity from `society_guards` (P0-1); `society_gates`; email linking on sign-up | `supabase/17_guard_identity.sql`, `lib/services/app_session.dart` |
| `lookup_vehicle_by_plate` authorized; guards get the owner's first name, not the phone (P0-2) | migration 17 |
| `create_visitor_entry` authorized, flat must be in the same society, real role recorded (P0-3) | migration 17 |
| Notifications to guards; `guard_call_flat` (logged, throttled); `guard_resolve_gate_request`; `fetch_expected_visitors` (no codes); guards can see, acknowledge, note and resolve SOS; society emergency contacts visible to guards | `supabase/18_guard_panel.sql` |
| Guard app: Gate · Inside · Alerts · Me, plus the waiting screen and the "access turned off" screen | `lib/screens/guard/` |
| Admin: Guards & Gates screen | `lib/screens/admin/security_staff_screen.dart` |
| Routing: guards get `GuardShell`; resident and office routes are blocked for guards | `lib/main.dart` |

### Fixed along the way (beyond the plan)

- **Repeat SOS taps failed.** Migration 15's dedupe trigger made a second SOS tap return an error instead of a confirmation. `raise_sos_alert` now handles the skipped insert.
- **Current pass codes couldn't be typed.** The verify screen took only 6 digits, but migration 15 changed codes to 8 letters and digits.
- **Server refusals were retried as direct table writes.** A refused visitor RPC made the client retry the same action straight on the table. An admin tapping Approve could get through that way, and the "too many attempts" limit on code checks could be bypassed. The client now falls back only when the RPC doesn't exist.
- **Guards could edit any column of a visitor.** They could update approved or checked-in visitor rows directly, e.g. change the name or flat. That policy is dropped; guards now change visitors only through RPCs.
- **Guards could fake audit entries.** A guard could add status-history rows claiming a resident made the change. Guards can now only add rows recorded as `guard` under their own user id.
- **SOS listening leaked across sign-ins.** The SOS listener subscribed once per app run and kept the previous society's channel after sign-out.

### Tests

- `test/guard_panel_sql_test.dart`: static checks on migrations 17 and 18, same style as `security_hardening_test.dart`.
- `test/guard_models_test.dart`: guard models, overstay rules, `approved_via`.
- `test/guard_shell_test.dart`: gate home, the four tabs, and a 320 px narrow-phone layout.
- Both migrations were parsed with libpg_query (pglast). They have not been run against a live database. That still has to be done on staging, using the checklist in §7.

### Still open

- **Guards can still read `visitors.approval_code` through the API.** The app never shows it to them. This doesn't give a guard any new power, since `check_in_visitor` works without the code. Hiding the column properly needs a view.
- **The dialled number stays in the guard phone's call log.** Real masking needs a calling service (Phase 4).
- **Not built yet:** parcels, blocklist, overstay alerts from the server, guard panic button, daily help, shifts, patrolling, offline mode, Hindi. These are Phases 2–4.
