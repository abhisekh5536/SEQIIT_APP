# Implementation Prompt — Saqiit Complaints / Helpdesk Module

Stack: Next.js (App Router) + Supabase. Hand this to a coding session to implement, or work through it yourself section by section.

---

## Status Flow (corrected/finalized)

```
Open ──▶ In Progress ──▶ Resolved ──▶ Closed
  ▲                          │
  └────────── Reopened ◀─────┘
```

- **Open** — resident just raised it, nothing done yet
- **In Progress** — admin has assigned/started work
- **Resolved** — admin marks it fixed; resident is notified
- **Closed** — resident confirms it's actually fixed (or auto-closes after N days with no reopen — your call, but don't auto-close immediately on Resolved, give the resident a chance to reopen)
- **Reopened** — resident marks a "Resolved" complaint as not actually fixed → goes back into the admin's active queue, distinct from a fresh "Open" so admins can see it's a repeat

Only the **admin** can move Open → In Progress → Resolved. Only the **resident** can move Resolved → Closed or Resolved → Reopened. Neither side should be able to jump straight to Closed — this keeps the trail honest.

---

## Database Schema

```sql
create table complaints (
  id uuid primary key default gen_random_uuid(),
  society_id uuid not null references societies(id) on delete cascade,
  flat_id uuid not null references flats(id) on delete cascade,
  raised_by uuid not null references residents(id) on delete cascade,
  category text not null check (category in
    ('plumbing', 'electrical', 'security', 'cleanliness', 'billing', 'lift', 'other')),
  title text not null,
  description text,
  photo_url text, -- Supabase Storage path, nullable
  status text not null default 'open' check (status in
    ('open', 'in_progress', 'resolved', 'closed', 'reopened')),
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high')),
  assigned_to text, -- free text for now ("Ramesh - plumber"); link to a staff table once Staff Management ships
  admin_notes text, -- latest note from admin, shown to resident
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  resolved_at timestamptz
);

-- Full audit trail of every status change — this is what lets you show
-- a timeline in the UI ("Raised → In Progress → Resolved → Reopened")
create table complaint_status_history (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references complaints(id) on delete cascade,
  from_status text,
  to_status text not null,
  note text,
  changed_by uuid, -- resident.id or society_admin_users.id
  changed_by_role text check (changed_by_role in ('resident', 'society_admin')),
  created_at timestamptz default now()
);

create index idx_complaints_society on complaints(society_id);
create index idx_complaints_flat on complaints(flat_id);
create index idx_complaints_status on complaints(status);
```

### RLS Policies

```sql
alter table complaints enable row level security;
alter table complaint_status_history enable row level security;

-- Master Admin: full access (support/debugging)
create policy "master admins full access to complaints"
  on complaints for all
  using (exists (select 1 from master_admin_users where id = auth.uid()));

-- Society Admin: full access to complaints within their own society
create policy "society admins manage own complaints"
  on complaints for all
  using (society_id = (select society_id from society_admin_users where id = auth.uid()));

-- Resident: can create complaints for their own flat, and see/update only their own
create policy "residents view own complaints"
  on complaints for select
  using (raised_by = auth.uid());

create policy "residents create own complaints"
  on complaints for insert
  with check (raised_by = auth.uid());

create policy "residents update own complaints"
  on complaints for update
  using (raised_by = auth.uid());
  -- Restrict WHICH fields residents can change to status (resolved->closed/reopened)
  -- at the application layer — RLS alone won't stop them editing title/category,
  -- so validate that in your Server Action (see below).

-- Status history: same visibility split
create policy "society admins view history"
  on complaint_status_history for select
  using (
    complaint_id in (
      select id from complaints where society_id =
        (select society_id from society_admin_users where id = auth.uid())
    )
  );

create policy "residents view own complaint history"
  on complaint_status_history for select
  using (
    complaint_id in (select id from complaints where raised_by = auth.uid())
  );
```

### Storage (optional photo attachment)

Create a Supabase Storage bucket `complaint-photos`, private, with a policy so a resident can only upload/read files under their own `resident_id` folder prefix, and Society Admins can read all files scoped to their society (implement via a signed-URL Route Handler rather than public bucket access, since this is resident-submitted content).

---

## User Panel (Resident) — Screens

Replace the current placeholder screen with:

