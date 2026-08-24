-- ============================================================
-- SEED: Test society + blocks + flats (run once in SQL Editor)
-- Safe to re-run — it skips work already done.
-- Adjust names/counts as you like.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Subscription plan (only if you don't have one yet).
--    If your societies.plan_id column is nullable you can skip this.
-- ------------------------------------------------------------
insert into public.subscription_plans (name, price, billing_cycle)
select 'Basic', 0, 'monthly'
where not exists (select 1 from public.subscription_plans);

-- ------------------------------------------------------------
-- 2) Society
-- ------------------------------------------------------------
insert into public.societies (name, address, city, state, registration_number, status, plan_id)
select 'Sunrise Heights',
       'Plot 12, Green Avenue',
       'Pune',
       'Maharashtra',
       'REG-2026-001',
       'active',
       (select id from public.subscription_plans order by created_at limit 1)
where not exists (
  select 1 from public.societies where name = 'Sunrise Heights'
);

-- ------------------------------------------------------------
-- 3) Blocks: A and B
-- ------------------------------------------------------------
insert into public.blocks (society_id, name)
select s.id, b.name
from public.societies s
cross join (values ('Block A'), ('Block B')) as b(name)
where s.name = 'Sunrise Heights'
  and not exists (
    select 1 from public.blocks x
     where x.society_id = s.id and x.name = b.name
  );

-- ------------------------------------------------------------
-- 4) Flats: floors 1..4, four flats per floor per block
--    e.g. Block A -> A-101, A-102 ... A-404
-- ------------------------------------------------------------
insert into public.flats (block_id, floor_number, flat_number, type, status)
select bl.id,
       f.floor,
       bl.name || '-' || (f.floor * 100 + n)::text,
       '3BHK',
       'vacant'
from public.societies s
join public.blocks bl      on bl.society_id = s.id
cross join generate_series(1, 4) as f(floor)
cross join generate_series(1, 4) as n
where s.name = 'Sunrise Heights'
  and not exists (
    select 1 from public.flats fl where fl.block_id = bl.id
  );

-- ------------------------------------------------------------
-- 5) PROMOTE YOURSELF TO SOCIETY ADMIN
-- After you sign up in the app with your admin email, find your
-- auth user id and run the INSERT below.
--
-- Find your id:
--   select id, email from auth.users order by created_at desc limit 5;
--
-- Then promote (replace the email):
--   insert into public.society_admin_users (id, society_id, name, status)
--   select u.id, s.id, 'Society Admin', 'active'
--   from auth.users u, public.societies s
--   where u.email = 'you@example.com' and s.name = 'Sunrise Heights';
-- ------------------------------------------------------------
