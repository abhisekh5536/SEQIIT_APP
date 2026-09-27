-- ============================================================
-- 12) PARKING BAY REQUESTS
--
-- Turns the resident-side "Request a bay" action into a real,
-- reviewable record instead of a fire-and-forget notification.
--
--   1) parking_bay_requests table
--   2) Triggers: updated_at + auto-resolve on allocation
--   3) Server Action RPCs:
--        - create_parking_bay_request
--        - review_parking_bay_request
--        - cancel_parking_bay_request
--   4) RLS policies for Master Admin, Society Admin, Resident
--   5) Realtime publication
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE: parking_bay_requests
-- ------------------------------------------------------------
create table if not exists public.parking_bay_requests (
  id                  uuid primary key default gen_random_uuid(),
  society_id          uuid not null references public.societies(id) on delete cascade,
  flat_id             uuid not null references public.flats(id) on delete cascade,
  resident_id         uuid references public.residents(id) on delete set null,
  vehicle_id          uuid references public.vehicles(id) on delete set null,
  preferred_category  text check (preferred_category in ('covered', 'open')),
  notes               text,
  status              text not null default 'pending'
                        check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by        uuid references auth.users(id) on delete set null,
  reviewed_by         uuid references auth.users(id) on delete set null,
  reviewed_at         timestamptz,
  review_notes        text,
  allocation_id       uuid references public.parking_allocations(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists idx_bay_requests_society on public.parking_bay_requests(society_id, status);
create index if not exists idx_bay_requests_flat on public.parking_bay_requests(flat_id, status);

-- A flat may only have one request awaiting review at a time.
create unique index if not exists idx_unique_pending_bay_request
  on public.parking_bay_requests(flat_id)
  where status = 'pending';

-- ------------------------------------------------------------
-- 2) TRIGGERS
-- ------------------------------------------------------------
create or replace function public.fn_touch_bay_request_updated_at()
returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_touch_bay_request_updated_at on public.parking_bay_requests;
create trigger trg_touch_bay_request_updated_at
  before update on public.parking_bay_requests
  for each row execute function public.fn_touch_bay_request_updated_at();

-- When an admin allocates a bay to a flat, any request that flat has
-- waiting is closed out automatically. Without this the resident would
-- keep seeing "pending review" after their bay was already allotted.
create or replace function public.fn_resolve_bay_request_on_allocation()
returns trigger
language plpgsql
security definer set search_path = public as $$
begin
  if new.status = 'active' then
    update public.parking_bay_requests
       set status        = 'approved',
           reviewed_at   = coalesce(reviewed_at, now()),
           reviewed_by   = coalesce(reviewed_by, new.allocated_by),
           allocation_id = new.id,
           review_notes  = coalesce(review_notes, 'Bay allotted by the society office')
     where flat_id = new.flat_id
       and status  = 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_resolve_bay_request_on_allocation on public.parking_allocations;
create trigger trg_resolve_bay_request_on_allocation
  after insert on public.parking_allocations
  for each row execute function public.fn_resolve_bay_request_on_allocation();

-- ------------------------------------------------------------
-- 3) SERVER ACTION RPCs
-- ------------------------------------------------------------

-- 3.1 Resident raises a bay request
create or replace function public.create_parking_bay_request(
  p_society_id          uuid,
  p_flat_id             uuid,
  p_resident_id         uuid default null,
  p_vehicle_id          uuid default null,
  p_preferred_category  text default null,
  p_notes               text default null
)
returns jsonb
language plpgsql
security definer set search_path = public as $$
declare
  v_request_id  uuid;
  v_max_slots   int;
  v_active      int;
begin
  if not (public.lives_in_flat(p_flat_id) or public.is_society_admin(p_society_id) or public.is_master_admin()) then
    return jsonb_build_object('success', false, 'error', 'You can only raise a request for your own flat');
  end if;

  if not exists (select 1 from public.flats where id = p_flat_id) then
    return jsonb_build_object('success', false, 'error', 'Flat not found');
  end if;

  if exists (select 1 from public.parking_bay_requests where flat_id = p_flat_id and status = 'pending') then
    return jsonb_build_object('success', false, 'error', 'This flat already has a bay request awaiting review');
  end if;

  -- Don't let a flat queue up for more bays than the society allows.
  select coalesce(max_slots_per_flat, 2) into v_max_slots
    from public.parking_society_configs where society_id = p_society_id;
  v_max_slots := coalesce(v_max_slots, 2);

  select count(*) into v_active
    from public.parking_allocations
   where flat_id = p_flat_id and status = 'active';

  if v_active >= v_max_slots then
    return jsonb_build_object(
      'success', false,
      'error', format('This flat already holds %s of %s permitted bays', v_active, v_max_slots)
    );
  end if;

  if p_vehicle_id is not null then
    if not exists (
      select 1 from public.vehicles
       where id = p_vehicle_id and flat_id = p_flat_id and status = 'active'
    ) then
      return jsonb_build_object('success', false, 'error', 'Vehicle does not belong to this flat or is not active');
    end if;
  end if;

  insert into public.parking_bay_requests (
    society_id, flat_id, resident_id, vehicle_id,
    preferred_category, notes, status, requested_by
  ) values (
    p_society_id, p_flat_id, p_resident_id, p_vehicle_id,
    nullif(p_preferred_category, 'any'), nullif(trim(coalesce(p_notes, '')), ''), 'pending', auth.uid()
  ) returning id into v_request_id;

  return jsonb_build_object('success', true, 'request_id', v_request_id);