**1. My Complaints (list)** — replaces the "being set up" screen
- List of the resident's own complaints, newest first
- Status badge per complaint (color-coded: Open=gray, In Progress=amber, Resolved=blue, Closed=green, Reopened=red)
- Tap to view detail
- Floating "+ Raise Complaint" button

**2. Raise Complaint (form)**
- Category (dropdown: Plumbing, Electrical, Security, Cleanliness, Billing, Lift, Other)
- Title (short text)
- Description (multi-line)
- Optional photo upload
- Priority is **not** resident-selectable — auto-set to `medium` by default; let the admin adjust priority based on their own judgment, since residents will otherwise mark everything "high"

**3. Complaint Detail**
- Full description + photo if attached
- Status timeline (pulled from `complaint_status_history`)
- Latest `admin_notes` shown prominently
- If status = `resolved`: two buttons — "Confirm Fixed" (→ closed) and "Not Fixed" (→ reopened, prompt for a short note on what's still wrong)

---

## Society Admin Panel — Screens

**1. Helpdesk Queue**
- Table/list of all complaints for the society
- Filters: status, category, priority
- Sort by: newest, oldest, priority
- Quick view of flat/resident, category, status badge
- Complaints with `category = 'security'` get a visual flag/icon — these should also trigger a notification to the Guard panel (implement as a simple insert into a `guard_notifications` table or reuse whatever notification mechanism you build for Visitor/Delivery alerts — don't build a separate system just for this one case)

**2. Complaint Detail (Admin view)**
- Full complaint info
- Status dropdown (Open → In Progress → Resolved only — admin cannot set Closed or Reopened, that's resident-only as established above)
- Assign to (free text field for now)
- Add admin note (saved to `admin_notes`, also logged to `complaint_status_history` even if status doesn't change, so notes have a timestamped trail)
- Priority override

---

## Server Actions / API Routes

Most of this can be plain Server Actions calling the Supabase client directly — RLS already enforces who can do what, so you mostly don't need custom Route Handlers here (unlike the invite flows, which needed the service_role key). Two things worth wrapping in a Server Action rather than raw client calls, so the status-history logging is guaranteed to happen atomically with the status change:

```ts
// app/actions/complaints.ts
'use server'

export async function updateComplaintStatus(
  complaintId: string,
  newStatus: string,
  note: string,
  actorRole: 'resident' | 'society_admin'
) {
  const supabase = await createClient() // server client, respects RLS as the logged-in user

  const { data: current } = await supabase
    .from('complaints')
    .select('status')
    .eq('id', complaintId)
    .single()

  const { error } = await supabase
    .from('complaints')
    .update({
      status: newStatus,
      admin_notes: actorRole === 'society_admin' ? note : undefined,
      resolved_at: newStatus === 'resolved' ? new Date().toISOString() : undefined,
      updated_at: new Date().toISOString(),
    })
    .eq('id', complaintId)

  if (error) throw error

  const { data: { user } } = await supabase.auth.getUser()

  await supabase.from('complaint_status_history').insert({
    complaint_id: complaintId,
    from_status: current?.status,
    to_status: newStatus,
    note,
    changed_by: user?.id,
    changed_by_role: actorRole,
  })
}
```

Enforce the allowed-transitions rule (who can set which status) **inside this function**, not just in the UI — check `actorRole` against `newStatus` and throw if a resident tries to set `in_progress`, for example.

---

## Notifications (minimum viable)

You don't need push notifications built yet to ship this module — at minimum:
- Resident sees an unread indicator/badge on "My Complaints" when status changes
- Admin sees a count badge on "Helpdesk" nav item for new/unassigned Open complaints

Full push/SMS notifications are a Phase 6 (Polish & Scale) concern per your roadmap — don't block this module's launch on that.

---

## Definition of Done

1. Resident can raise a complaint with category/title/description/optional photo
2. It appears in the Society Admin's Helpdesk queue immediately
3. Admin can move it Open → In Progress → Resolved with a note
4. Resident sees the status change and the note on their Complaint Detail screen
5. Resident can confirm-fixed (→ Closed) or reject (→ Reopened) a Resolved complaint
6. A `category = 'security'` complaint is visibly flagged for the admin (Guard notification can be stubbed/logged for now if the Guard panel doesn't exist yet)
7. Full status_history timeline renders correctly for at least one complaint that's been through every state
