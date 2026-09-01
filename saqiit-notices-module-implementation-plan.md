# Implementation Plan — Saqiit Notices / Announcements Module

Stack: Next.js (App Router) + Supabase. Matches your existing panel structure — Society Admin creates/manages, Resident (User panel) views/receives.

---

## What "professional" means here (research-informed additions)

Beyond a basic "post a message" board, real society-management notice systems need:

1. **Scheduling** — admin can write a notice today for a water-shutdown next Tuesday, and it publishes itself at the right time without anyone remembering to click a button
2. **Expiry** — a notice about "meeting this Sunday" shouldn't clutter the feed forever; it should auto-archive
3. **Pinning** — a genuinely urgent notice (fire drill, security alert) should stay at the top even if newer, less important notices get posted after it
4. **Categorization with visual distinction** — your screenshots already show this instinct (Important/Event/Safety badges) — formalize it
5. **Read acknowledgment for critical notices** — for safety/compliance-relevant notices, the admin should be able to see *who has actually seen it*, not just that it was posted. This is the difference between "we posted a notice" and "we can prove residents were informed" — genuinely useful for a committee.
6. **Targeting** — not every notice is for the whole society (e.g., "Block A water shutdown" shouldn't notify Block B/C residents)
7. **Draft state** — admin should be able to write a notice, preview it, and not have it go live until they're ready

---

## Database Schema

```sql
create table notices (
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null references societies(id) on delete cascade,
  title text not null,
  body text not null,
  category text not null default 'general' check (category in
    ('important', 'event', 'safety', 'maintenance', 'billing', 'general')),
  attachment_url text, -- optional image/PDF via Supabase Storage

  target_type text not null default 'all' check (target_type in ('all', 'block')),
  target_block_id uuid references blocks(id), -- null when target_type = 'all'

  -- Event-specific fields — separate from publish_at/expires_at on purpose.
  -- publish_at/expires_at control when the NOTICE is visible in the feed.
  -- event_starts_at/event_ends_at is WHEN THE EVENT ITSELF happens
  -- (e.g. Janmashtami celebration, 6:00 PM–8:00 PM on a specific date).
  -- A notice can exist without being an event (e.g. a maintenance notice),
  -- so these stay nullable and are only required when is_event = true.
  is_event boolean default false,
  event_starts_at timestamptz,
  event_ends_at timestamptz,
  event_venue text, -- optional, e.g. "Community Hall" / "Clubhouse Lawn"

  is_pinned boolean default false,
  requires_acknowledgment boolean default false,

  status text not null default 'draft' check (status in
    ('draft', 'scheduled', 'published', 'expired', 'archived')),

  publish_at timestamptz not null default now(), -- when it should go live
  expires_at timestamptz, -- nullable — null means never auto-expires

  created_by uuid not null references society_admin_users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),

  constraint event_fields_required check (
    not is_event or (event_starts_at is not null and event_ends_at is not null)
  ),
  constraint event_end_after_start check (
    event_ends_at is null or event_starts_at is null or event_ends_at > event_starts_at
  )
);

-- Read tracking (for "seen by 34/50 residents" analytics)
create table notice_reads (
  id uuid primary key default gen_random_uuid(),
  notice_id uuid not null references notices(id) on delete cascade,
  resident_id uuid not null references residents(id) on delete cascade,
  read_at timestamptz default now(),
  unique (notice_id, resident_id)
);

-- Explicit acknowledgment — separate from "read", since read = opened it,
-- acknowledged = tapped "I understand / Confirm" on a mandatory notice
create table notice_acknowledgments (
  id uuid primary key default gen_random_uuid(),
  notice_id uuid not null references notices(id) on delete cascade,
  resident_id uuid not null references residents(id) on delete cascade,
  acknowledged_at timestamptz default now(),
  unique (notice_id, resident_id)
);

create index idx_notices_society_status on notices(society_id, status);
create index idx_notices_publish_at on notices(publish_at);
create index idx_notices_event_starts_at on notices(event_starts_at) where is_event = true;
```

### RLS Policies

```sql
alter table notices enable row level security;
alter table notice_reads enable row level security;
alter table notice_acknowledgments enable row level security;

-- Society Admin: full control over their own society's notices
create policy "society admins manage own notices"
  on notices for all
  using (society_id = (select society_id from society_admin_users where id = auth.uid()));

-- Residents: can only see PUBLISHED notices targeted at them (all, or their own block)
-- that haven't expired yet
create policy "residents view published notices for their scope"
  on notices for select
  using (
    status = 'published'
    and publish_at <= now()
    and (expires_at is null or expires_at > now())
    and (
      target_type = 'all'
      or target_block_id = (
        select b.id from residents r
        join flats f on f.id = r.flat_id
        join blocks b on b.id = f.block_id
        where r.id = auth.uid()
      )
    )
  );

-- Read/ack tracking: residents write their own, admins read all for their society
create policy "residents mark own reads"
  on notice_reads for insert
  with check (resident_id = auth.uid());

create policy "residents view own reads"
  on notice_reads for select
  using (resident_id = auth.uid());

create policy "society admins view read stats"
  on notice_reads for select
  using (
    notice_id in (
      select id from notices where society_id =
        (select society_id from society_admin_users where id = auth.uid())
    )
  );

create policy "residents mark own acknowledgment"
  on notice_acknowledgments for insert
  with check (resident_id = auth.uid());

create policy "society admins view acknowledgment stats"
  on notice_acknowledgments for select
  using (
    notice_id in (
      select id from notices where society_id =
        (select society_id from society_admin_users where id = auth.uid())
    )
  );
```

---

## Event Notices — how this works end to end

When the admin toggles **"This is an event"** on a notice (auto-suggested when category = Event, but not forced — a "Board elections" notice might be an event too, for example), the create form reveals:
- **Event date** (date picker)
- **Start time** / **End time** (time pickers — e.g. 6:00 PM–8:00 PM)
- **Venue** (optional free text, e.g. "Community Hall")

This produces `event_starts_at` / `event_ends_at` as combined date+time values. Keep this visually distinct from *when the notice publishes* — a common real pattern is: admin publishes the notice a week in advance (`publish_at` = today), but the event itself is next Saturday (`event_starts_at` = next Saturday 6 PM). Don't let these two collapse into one field; that's the mistake that would make this feature confusing.

**Nice, low-effort touches worth including:**
- **Auto-suggest `expires_at`** as the day *after* `event_starts_at` when creating an event notice (editable, not forced) — so a Janmashtami notice naturally falls out of the active feed once the celebration has happened, without the admin needing to remember to archive it
- **Display format**: show event notices with a distinct card treatment — a small calendar-style date block + "6:00 PM – 8:00 PM" + venue, rather than just burying the time in the body text. This is what makes it read as an actual event listing rather than a text announcement that happens to mention a time.
- **Optional reminder**: if you want to go further, a second scheduled notification 1 day before `event_starts_at` ("Reminder: Janmashtami celebration tomorrow, 6–8 PM") is a nice-to-have — implement it as a second row type in the same `notification_queue` mechanism below, not a separate system. Treat as a fast-follow, not required for launch.

---

## Scheduling — the one genuinely tricky technical piece

A notice created now with `publish_at` set to a future time needs *something* to flip its status from `scheduled` → `published` when that time arrives — nothing does this automatically just by sitting in the database. Two options:

**Option A (recommended): Supabase `pg_cron` extension**
Enable `pg_cron` in your Supabase project, then schedule a small SQL job to run every few minutes:
```sql
select cron.schedule(
  'publish-due-notices',
  '*/5 * * * *', -- every 5 minutes
  $$
  update notices
  set status = 'published'
  where status = 'scheduled' and publish_at <= now();

  update notices
  set status = 'expired'
  where status = 'published' and expires_at is not null and expires_at <= now();
  $$
);
```
This is simple, runs inside the database, and needs no external infrastructure.

**Option B: Supabase Edge Function on a schedule**
Same logic, but as a Deno Edge Function triggered by Supabase's cron scheduler — better if you want to *also* trigger a push notification at the exact moment of publishing (Option A can't send a push notification by itself, just update rows; you'd still need something to notice the row changed and act on it — a Postgres trigger or a periodic check).

**Recommendation:** Use `pg_cron` (Option A) for the status flip, and add a Postgres trigger on `notices` that fires whenever a row's `status` changes to `published` (whether by immediate publish or by the cron job) to enqueue the actual notification. This way "immediate publish" and "scheduled publish" both go through the exact same notification path — one code path, not two.

```sql
create or replace function notify_on_notice_published()
returns trigger as $$
begin
  if new.status = 'published' and (old.status is distinct from 'published') then
    insert into notification_queue (type, reference_id, society_id)
    values ('notice_published', new.id, new.society_id);
  end if;
  return new;
end;
$$ language plpgsql;

create trigger trg_notice_published
after update on notices
for each row execute function notify_on_notice_published();
```
(`notification_queue` is a generic table you'll likely want anyway once Visitor/Delivery/Complaint notifications exist too — worth designing once, reused everywhere, rather than a notices-specific notification mechanism.)

---

## Society Admin Panel — Screens

**1. Notices List (management view)**
- Tabs or filter: Draft / Scheduled / Published / Expired / Archived
- Each row: title, category badge, target (All / Block X), pin indicator, publish date, read count (e.g., "34/50 read")
- Actions: Edit (if draft/scheduled), Archive, Unpublish (pull a live notice early)

**2. Create/Edit Notice**
- Title (short, this is what shows in the home-screen widget — keep a soft character limit, ~60 chars, with a counter)
- Body (longer text, rich enough for line breaks; full markdown/rich-text is overkill for v1)
- Category (dropdown: Important, Event, Safety, Maintenance, Billing, General) — this drives the badge color
- **"This is an event" toggle** (auto-checked when category = Event, but editable) — reveals Event date, Start time, End time, and optional Venue
- Optional attachment (image or PDF)
- Target: All residents, or a specific Block
- Pin this notice (toggle)
- Requires acknowledgment (toggle) — when on, show a note to the admin: "Residents will need to tap 'I understand' before this is marked as acknowledged"
- Publish timing: **Publish now** / **Schedule for later** (date + time picker)
- Optional: Expires on (date picker, optional — auto-suggested as the day after the event date when "This is an event" is on)
- Save as Draft / Publish (or Schedule) buttons — draft never notifies anyone

**3. Notice Detail (admin view)**
- Full notice as residents see it
- Read stats: X/Y residents have read this
- If `requires_acknowledgment`: separate acknowledgment stats, and a list of who hasn't acknowledged yet (useful to chase up before a mandatory drill/deadline)

---

## User Panel — Screens

**1. Home Screen — "Latest Updates" widget** (matches your screenshot)
- Top 3 published, non-expired notices relevant to the resident (all + their block), pinned ones first, then newest
- Each row: category badge, title, one-line snippet of body, relative time ("2h ago")
- Event notices show "6:00 PM · 15 Aug" inline instead of/alongside the relative time, so an event is scannable without opening it
- "View all" → full Notices tab

**2. Notices Tab (full list)**
- All published notices relevant to this resident, pinned at top, then reverse-chronological
- Filter by category (chip row: All, Important, Event, Safety, Maintenance, Billing, General)
- Consider a small "Upcoming Events" strip at the top of this tab (sorted by `event_starts_at` ascending) — separate from the reverse-chronological feed below it, since a resident scanning for events wants them sorted by *when they happen*, not *when they were posted*
- Unread notices visually distinct (bold title / dot indicator) — mark as read the moment the resident opens the detail view

**3. Notice Detail**
- Full title, body, attachment (if any), category badge, posted date
- If `is_event`: a prominent date/time/venue block near the top (calendar-style date + "6:00 PM – 8:00 PM" + venue) — this should be the most visually prominent part of an event notice, above the body text
- If `requires_acknowledgment` and not yet acknowledged: a prominent "I understand / Confirm" button pinned at the bottom
- Auto-insert into `notice_reads` on view (fire-and-forget, don't block rendering on it)

**4. Notification badge**
- Bell icon (already in your screenshot) shows unread count — count of published notices in scope that this resident hasn't opened yet

---

## Push/In-App Notifications (minimum viable for this module)

You don't need a full push-notification service built to ship this — start with:
- An in-app unread badge (via `notice_reads` absence) — this alone covers most of the value
- If you already have any push mechanism (FCM, OneSignal, etc.) wired up elsewhere, hook it into the `notification_queue` trigger above; if not, treat real push notifications as a fast-follow, not a blocker for this module's launch

---

## Definition of Done

1. Admin can create a notice, save as draft, and it does **not** appear anywhere in the User panel
2. Admin can publish a notice immediately targeted at "All" — it appears within the Notices tab and the Home "Latest Updates" widget for residents across different blocks
3. Admin can create a notice targeted at a specific Block — confirm a resident in a different block does **not** see it
4. Admin can schedule a notice for a future time — confirm it stays invisible to residents until `publish_at`, then appears automatically (test with a near-future timestamp, a few minutes out)
5. A pinned notice stays above newer non-pinned notices in both the widget and full list
6. A notice with `expires_at` in the past no longer appears to residents, but is still visible to the admin under "Expired"
7. Admin can see accurate read counts, and separately, acknowledgment counts for a `requires_acknowledgment` notice
8. A resident can tap "I understand" on a mandatory notice, and the admin's acknowledgment list reflects it immediately
9. Admin can create an event notice (e.g. Janmashtami, 6:00 PM–8:00 PM on a specific date) with `publish_at` set earlier than the event date — confirm the notice is visible in advance, and the event's date/time/venue render prominently and correctly on both the widget and detail view
10. An event notice's `expires_at` (auto-suggested as the day after the event) correctly moves it to "Expired" for the admin and out of the resident feed once the event has passed
