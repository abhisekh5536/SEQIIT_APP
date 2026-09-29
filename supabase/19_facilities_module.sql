-- ============================================================
-- 19) FACILITIES MODULE (display / catalog)
--
-- Society admins publish the society's facilities (photos, description,
-- hours, rules, status); residents browse them. Deliberately NOT a booking
-- system — Facility Booking is a separate future module that will attach
-- to `facilities.id` without changing these tables.
--
--   1) facility_categories  — shared defaults + per-society custom ones
--   2) facilities           — the catalog, with active/maintenance/closed
--   3) facility_images      — ordered gallery per facility
--   4) RLS                  — society scoping enforced server-side, and the
--                             `facilities` module flag honoured for residents
--   5) Storage bucket       — facility-images, writes limited to admins of
--                             the society in the path
--   6) Status-change notification (push is opt-in per resident)
--   7) Realtime, so a status change reaches open screens immediately
--
-- Prerequisite: migrations 01, 07, 18.
-- Idempotent: safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1) CATEGORIES
--
-- society_id null  -> shared default, visible to every society, read-only
-- society_id set   -> a society's own category, editable by its admins
--
-- A single global list editable by any society admin would let one
-- society rename another's categories, so edits are per society.
-- ------------------------------------------------------------
create table if not exists public.facility_categories (
  id          uuid primary key default gen_random_uuid(),
  society_id  uuid references public.societies(id) on delete cascade,
  name        text not null check (length(trim(name)) between 1 and 40),
  sort_order  int not null default 100,
  created_at  timestamptz not null default now()
);

create unique index if not exists uq_facility_categories_name
  on public.facility_categories (coalesce(society_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name));

insert into public.facility_categories (society_id, name, sort_order)
select null, v.name, v.sort_order
  from (values
    ('Sports', 10),
    ('Fitness & Wellness', 20),
    ('Community Hall', 30),
    ('Outdoor', 40),
    ('Kids', 50),
    ('Other', 90)
  ) as v(name, sort_order)
 where not exists (
   select 1 from public.facility_categories c
    where c.society_id is null and lower(c.name) = lower(v.name)
 );

-- ------------------------------------------------------------
-- 2) FACILITIES
-- ------------------------------------------------------------
create table if not exists public.facilities (
  id               uuid primary key default gen_random_uuid(),
  society_id       uuid not null references public.societies(id) on delete cascade,
  category_id      uuid references public.facility_categories(id) on delete set null,
  name             text not null check (length(trim(name)) between 1 and 80),
  description      text not null default '',
  status           text not null default 'active'
                     check (status in ('active', 'maintenance', 'closed')),
  status_note      text,          -- e.g. "Cleaning until Friday"
  operating_hours  text,          -- free text for v1, e.g. "5:00 AM – 10:00 PM"
  location         text,          -- e.g. "Clubhouse, ground floor"
  rules_text       text,
  created_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists idx_facilities_society
  on public.facilities (society_id, name);

create or replace function public.fn_facilities_touch()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_facilities_touch on public.facilities;
create trigger trg_facilities_touch
before update on public.facilities
for each row execute function public.fn_facilities_touch();

-- ------------------------------------------------------------
-- 3) IMAGES
-- ------------------------------------------------------------
create table if not exists public.facility_images (
  id           uuid primary key default gen_random_uuid(),
  facility_id  uuid not null references public.facilities(id) on delete cascade,
  image_url    text not null,
  storage_path text,              -- for deleting the object with the row
  sort_order   int not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists idx_facility_images_facility
  on public.facility_images (facility_id, sort_order);

-- ------------------------------------------------------------
-- 4) ROW LEVEL SECURITY
--
-- Scoping comes from the caller's own membership (auth.uid()), never from
-- anything the client sends, so one society cannot read another's list.
--
-- A society that switched the module off (module_flags, key 'facilities')
-- hides it from residents; admins keep access so they can prepare the
-- catalog before switching it on. No flag row means enabled.
-- ------------------------------------------------------------
create or replace function public.facilities_enabled(p_society_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select enabled from public.module_flags
      where society_id = p_society_id and module_key = 'facilities'),
    true
  );
$$;

