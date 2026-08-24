-- ============================================================
-- MIGRATION: Residents directory (run once in Supabase SQL Editor)
-- Adds: residents table, signup auto-link trigger, occupancy sync,
--       RLS on every table, limited-directory RPC.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE
-- ------------------------------------------------------------
create table if not exists public.residents (
  id                    uuid primary key default gen_random_uuid(),
  society_id            uuid not null references public.societies(id) on delete cascade,
  flat_id               uuid not null references public.flats(id) on delete cascade,
  user_id               uuid references auth.users(id) on delete set null,
  full_name             text not null,
  email                 text not null,
  phone                 text,
  resident_type         text not null check (resident_type in ('owner', 'tenant')),
  is_primary            boolean not null default false,
  agreement_holder_name text,
  agreement_date        date,
  aadhar_last4          varchar(4) check (aadhar_last4 ~ '^[0-9]{4}$'),
  status                text not null default 'active' check (status in ('active', 'moved_out')),
  created_by            uuid references auth.users(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists residents_society_idx on public.residents (society_id);
create index if not exists residents_flat_idx    on public.residents (flat_id);
create index if not exists residents_user_idx    on public.residents (user_id);
create index if not exists residents_email_idx   on public.residents (lower(email));

-- keep updated_at fresh automatically
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_residents_updated on public.residents;
create trigger trg_residents_updated
before update on public.residents
for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 2) SIGNUP AUTO-LINK
-- When someone signs up, attach every pending resident record
-- whose email matches (works across multiple flats too).
-- ------------------------------------------------------------
create or replace function public.link_residents_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.residents
     set user_id   = new.id,
         updated_at = now()
   where lower(email) = lower(new.email)
     and user_id is null;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.link_residents_on_signup();

-- ------------------------------------------------------------
-- 3) FLAT OCCUPANCY SYNC
-- Keeps flats.status in step with active residents.
-- NOTE: if your flats.status uses different words than
--       'occupied' / 'vacant', edit the two values below.
-- ------------------------------------------------------------
create or replace function public.sync_flat_occupancy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_flat uuid := coalesce(new.flat_id, old.flat_id);
begin
  update public.flats f
     set status = case
           when exists (
             select 1 from public.residents r
              where r.flat_id = v_flat
                and r.status = 'active'
           ) then 'occupied'
           else 'vacant'
         end
   where f.id = v_flat;
  return coalesce(new, old);
end $$;

drop trigger if exists trg_residents_flat_sync on public.residents;
create trigger trg_residents_flat_sync
after insert or update or delete on public.residents
for each row execute function public.sync_flat_occupancy();

-- ------------------------------------------------------------
-- 4) SECURITY-DEFINER HELPERS
-- (avoid RLS recursion between policies)
-- Assumes society_admin_users.status = 'active' means enabled.
-- ------------------------------------------------------------
create or replace function public.is_master_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.master_admin_users m where m.id = auth.uid()
  );
$$;

create or replace function public.is_society_admin(p_society_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.society_admin_users a
     where a.id = auth.uid()
       and a.society_id = p_society_id
       and a.status = 'active'
  );
$$;

create or replace function public.is_society_member(p_society_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_society_admin(p_society_id)
      or exists (
        select 1 from public.residents r
         where r.user_id = auth.uid()
           and r.society_id = p_society_id
           and r.status = 'active'
      );
$$;

grant execute on function public.is_master_admin()          to authenticated;
grant execute on function public.is_society_admin(uuid)     to authenticated;
grant execute on function public.is_society_member(uuid)    to authenticated;

-- ------------------------------------------------------------
-- 5) LIMITED DIRECTORY RPC
-- Signed-in members get name + flat + type ONLY.
-- Phones / emails / aadhar never leave the DB here.
-- Call from app: supabase.rpc('get_directory_public', params: {'p_society_id': ...})
-- ------------------------------------------------------------
create or replace function public.get_directory_public(p_society_id uuid)
returns table (
  resident_id   uuid,
  flat_id       uuid,
  full_name     text,
  resident_type text,
  is_primary    boolean
)
language sql stable security definer set search_path = public as $$
  select r.id, r.flat_id, r.full_name, r.resident_type, r.is_primary
  from public.residents r
  where r.society_id = p_society_id
    and r.status = 'active'
    and public.is_society_member(p_society_id);
$$;

grant execute on function public.get_directory_public(uuid) to authenticated;
revoke execute on function public.get_directory_public(uuid) from anon;

