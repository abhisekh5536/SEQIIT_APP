-- ============================================================
-- MIGRATION 06: Complaints / Helpdesk Module
-- Provides tables, RLS, storage bucket, and atomic RPC functions
-- for raising complaints, status transitions, and audit trail.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE: complaints
-- ------------------------------------------------------------
create table if not exists public.complaints (
  id                    uuid primary key default gen_random_uuid(),
  society_id            uuid not null references public.societies(id) on delete cascade,
  flat_id               uuid not null references public.flats(id) on delete cascade,
  raised_by             uuid not null references public.residents(id) on delete cascade,
  category              text not null check (category in
                          ('plumbing', 'electrical', 'security', 'cleanliness', 'billing', 'lift', 'other')),
  title                 text not null,
  description           text,
  photo_url             text,
  status                text not null default 'open' check (status in
                          ('open', 'in_progress', 'resolved', 'closed', 'reopened')),
  priority              text not null default 'medium' check (priority in ('low', 'medium', 'high')),
  assigned_to           text,
  admin_notes           text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  resolved_at           timestamptz
);

create index if not exists idx_complaints_society    on public.complaints(society_id);
create index if not exists idx_complaints_flat       on public.complaints(flat_id);
create index if not exists idx_complaints_raised_by  on public.complaints(raised_by);
create index if not exists idx_complaints_status     on public.complaints(status);
create index if not exists idx_complaints_category   on public.complaints(category);
create index if not exists idx_complaints_created_at on public.complaints(created_at desc);

-- Keep updated_at fresh
drop trigger if exists trg_complaints_updated on public.complaints;
create trigger trg_complaints_updated
before update on public.complaints
for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 2) TABLE: complaint_status_history
-- ------------------------------------------------------------
create table if not exists public.complaint_status_history (
  id                    uuid primary key default gen_random_uuid(),
  complaint_id          uuid not null references public.complaints(id) on delete cascade,
  from_status           text,
  to_status             text not null,
  note                  text,
  changed_by            uuid references auth.users(id) on delete set null,
  changed_by_role       text not null check (changed_by_role in ('resident', 'society_admin')),
  created_at            timestamptz not null default now()
);

create index if not exists idx_complaint_history_complaint on public.complaint_status_history(complaint_id, created_at asc);

-- ------------------------------------------------------------
-- 3) ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------
alter table public.complaints enable row level security;
alter table public.complaint_status_history enable row level security;

-- Master Admin: full access
drop policy if exists "master admins full access to complaints" on public.complaints;
create policy "master admins full access to complaints"
on public.complaints
for all
to authenticated
using (public.is_master_admin());

drop policy if exists "master admins full access to complaint history" on public.complaint_status_history;
create policy "master admins full access to complaint history"
on public.complaint_status_history
for all
to authenticated
using (public.is_master_admin());

-- Society Admin: full access to complaints within their own society
drop policy if exists "society admins manage own complaints" on public.complaints;
create policy "society admins manage own complaints"
on public.complaints
for all
to authenticated
using (public.is_society_admin(society_id))
with check (public.is_society_admin(society_id));

drop policy if exists "society admins view history" on public.complaint_status_history;
create policy "society admins view history"
on public.complaint_status_history
for select
to authenticated
using (
  complaint_id in (
    select c.id from public.complaints c
     where public.is_society_admin(c.society_id)
  )
);

drop policy if exists "society admins insert history" on public.complaint_status_history;
create policy "society admins insert history"
on public.complaint_status_history
for insert
to authenticated
with check (
  complaint_id in (
    select c.id from public.complaints c
     where public.is_society_admin(c.society_id)
  )
);

-- Resident: can view, create, and update complaints for their own residence records
drop policy if exists "residents view own complaints" on public.complaints;
create policy "residents view own complaints"
on public.complaints
for select
to authenticated
using (
  raised_by in (
    select r.id from public.residents r
     where r.user_id = auth.uid()
  )
);

