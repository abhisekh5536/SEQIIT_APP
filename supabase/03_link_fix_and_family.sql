-- ============================================================
-- MIGRATION: Fix resident linking (reverse) + family role + mandatory fields
-- Run after 01_residents_migration.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1) Allow 'family' in resident_type
-- ------------------------------------------------------------
do $$
begin
  -- drop old check if exists (name may vary)
  if exists (select 1 from pg_constraint where conname = 'residents_resident_type_check' and conrelid = 'public.residents'::regclass) then
    alter table public.residents drop constraint residents_resident_type_check;
  end if;
exception when undefined_object then null;
end $$;

alter table public.residents
  add constraint residents_resident_type_check
  check (resident_type in ('owner', 'tenant', 'family'));

-- ------------------------------------------------------------
-- 2) Make agreement fields mandatory for active residents
--    (kept as CHECK not NOT NULL to allow historical moved_out rows)
-- ------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'residents_mandatory_fields_check' and conrelid = 'public.residents'::regclass) then
    alter table public.residents
      add constraint residents_mandatory_fields_check
      check (
        status != 'active' or (
          agreement_holder_name is not null and btrim(agreement_holder_name) <> ''
          and agreement_date is not null
          and aadhar_last4 is not null and aadhar_last4 ~ '^[0-9]{4}$'
          and email is not null and btrim(email) <> ''
          and phone is not null and btrim(phone) <> ''
        )
      );
  end if;
end $$;

-- also enforce phone NOT NULL via same check (DB had phone nullable before)
-- keep email already NOT NULL

-- ------------------------------------------------------------
-- 3) Reverse link: when admin adds resident AFTER user already exists,
--    auto-fill user_id by email match (before insert)
-- ------------------------------------------------------------
create or replace function public.link_resident_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id is null then
    select id into new.user_id
    from auth.users
    where lower(email) = lower(new.email)
    limit 1;
  end if;
  -- also set created_by if not provided
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists trg_residents_link_on_insert on public.residents;
create trigger trg_residents_link_on_insert
before insert on public.residents
for each row execute function public.link_resident_on_insert();

-- ------------------------------------------------------------
-- 4) Backfill existing pending residents where user already exists
--    (one-time fix for rows inserted before this trigger existed)
-- ------------------------------------------------------------
update public.residents r
   set user_id = u.id,
       updated_at = now()
  from auth.users u
 where r.user_id is null
   and lower(r.email) = lower(u.email);

-- ------------------------------------------------------------
-- 5) Refresh flat occupancy after backfill (in case any flat status stale)
-- ------------------------------------------------------------
-- sync_flat_occupancy() already handles insert/update/delete, but backfill
-- was an UPDATE, so it fired. Force a full sync as safety:
update public.flats f
   set status = case
         when exists (
           select 1 from public.residents r
            where r.flat_id = f.id and r.status = 'active'
         ) then 'occupied' else 'vacant' end
 where exists (select 1 from public.blocks b where b.id = f.block_id);

-- ------------------------------------------------------------
-- DONE.
-- Verify:
--   select * from public.residents where email = 'test@example.com';
--   insert into public.residents (society_id, flat_id, full_name, email, phone, resident_type, agreement_holder_name, agreement_date, aadhar_last4)
--   values (...); -- should auto-link user_id if email exists in auth.users
-- ------------------------------------------------------------