create or replace function public.can_view_facilities(p_society_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_master_admin()
      or public.is_society_admin(p_society_id)
      or (public.is_society_member(p_society_id)
          and public.facilities_enabled(p_society_id));
$$;

grant execute on function public.facilities_enabled(uuid) to authenticated;
grant execute on function public.can_view_facilities(uuid) to authenticated;

alter table public.facility_categories enable row level security;
alter table public.facilities          enable row level security;
alter table public.facility_images     enable row level security;

-- categories
drop policy if exists "facility categories read" on public.facility_categories;
create policy "facility categories read" on public.facility_categories
for select to authenticated
using (society_id is null or public.is_society_member(society_id) or public.is_master_admin());

drop policy if exists "facility categories admin write" on public.facility_categories;
create policy "facility categories admin write" on public.facility_categories
for all to authenticated
using (society_id is not null and public.is_society_admin(society_id))
with check (society_id is not null and public.is_society_admin(society_id));

-- facilities
drop policy if exists "facilities read" on public.facilities;
create policy "facilities read" on public.facilities
for select to authenticated
using (public.can_view_facilities(society_id));

drop policy if exists "facilities admin write" on public.facilities;
create policy "facilities admin write" on public.facilities
for all to authenticated
using (public.is_society_admin(society_id))
with check (public.is_society_admin(society_id));

-- images follow their facility
drop policy if exists "facility images read" on public.facility_images;
create policy "facility images read" on public.facility_images
for select to authenticated
using (exists (
  select 1 from public.facilities f
   where f.id = facility_id and public.can_view_facilities(f.society_id)
));

drop policy if exists "facility images admin write" on public.facility_images;
create policy "facility images admin write" on public.facility_images
for all to authenticated
using (exists (
  select 1 from public.facilities f
   where f.id = facility_id and public.is_society_admin(f.society_id)
))
with check (exists (
  select 1 from public.facilities f
   where f.id = facility_id and public.is_society_admin(f.society_id)
));

-- ------------------------------------------------------------
-- 5) STORAGE: facility-images
--
-- Objects live at <society_id>/<facility_id>/<file>. Public read (the app
-- renders plain URLs, like the other modules); writes only by an admin of
-- the society named in the first path segment.
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('facility-images', 'facility-images', true)
on conflict (id) do update set public = true;

create or replace function public.is_admin_of_storage_path(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_society uuid;
begin
  begin
    v_society := ((storage.foldername(p_name))[1])::uuid;
  exception when others then
    return false;
  end;
  return public.is_society_admin(v_society);
end;
$$;

grant execute on function public.is_admin_of_storage_path(text) to authenticated;

drop policy if exists "facility images public read" on storage.objects;
create policy "facility images public read"
on storage.objects for select to public
using (bucket_id = 'facility-images');

drop policy if exists "facility images admin insert" on storage.objects;
create policy "facility images admin insert"
on storage.objects for insert to authenticated
with check (bucket_id = 'facility-images' and public.is_admin_of_storage_path(name));

drop policy if exists "facility images admin update" on storage.objects;
create policy "facility images admin update"
on storage.objects for update to authenticated
using (bucket_id = 'facility-images' and public.is_admin_of_storage_path(name));

drop policy if exists "facility images admin delete" on storage.objects;
create policy "facility images admin delete"
on storage.objects for delete to authenticated
using (bucket_id = 'facility-images' and public.is_admin_of_storage_path(name));

-- ------------------------------------------------------------
-- 6) STATUS-CHANGE NOTIFICATION
--
-- Writes one resident broadcast to the bell whenever a facility's status
-- changes. Push for it is opt-in (see push_recipients below), so residents
-- are not woken for every pool cleaning unless they asked to be.
-- ------------------------------------------------------------
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type in (
  'complaint_created', 'complaint_updated', 'complaint_resolved',
  'complaint_reopened', 'complaint_closed', 'join_request_created',
  'join_request_approved', 'join_request_rejected', 'notice', 'general',
  'visitor_approval_request', 'visitor_approved', 'visitor_denied',
  'visitor_preapproved_created', 'visitor_checked_in', 'visitor_checked_out',
  'visitor_cancelled', 'visitor_expired',
  'sos_alert_raised', 'sos_alert_acknowledged', 'sos_alert_resolved',
  'sos_alert_cancelled',
  'parking_bay_request', 'parking_bay_approved', 'parking_bay_rejected',
  'facility_status_changed'
));