drop policy if exists "residents create own complaints" on public.complaints;
create policy "residents create own complaints"
on public.complaints
for insert
to authenticated
with check (
  raised_by in (
    select r.id from public.residents r
     where r.user_id = auth.uid()
       and r.society_id = complaints.society_id
       and r.status = 'active'
  )
);

drop policy if exists "residents update own complaints" on public.complaints;
create policy "residents update own complaints"
on public.complaints
for update
to authenticated
using (
  raised_by in (
    select r.id from public.residents r
     where r.user_id = auth.uid()
  )
)
with check (
  raised_by in (
    select r.id from public.residents r
     where r.user_id = auth.uid()
  )
);

-- Resident: view & insert history on own complaints
drop policy if exists "residents view own complaint history" on public.complaint_status_history;
create policy "residents view own complaint history"
on public.complaint_status_history
for select
to authenticated
using (
  complaint_id in (
    select c.id from public.complaints c
      join public.residents r on r.id = c.raised_by
     where r.user_id = auth.uid()
  )
);

drop policy if exists "residents insert own complaint history" on public.complaint_status_history;
create policy "residents insert own complaint history"
on public.complaint_status_history
for insert
to authenticated
with check (
  complaint_id in (
    select c.id from public.complaints c
      join public.residents r on r.id = c.raised_by
     where r.user_id = auth.uid()
  )
);

-- ------------------------------------------------------------
-- 4) ATOMIC RPC FUNCTIONS
-- ------------------------------------------------------------