-- ------------------------------------------------------------
-- 6) ROW LEVEL SECURITY
-- ------------------------------------------------------------
alter table public.residents           enable row level security;
alter table public.societies           enable row level security;
alter table public.blocks              enable row level security;
alter table public.flats               enable row level security;
alter table public.society_admin_users enable row level security;
alter table public.master_admin_users  enable row level security;
alter table public.support_tickets     enable row level security;
alter table public.module_flags        enable row level security;
alter table public.audit_logs          enable row level security;
alter table public.subscription_plans  enable row level security;

-- residents: full rows only for admins + the record owner
drop policy if exists "residents_select" on public.residents;
create policy "residents_select" on public.residents
for select to authenticated
using (public.is_society_admin(society_id) or user_id = auth.uid());

drop policy if exists "residents_insert" on public.residents;
create policy "residents_insert" on public.residents
for insert to authenticated
with check (public.is_society_admin(society_id));

drop policy if exists "residents_update" on public.residents;
create policy "residents_update" on public.residents
for update to authenticated
using (public.is_society_admin(society_id))
with check (public.is_society_admin(society_id));

drop policy if exists "residents_delete" on public.residents;
create policy "residents_delete" on public.residents
for delete to authenticated
using (public.is_society_admin(society_id));

-- societies: visible to their admins and their members
drop policy if exists "societies_select" on public.societies;
create policy "societies_select" on public.societies
for select to authenticated
using (public.is_society_member(id));

-- blocks / flats: readable by members, writable by admins only
drop policy if exists "blocks_select" on public.blocks;
create policy "blocks_select" on public.blocks
for select to authenticated
using (public.is_society_member(society_id));

drop policy if exists "blocks_write" on public.blocks;
create policy "blocks_write" on public.blocks
for all to authenticated
using (public.is_society_admin(society_id))
with check (public.is_society_admin(society_id));

drop policy if exists "flats_select" on public.flats;
create policy "flats_select" on public.flats
for select to authenticated
using (
  exists (
    select 1 from public.blocks b
     where b.id = flats.block_id
       and public.is_society_member(b.society_id)
  )
);

drop policy if exists "flats_write" on public.flats;
create policy "flats_write" on public.flats
for all to authenticated
using (
  exists (
    select 1 from public.blocks b
     where b.id = flats.block_id
       and public.is_society_admin(b.society_id)
  )
)
with check (
  exists (
    select 1 from public.blocks b
     where b.id = flats.block_id
       and public.is_society_admin(b.society_id)
  )
);

-- roles: users may read only their own role rows
drop policy if exists "admin_roles_select_own" on public.society_admin_users;
create policy "admin_roles_select_own" on public.society_admin_users
for select to authenticated
using (id = auth.uid());

drop policy if exists "master_roles_select_own" on public.master_admin_users;
create policy "master_roles_select_own" on public.master_admin_users
for select to authenticated
using (id = auth.uid());

-- module flags: readable by members, writable by admins
drop policy if exists "module_flags_select" on public.module_flags;
create policy "module_flags_select" on public.module_flags
for select to authenticated
using (public.is_society_member(society_id));

drop policy if exists "module_flags_write" on public.module_flags;
create policy "module_flags_write" on public.module_flags
for all to authenticated
using (public.is_society_admin(society_id))
with check (public.is_society_admin(society_id));

-- support tickets: users see/create their own; admins see all of their society
drop policy if exists "tickets_select" on public.support_tickets;
create policy "tickets_select" on public.support_tickets
for select to authenticated
using (raised_by = auth.uid() or public.is_society_admin(society_id));

drop policy if exists "tickets_insert" on public.support_tickets;
create policy "tickets_insert" on public.support_tickets
for insert to authenticated
with check (raised_by = auth.uid());

drop policy if exists "tickets_update" on public.support_tickets;
create policy "tickets_update" on public.support_tickets
for update to authenticated
using (public.is_society_admin(society_id))
with check (public.is_society_admin(society_id));

-- audit logs: read-only for master admins (writes happen server-side)
drop policy if exists "audit_logs_select" on public.audit_logs;
create policy "audit_logs_select" on public.audit_logs
for select to authenticated
using (public.is_master_admin());

-- subscription plans: any signed-in user can browse plans
drop policy if exists "plans_select" on public.subscription_plans;
create policy "plans_select" on public.subscription_plans
for select to authenticated
using (true);

-- ------------------------------------------------------------
-- DONE. Verify with:
--   select count(*) from public.residents;  -- as any signed-in user
--   -> should be 0 unless you are an admin or linked resident
-- ------------------------------------------------------------
