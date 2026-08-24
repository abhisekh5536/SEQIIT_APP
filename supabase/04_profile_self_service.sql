-- ============================================================
-- MIGRATION: Profile self-service
-- Adds: resident_vehicles table + RLS, relation column, household
--       visibility, and lets PRIMARY residents add family / tenant
--       members to their own flats and manage members they added.
-- Run after 01_residents_migration.sql and 03_link_fix_and_family.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1) SECURITY-DEFINER HELPERS (avoid RLS recursion)
-- ------------------------------------------------------------
create or replace function public.is_primary_of_flat(p_flat_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.residents me
     where me.flat_id = p_flat_id
       and me.user_id = auth.uid()
       and me.is_primary
       and me.status = 'active'
  );
$$;

create or replace function public.lives_in_flat(p_flat_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.residents me
     where me.flat_id = p_flat_id
       and me.user_id = auth.uid()
       and me.status = 'active'
  );
$$;

grant execute on function public.is_primary_of_flat(uuid) to authenticated;
grant execute on function public.lives_in_flat(uuid)      to authenticated;

-- ------------------------------------------------------------
-- 2) VEHICLES TABLE
-- Car name + registration + allotted parking slot per resident.
-- ------------------------------------------------------------
create table if not exists public.resident_vehicles (
  id              uuid primary key default gen_random_uuid(),
  society_id      uuid not null references public.societies(id) on delete cascade,
  flat_id         uuid not null references public.flats(id) on delete cascade,
  resident_id     uuid not null references public.residents(id) on delete cascade,
  make_model      text not null,
  registration_no text not null,
  parking_slot    text,
  created_at      timestamptz not null default now()
);

create index if not exists vehicles_resident_idx on public.resident_vehicles (resident_id);
create index if not exists vehicles_flat_idx     on public.resident_vehicles (flat_id);

alter table public.resident_vehicles enable row level security;

drop policy if exists "vehicles_select" on public.resident_vehicles;
create policy "vehicles_select" on public.resident_vehicles
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.lives_in_flat(flat_id)
);

drop policy if exists "vehicles_insert" on public.resident_vehicles;
create policy "vehicles_insert" on public.resident_vehicles
for insert to authenticated
with check (
  public.is_society_admin(society_id)
  or exists (select 1 from public.residents r where r.id = resident_id and r.user_id = auth.uid())
  or public.is_primary_of_flat(flat_id)
);

drop policy if exists "vehicles_update" on public.resident_vehicles;
create policy "vehicles_update" on public.resident_vehicles
for update to authenticated
using (
  public.is_society_admin(society_id)
  or exists (select 1 from public.residents r where r.id = resident_id and r.user_id = auth.uid())
)
with check (
  public.is_society_admin(society_id)
  or exists (select 1 from public.residents r where r.id = resident_id and r.user_id = auth.uid())
);

drop policy if exists "vehicles_delete" on public.resident_vehicles;
create policy "vehicles_delete" on public.resident_vehicles
for delete to authenticated
using (
  public.is_society_admin(society_id)
  or exists (select 1 from public.residents r where r.id = resident_id and r.user_id = auth.uid())
);

-- ------------------------------------------------------------
-- 3) RELATION COLUMN
-- e.g. Spouse / Son / Daughter for family members.
-- ------------------------------------------------------------
alter table public.residents add column if not exists relation text;

-- ------------------------------------------------------------
-- 4) HOUSEHOLD VISIBILITY
-- Members of a flat can see the other people registered in the
-- SAME flat (needed for the profile page's family section).
-- Replaces the stricter residents_select from migration 01.
-- ------------------------------------------------------------
drop policy if exists "residents_select" on public.residents;
create policy "residents_select" on public.residents
for select to authenticated
using (
  public.is_society_admin(society_id)
  or user_id = auth.uid()
  or public.lives_in_flat(flat_id)
);

-- ------------------------------------------------------------
-- 5) HOUSEHOLD SELF-SERVICE
-- Primary active residents may ADD family members / tenants to
-- their own flats. They may also edit/remove members they added
-- themselves (created_by = auth.uid()).
-- Admins keep full control via existing policies.
-- ------------------------------------------------------------
drop policy if exists "residents_insert_household" on public.residents;
create policy "residents_insert_household" on public.residents
for insert to authenticated
with check (
  public.is_society_admin(society_id)
  or (
    resident_type in ('family', 'tenant')
    and public.is_primary_of_flat(flat_id)
  )
);

drop policy if exists "residents_update_household" on public.residents;
create policy "residents_update_household" on public.residents
for update to authenticated
using (
  public.is_society_admin(society_id)
  or (resident_type in ('family', 'tenant') and created_by = auth.uid())
)
with check (
  public.is_society_admin(society_id)
  or (resident_type in ('family', 'tenant') and created_by = auth.uid())
);

drop policy if exists "residents_delete_household" on public.residents;
create policy "residents_delete_household" on public.residents
for delete to authenticated
using (
  public.is_society_admin(society_id)
  or (resident_type in ('family', 'tenant') and created_by = auth.uid())
);

-- ------------------------------------------------------------
-- DONE. Verify:
--   As a primary resident: insert into resident_vehicles (...) -> works
--   Insert a family member into own flat -> works
--   Insert into someone else's flat -> row-level security violation
-- ------------------------------------------------------------