end;
$$;

grant execute on function public.create_parking_bay_request to authenticated;

-- 3.2 Admin approves or rejects a request
create or replace function public.review_parking_bay_request(
  p_request_id   uuid,
  p_action       text,             -- 'approved' | 'rejected'
  p_review_notes text default null
)
returns jsonb
language plpgsql
security definer set search_path = public as $$
declare
  v_req record;
begin
  select * into v_req from public.parking_bay_requests where id = p_request_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Request not found');
  end if;

  if not (public.is_society_admin(v_req.society_id) or public.is_master_admin()) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_req.status <> 'pending' then
    return jsonb_build_object('success', false, 'error', 'This request has already been reviewed');
  end if;

  if p_action not in ('approved', 'rejected') then
    return jsonb_build_object('success', false, 'error', 'Invalid action');
  end if;

  if p_action = 'rejected' and nullif(trim(coalesce(p_review_notes, '')), '') is null then
    return jsonb_build_object('success', false, 'error', 'A reason is required when declining a request');
  end if;

  update public.parking_bay_requests
     set status       = p_action,
         reviewed_by  = auth.uid(),
         reviewed_at  = now(),
         review_notes = nullif(trim(coalesce(p_review_notes, '')), '')
   where id = p_request_id;

  return jsonb_build_object('success', true, 'request_id', p_request_id, 'status', p_action);
end;
$$;

grant execute on function public.review_parking_bay_request to authenticated;

-- 3.3 Resident withdraws their own pending request
create or replace function public.cancel_parking_bay_request(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer set search_path = public as $$
declare
  v_req record;
begin
  select * into v_req from public.parking_bay_requests where id = p_request_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Request not found');
  end if;

  if not (public.lives_in_flat(v_req.flat_id) or public.is_society_admin(v_req.society_id) or public.is_master_admin()) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_req.status <> 'pending' then
    return jsonb_build_object('success', false, 'error', 'Only a pending request can be withdrawn');
  end if;

  update public.parking_bay_requests
     set status = 'cancelled', reviewed_at = now()
   where id = p_request_id;

  return jsonb_build_object('success', true, 'request_id', p_request_id);
end;
$$;

grant execute on function public.cancel_parking_bay_request to authenticated;

-- ------------------------------------------------------------
-- 4) ROW LEVEL SECURITY
-- ------------------------------------------------------------
alter table public.parking_bay_requests enable row level security;

drop policy if exists "bay_requests_select" on public.parking_bay_requests;
create policy "bay_requests_select" on public.parking_bay_requests
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or public.lives_in_flat(flat_id)
);

drop policy if exists "bay_requests_insert" on public.parking_bay_requests;
create policy "bay_requests_insert" on public.parking_bay_requests
for insert to authenticated
with check (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or public.lives_in_flat(flat_id)
);

drop policy if exists "bay_requests_update" on public.parking_bay_requests;
create policy "bay_requests_update" on public.parking_bay_requests
for update to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or public.lives_in_flat(flat_id)
)
with check (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or public.lives_in_flat(flat_id)
);

drop policy if exists "bay_requests_delete" on public.parking_bay_requests;
create policy "bay_requests_delete" on public.parking_bay_requests
for delete to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
);

-- ------------------------------------------------------------
-- 5) REALTIME
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'parking_bay_requests'
  ) then
    alter publication supabase_realtime add table public.parking_bay_requests;
  end if;
exception when others then
  raise notice 'Could not add parking_bay_requests to realtime publication: %', sqlerrm;
end $$;

-- ------------------------------------------------------------
-- 6) NOTIFICATION TYPE
--
-- notifications.type is constrained by notifications_type_check. Adding
-- the parking type here keeps the resident's "bay requested" nudge from
-- being rejected by that constraint.
-- ------------------------------------------------------------
do $$
begin
  alter table public.notifications drop constraint if exists notifications_type_check;
  alter table public.notifications add constraint notifications_type_check
    check (type in (
      'complaint_created', 'complaint_updated', 'complaint_resolved',
      'complaint_reopened', 'complaint_closed', 'join_request_created',
      'join_request_approved', 'join_request_rejected', 'notice', 'general',
      'visitor_approval_request', 'visitor_approved', 'visitor_denied',
      'visitor_preapproved_created', 'visitor_checked_in', 'visitor_checked_out',
      'visitor_cancelled', 'visitor_expired',
      'sos_alert_raised', 'sos_alert_acknowledged', 'sos_alert_resolved', 'sos_alert_cancelled',
      'parking_bay_request', 'parking_bay_approved', 'parking_bay_rejected'
    ));
exception when others then
  raise notice 'Could not update notifications type check constraint: %', sqlerrm;
end $$;