-- Submit a new complaint atomically with initial history entry
create or replace function public.submit_complaint(
  p_society_id uuid,
  p_flat_id uuid,
  p_raised_by uuid,
  p_category text,
  p_title text,
  p_description text default null,
  p_photo_url text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id uuid;
  v_caller_user_id uuid := auth.uid();
begin
  -- Validate caller owns the resident record or is admin
  if not exists (
    select 1 from public.residents r
     where r.id = p_raised_by
       and r.society_id = p_society_id
       and r.flat_id = p_flat_id
       and (r.user_id = v_caller_user_id or public.is_society_admin(p_society_id))
  ) then
    return json_build_object('success', false, 'error', 'Unauthorized: Invalid resident record');
  end if;

  -- Validate category
  if p_category not in ('plumbing', 'electrical', 'security', 'cleanliness', 'billing', 'lift', 'other') then
    return json_build_object('success', false, 'error', 'Invalid complaint category');
  end if;

  if coalesce(trim(p_title), '') = '' then
    return json_build_object('success', false, 'error', 'Title is required');
  end if;

  -- Insert complaint
  insert into public.complaints (
    society_id,
    flat_id,
    raised_by,
    category,
    title,
    description,
    photo_url,
    status,
    priority
  ) values (
    p_society_id,
    p_flat_id,
    p_raised_by,
    p_category,
    trim(p_title),
    trim(p_description),
    p_photo_url,
    'open',
    'medium'
  ) returning id into v_new_id;

  -- Insert initial status history entry
  insert into public.complaint_status_history (
    complaint_id,
    from_status,
    to_status,
    note,
    changed_by,
    changed_by_role
  ) values (
    v_new_id,
    null,
    'open',
    'Complaint raised',
    v_caller_user_id,
    'resident'
  );

  return json_build_object(
    'success', true,
    'complaint_id', v_new_id,
    'message', 'Complaint submitted successfully'
  );
end;
$$;

-- Atomic status transition validator and history recorder
create or replace function public.update_complaint_status_rpc(
  p_complaint_id uuid,
  p_new_status text,
  p_note text default null,
  p_assigned_to text default null,
  p_priority text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complaint record;
  v_caller_user_id uuid := auth.uid();
  v_is_admin boolean := false;
  v_is_owner boolean := false;
  v_actor_role text;
begin
  -- 1. Fetch complaint
  select * into v_complaint
    from public.complaints
   where id = p_complaint_id;

  if v_complaint.id is null then
    return json_build_object('success', false, 'error', 'Complaint not found');
  end if;

  -- 2. Check authorization
  v_is_admin := public.is_society_admin(v_complaint.society_id) or public.is_master_admin();
  v_is_owner := exists (
    select 1 from public.residents r
     where r.id = v_complaint.raised_by
       and r.user_id = v_caller_user_id
  );

  if not v_is_admin and not v_is_owner then
    return json_build_object('success', false, 'error', 'Unauthorized access to complaint');
  end if;

  v_actor_role := case when v_is_admin then 'society_admin' else 'resident' end;

  -- 3. Enforce valid state transitions
  if v_complaint.status = p_new_status then
    -- Note or metadata update without status transition
    update public.complaints
       set admin_notes = case when v_is_admin and p_note is not null then p_note else admin_notes end,
           assigned_to = case when v_is_admin and p_assigned_to is not null then p_assigned_to else assigned_to end,
           priority = case when v_is_admin and p_priority is not null then p_priority else priority end,
           updated_at = now()
     where id = p_complaint_id;

    if p_note is not null and trim(p_note) != '' then
      insert into public.complaint_status_history (
        complaint_id,
        from_status,
        to_status,
        note,
        changed_by,
        changed_by_role
      ) values (
        p_complaint_id,
        v_complaint.status,
        v_complaint.status,
        trim(p_note),
        v_caller_user_id,
        v_actor_role
      );
    end if;

    return json_build_object('success', true, 'message', 'Complaint updated successfully');
  end if;

  -- Validate Role-Based Transition Matrix:
  -- Admin: Open -> In Progress -> Resolved, or Reopened -> In Progress / Resolved
  -- Resident: Resolved -> Closed, or Resolved -> Reopened
  if v_is_admin then
    if p_new_status not in ('in_progress', 'resolved', 'open') then
      return json_build_object('success', false, 'error', 'Admins cannot mark complaints as ' || p_new_status || '. That is reserved for residents.');
    end if;
    if v_complaint.status = 'closed' then
      return json_build_object('success', false, 'error', 'Closed complaints cannot be modified.');
    end if;
  else
    -- Resident rules
    if p_new_status not in ('closed', 'reopened') then
      return json_build_object('success', false, 'error', 'Residents can only confirm fixed (Closed) or mark not fixed (Reopened).');
    end if;
    if v_complaint.status != 'resolved' then
      return json_build_object('success', false, 'error', 'You can only close or reopen a complaint once it has been marked as Resolved.');
    end if;
  end if;

  -- 4. Apply transition
  update public.complaints
     set status = p_new_status,
         admin_notes = case when v_is_admin and p_note is not null then p_note else admin_notes end,
         assigned_to = case when v_is_admin and p_assigned_to is not null then p_assigned_to else assigned_to end,
         priority = case when v_is_admin and p_priority is not null then p_priority else priority end,
         resolved_at = case when p_new_status = 'resolved' then now() when p_new_status = 'reopened' then null else resolved_at end,
         updated_at = now()
   where id = p_complaint_id;

  -- 5. Record status history entry
  insert into public.complaint_status_history (
    complaint_id,
    from_status,
    to_status,
    note,
    changed_by,
    changed_by_role
  ) values (
    p_complaint_id,
    v_complaint.status,
    p_new_status,
    trim(p_note),
    v_caller_user_id,
    v_actor_role
  );

  return json_build_object(
    'success', true,
    'message', 'Status updated to ' || p_new_status
  );
end;
$$;

grant execute on function public.submit_complaint(uuid, uuid, uuid, text, text, text, text) to authenticated;
grant execute on function public.update_complaint_status_rpc(uuid, text, text, text, text) to authenticated;

-- ------------------------------------------------------------
-- 5) STORAGE SETUP FOR COMPLAINT PHOTOS
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('complaint-photos', 'complaint-photos', true)
on conflict (id) do nothing;

drop policy if exists "Authenticated users can upload complaint photos" on storage.objects;
create policy "Authenticated users can upload complaint photos"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'complaint-photos');

drop policy if exists "Authenticated users can read complaint photos" on storage.objects;
create policy "Authenticated users can read complaint photos"
on storage.objects
for select
to authenticated
using (bucket_id = 'complaint-photos');
