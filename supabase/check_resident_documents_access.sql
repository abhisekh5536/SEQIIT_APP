-- ============================================================
-- Resident documents: who can see what (STAGING CHECK)
--
-- Static tests only prove the SQL text contains each check. This script
-- runs the real policies and RPCs as each kind of user and compares the
-- result with the access table in
-- saqiit-resident-documents-implementation-plan.md §2.
--
-- 1. Prepare on staging (through the app or by hand):
--      flat A: an owner and a tenant, both signed up (linked user ids);
--              the tenant has a PAN saved, a rent agreement and a masked
--              Aadhaar uploaded; the owner has a sale deed uploaded
--      flat B: a resident of another flat
--      a guard, and a society admin whose status is NOT 'active'
-- 2. Fill in the ids below.
-- 3. Run the whole script. Everything happens in one transaction that is
--    rolled back at the end, so nothing it does is kept.
-- Every row should say PASS.
-- ============================================================
begin;

create temp table rd_actor (label text primary key, user_id uuid not null);
insert into rd_actor values
  ('admin',             '00000000-0000-0000-0000-000000000001'),
  ('owner',             '00000000-0000-0000-0000-000000000002'),
  ('tenant',            '00000000-0000-0000-0000-000000000003'),
  ('other_flat',        '00000000-0000-0000-0000-000000000004'),
  ('guard',             '00000000-0000-0000-0000-000000000005'),
  ('deactivated_admin', '00000000-0000-0000-0000-000000000006');

create temp table rd_target (label text primary key, id uuid not null);
insert into rd_target values
  ('tenant_resident',      '00000000-0000-0000-0000-00000000000a'),
  ('tenant_rent_doc',      '00000000-0000-0000-0000-00000000000b'),
  ('tenant_aadhaar_doc',   '00000000-0000-0000-0000-00000000000c'),
  ('owner_sale_deed_doc',  '00000000-0000-0000-0000-00000000000d');

create temp table rd_result (
  actor text, check_name text, actual boolean
);

grant select on rd_actor, rd_target to authenticated;
grant insert, select on rd_result to authenticated;

do $$
declare
  a record;
  v_tenant uuid := (select id from rd_target where label = 'tenant_resident');
  v_rent uuid := (select id from rd_target where label = 'tenant_rent_doc');
  v_aadhaar uuid := (select id from rd_target where label = 'tenant_aadhaar_doc');
  v_deed uuid := (select id from rd_target where label = 'owner_sale_deed_doc');
  v_ok boolean;
begin
  for a in select * from rd_actor loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', a.user_id, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', a.user_id::text, true);
    execute 'set local role authenticated';

    insert into rd_result values (a.label, 'list tenant rent agreement',
      exists (select 1 from public.resident_documents where id = v_rent));
    insert into rd_result values (a.label, 'open tenant rent agreement',
      coalesce((public.open_resident_document(v_rent) ->> 'success')::boolean, false));
    insert into rd_result values (a.label, 'list tenant masked Aadhaar',
      exists (select 1 from public.resident_documents where id = v_aadhaar));
    insert into rd_result values (a.label, 'open tenant masked Aadhaar',
      coalesce((public.open_resident_document(v_aadhaar) ->> 'success')::boolean, false));
    insert into rd_result values (a.label, 'list owner sale deed',
      exists (select 1 from public.resident_documents where id = v_deed));
    insert into rd_result values (a.label, 'may reveal tenant PAN',
      (public.reveal_resident_pan(v_tenant, 'staging access check') ->> 'error')
        is distinct from 'Permission denied');

    begin
      perform 1 from public.resident_identity limit 1;
      v_ok := true;
    exception when others then
      v_ok := false;
    end;
    insert into rd_result values (a.label, 'read resident_identity table directly', v_ok);

    -- P0-2: nobody but an admin can make a resident row theirs.
    if a.label <> 'admin' then
      begin
        update public.residents set user_id = a.user_id where id = v_tenant;
      exception when others then
        null;
      end;
      insert into rd_result values (a.label, 'take over the tenant''s resident row',
        (select user_id from public.residents where id = v_tenant) = a.user_id
        and a.label <> 'tenant');
    end if;

    execute 'reset role';
  end loop;
end $$;

with expected (actor, check_name, expected) as (values
  ('admin', 'list tenant rent agreement', true),
  ('owner', 'list tenant rent agreement', true),
  ('tenant', 'list tenant rent agreement', true),
  ('other_flat', 'list tenant rent agreement', false),
  ('guard', 'list tenant rent agreement', false),
  ('deactivated_admin', 'list tenant rent agreement', false),

  ('admin', 'open tenant rent agreement', true),
  ('owner', 'open tenant rent agreement', true),
  ('tenant', 'open tenant rent agreement', true),
  ('other_flat', 'open tenant rent agreement', false),
  ('guard', 'open tenant rent agreement', false),
  ('deactivated_admin', 'open tenant rent agreement', false),

  ('admin', 'list tenant masked Aadhaar', true),
  ('owner', 'list tenant masked Aadhaar', true),
  ('tenant', 'list tenant masked Aadhaar', true),
  ('other_flat', 'list tenant masked Aadhaar', false),
  ('guard', 'list tenant masked Aadhaar', false),
  ('deactivated_admin', 'list tenant masked Aadhaar', false),

  ('admin', 'open tenant masked Aadhaar', true),
  ('owner', 'open tenant masked Aadhaar', false),
  ('tenant', 'open tenant masked Aadhaar', true),
  ('other_flat', 'open tenant masked Aadhaar', false),
  ('guard', 'open tenant masked Aadhaar', false),
  ('deactivated_admin', 'open tenant masked Aadhaar', false),

  ('admin', 'list owner sale deed', true),
  ('owner', 'list owner sale deed', true),
  ('tenant', 'list owner sale deed', false),
  ('other_flat', 'list owner sale deed', false),
  ('guard', 'list owner sale deed', false),
  ('deactivated_admin', 'list owner sale deed', false),

  ('admin', 'may reveal tenant PAN', true),
  ('owner', 'may reveal tenant PAN', false),
  ('tenant', 'may reveal tenant PAN', true),
  ('other_flat', 'may reveal tenant PAN', false),
  ('guard', 'may reveal tenant PAN', false),
  ('deactivated_admin', 'may reveal tenant PAN', false),

  ('admin', 'read resident_identity table directly', false),
  ('owner', 'read resident_identity table directly', false),
  ('tenant', 'read resident_identity table directly', false),
  ('other_flat', 'read resident_identity table directly', false),
  ('guard', 'read resident_identity table directly', false),
  ('deactivated_admin', 'read resident_identity table directly', false),

  ('owner', 'take over the tenant''s resident row', false),
  ('tenant', 'take over the tenant''s resident row', false),
  ('other_flat', 'take over the tenant''s resident row', false),
  ('guard', 'take over the tenant''s resident row', false),
  ('deactivated_admin', 'take over the tenant''s resident row', false)
)
select e.actor, e.check_name, e.expected, r.actual,
       case when r.actual is not distinct from e.expected then 'PASS' else 'FAIL' end as result
  from expected e
  left join rd_result r using (actor, check_name)
 order by result, e.check_name, e.actor;

-- Storage policies are OR'd together: one that forgets bucket_id opens
-- every bucket, including this private one. Every row here must mention
-- bucket_id.
select policyname, cmd,
       case when coalesce(qual, '') || coalesce(with_check, '') like '%bucket_id%'
            then 'PASS' else 'FAIL: no bucket_id' end as result
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
 order by result, policyname;

rollback;