create or replace function public.notify_on_facility_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  -- Nobody can see it, so nobody needs telling.
  if not public.facilities_enabled(new.society_id) then
    return new;
  end if;

  insert into public.notifications (
    society_id, user_id, target_role, title, body,
    type, entity_type, entity_id, route
  ) values (
    new.society_id,
    null,
    'resident',
    case new.status
      when 'maintenance' then '🛠️ ' || new.name || ' under maintenance'
      when 'closed'      then '⛔ ' || new.name || ' is closed'
      else                    '✅ ' || new.name || ' is open again'
    end,
    coalesce(nullif(trim(new.status_note), ''),
      case new.status
        when 'active' then 'Available as usual' || coalesce(' · ' || new.operating_hours, '')
        else 'Temporarily unavailable. Tap for details.'
      end),
    'facility_status_changed',
    'facility',
    new.id::text,
    '/facilities'
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_facility_status on public.facilities;
create trigger trg_notify_facility_status
after update of status on public.facilities
for each row execute function public.notify_on_facility_status();

-- Push plumbing from migration 18: a 'facilities' module...
alter table public.notification_preferences
  drop constraint if exists notification_preferences_module_check;
alter table public.notification_preferences
  add constraint notification_preferences_module_check check (module in (
    'visitors', 'helpdesk', 'notices', 'security',
    'approvals', 'parking', 'facilities', 'general'
  ));

create or replace function public.notification_module(p_type text)
returns text
language sql
immutable
as $$
  select case
    when p_type like 'visitor%'      then 'visitors'
    when p_type like 'complaint%'    then 'helpdesk'
    when p_type = 'notice'           then 'notices'
    when p_type like 'sos%'          then 'security'
    when p_type like 'join_request%' then 'approvals'
    when p_type like 'parking%'      then 'parking'
    when p_type like 'facility%'     then 'facilities'
    else 'general'
  end;
$$;

-- ...which, unlike the others, is OFF unless the user turned it on.
create or replace function public.push_module_default(p_module text)
returns boolean
language sql
immutable
as $$
  select p_module <> 'facilities';
$$;

create or replace function public.push_recipients(
  p_notification_id uuid,
  p_actor_id uuid default null
)
returns table (user_id uuid, token text)
language sql
stable
security definer
set search_path = public
as $$
  with n as (
    select * from public.notifications where id = p_notification_id
  ),
  audience as (
    select n.user_id as uid from n where n.user_id is not null

    union
    select r.user_id from n
      join public.residents r on r.society_id = n.society_id
     where n.user_id is null
       and n.target_role in ('resident', 'all')
       and r.status = 'active'
       and r.user_id is not null

    union
    select a.id from n
      join public.society_admin_users a on a.society_id = n.society_id
     where n.user_id is null
       and n.target_role in ('society_admin', 'all')
       and a.status = 'active'

    union
    select u.id from n
      join auth.users u
        on (u.raw_user_meta_data ->> 'society_id') = n.society_id::text
     where n.user_id is null
       and n.target_role in ('guard', 'all')
       and lower(coalesce(u.raw_user_meta_data ->> 'role', '')) in ('guard', 'security')

    union
    select v.created_by from n
      join public.visitors v on v.id::text = n.entity_id
     where n.entity_type = 'visitor'
       and n.type in ('visitor_approved', 'visitor_denied')
       and v.created_by_type in ('guard', 'society_admin')
  )
  select d.user_id, d.token
    from audience a
    join public.device_tokens d on d.user_id = a.uid
    cross join n
   where a.uid is distinct from p_actor_id
     and coalesce(
       (select pref.push_enabled from public.notification_preferences pref
         where pref.user_id = a.uid
           and pref.module = public.notification_module(n.type)),
       public.push_module_default(public.notification_module(n.type))
     );
$$;

revoke all on function public.push_recipients(uuid, uuid) from public, anon, authenticated;
grant execute on function public.push_recipients(uuid, uuid) to service_role;

-- ------------------------------------------------------------
-- 7) REALTIME
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['facilities', 'facility_images'] loop
    begin
      execute format('alter table public.%I replica identity full', t);
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then
      null;
    when others then
      raise notice 'Realtime setup for % skipped: %', t, sqlerrm;
    end;
  end loop;
end $$;
