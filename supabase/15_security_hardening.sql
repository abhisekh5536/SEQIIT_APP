-- ============================================================
-- 15) SECURITY HARDENING
--
-- Closes the four `security definer` functions that were granted to
-- `authenticated` without an authorization predicate, and defuses the
-- approval-code exhaustion bug.
--
-- `security definer` runs with the definer's rights and BYPASSES RLS.
-- Any such function must therefore perform its own authorization check
-- as its first act. These four did not, so every signed-in user of every
-- society could act on every other society's data.
--
--   1) log_vehicle_entry      — forged gate-register entries        (P0-1)
--   2) verify_pre_approval    — visitor PII leak, code-enumerable   (P0-2)
--   3) check_in_visitor       — check anyone in, anywhere           (P0-3)
--      check_out_visitor      — ditto, plus misattributed audit row
--   4) generate_approval_code — code space never released           (P1-8)
--
-- Prerequisites: migrations 09, 11 and 14 (for is_guard_or_admin).
-- Idempotent: safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 0) DROP STALE OVERLOADS
--
-- Signatures change below (verify_pre_approval gains p_society_id).
-- `create or replace` would leave the old, unguarded version alongside
-- the new one — which is exactly how the unguarded log_vehicle_exit(uuid)
-- survived its own fix. Drop every overload first.
-- ------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'log_vehicle_entry',
        'verify_pre_approval',
        'check_in_visitor',
        'check_out_visitor'
      )
  loop
    execute format('drop function if exists %s', r.sig);
  end loop;
end $$;

-- ------------------------------------------------------------
-- 1) log_vehicle_entry — require guard or admin  (P0-1)
--
-- Was: security definer, granted to authenticated, zero checks. Any user
-- could insert arbitrary rows into any society's gate register. The gate
-- register is an audit trail; without this its entries prove nothing.
-- ------------------------------------------------------------
create function public.log_vehicle_entry(
  p_society_id uuid,
  p_plate_number text,
  p_vehicle_id uuid default null,
  p_match_status text default 'unregistered',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_log_id uuid;
begin
  if not public.is_guard_or_admin(p_society_id) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if p_match_status not in ('registered', 'unregistered') then
    return jsonb_build_object('success', false, 'error', 'Invalid match status');
  end if;

  -- A vehicle may only be attributed to a log row in its own society,
  -- otherwise a guard could pin a movement on an unrelated resident.
  if p_vehicle_id is not null then
    if not exists (
      select 1 from public.vehicles
       where id = p_vehicle_id and society_id = p_society_id
    ) then
      return jsonb_build_object('success', false, 'error', 'Vehicle does not belong to this society');
    end if;
  end if;

  insert into public.vehicle_entry_logs (
    society_id, vehicle_id, vehicle_number_entered, match_status,
    entry_at, logged_by, notes
  ) values (
    p_society_id,
    p_vehicle_id,
    -- Same normalisation the lookup RPC and the Flutter client use, so a
    -- plate logged at the gate matches the registry later.
    upper(regexp_replace(p_plate_number, '[^a-zA-Z0-9]', '', 'g')),
    p_match_status,
    now(), auth.uid(), nullif(trim(coalesce(p_notes, '')), '')
  ) returning id into v_log_id;

  return jsonb_build_object('success', true, 'log_id', v_log_id);
end;
$$;

grant execute on function public.log_vehicle_entry(uuid, text, uuid, text, text) to authenticated;

-- ------------------------------------------------------------
-- 2) verify_pre_approval — authorize, scope, and stop leaking  (P0-2)
--
-- Was: no auth check, no society scoping, keyed only on a 6-digit code,
-- returning visitor name, phone, photo and destination flat. With 10^6
-- codes and no rate limit that is a PII harvest across every society.
--
-- Now: caller must be a guard/admin of the visitor's own society, the
-- code must still be live, and failures are logged for throttling.
-- ------------------------------------------------------------

-- Attempt log, so brute force is visible and rate-limitable.
create table if not exists public.pre_approval_verify_attempts (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references auth.users(id) on delete cascade,
  society_id  uuid,
  code_tried  text,
  succeeded   boolean not null default false,
  attempted_at timestamptz not null default now()
);

create index if not exists idx_verify_attempts_actor
  on public.pre_approval_verify_attempts(actor_id, attempted_at desc);

alter table public.pre_approval_verify_attempts enable row level security;

drop policy if exists "verify_attempts_admin_read" on public.pre_approval_verify_attempts;
create policy "verify_attempts_admin_read" on public.pre_approval_verify_attempts
for select to authenticated
using (
  public.is_master_admin()
  or (society_id is not null and public.is_society_admin(society_id))
);

create function public.verify_pre_approval(
  p_approval_code text,
  p_society_id uuid default null
)
returns json
language plpgsql
security definer set search_path = public
as $$
declare
  v_visitor record;
  v_members jsonb;
  v_flat record;
  v_block record;
  v_recent_failures int;
  v_code text := upper(trim(coalesce(p_approval_code, '')));
begin
  if auth.uid() is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  -- Throttle: 10 failed lookups in 5 minutes and this caller is done.
  select count(*) into v_recent_failures
    from public.pre_approval_verify_attempts
   where actor_id = auth.uid()
     and succeeded = false
     and attempted_at > now() - interval '5 minutes';

  if v_recent_failures >= 10 then
    return json_build_object('success', false, 'error', 'Too many attempts. Try again in a few minutes.');
  end if;

  select * into v_visitor
    from public.visitors
   where approval_code = v_code;

  -- Deliberately identical message whether the code is unknown or simply
  -- not the caller's to see, so this cannot be used as an oracle.
  if not found or not public.is_guard_or_admin(v_visitor.society_id)
     or (p_society_id is not null and v_visitor.society_id <> p_society_id) then
    insert into public.pre_approval_verify_attempts (actor_id, society_id, code_tried, succeeded)
    values (auth.uid(), p_society_id, left(v_code, 12), false);
    return json_build_object('success', false, 'error', 'No valid visitor found for this code');
  end if;

  if v_visitor.status in ('denied', 'cancelled', 'expired', 'checked_out') then
    insert into public.pre_approval_verify_attempts (actor_id, society_id, code_tried, succeeded)
    values (auth.uid(), v_visitor.society_id, left(v_code, 12), false);
    return json_build_object('success', false, 'error', 'This pass is no longer valid (' || v_visitor.status || ')');
  end if;

  if v_visitor.valid_until is not null and now() > v_visitor.valid_until then
    insert into public.pre_approval_verify_attempts (actor_id, society_id, code_tried, succeeded)
    values (auth.uid(), v_visitor.society_id, left(v_code, 12), false);
    return json_build_object('success', false, 'error', 'This pass has expired');
  end if;

  insert into public.pre_approval_verify_attempts (actor_id, society_id, code_tried, succeeded)
  values (auth.uid(), v_visitor.society_id, left(v_code, 12), true);

  select * into v_flat from public.flats where id = v_visitor.flat_id;
  select * into v_block from public.blocks where id = v_visitor.block_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', vgm.id,
    'guest_name', vgm.guest_name,
    'guest_phone', vgm.guest_phone
  )), '[]'::jsonb)
  into v_members
  from public.visitor_group_members vgm
  where vgm.visitor_id = v_visitor.id;

  return json_build_object(
    'success', true,
    'visitor', json_build_object(
      'id', v_visitor.id,
      'visitor_name', v_visitor.visitor_name,
      'visitor_phone', v_visitor.visitor_phone,
      'visitor_photo_url', v_visitor.visitor_photo_url,
      'category', v_visitor.category,
      'company_or_context', v_visitor.company_or_context,
      'vehicle_number', v_visitor.vehicle_number,
      'status', v_visitor.status,
      'entry_type', v_visitor.entry_type,
      'duration_type', v_visitor.duration_type,
      'valid_from', v_visitor.valid_from,
      'valid_until', v_visitor.valid_until,
      'approval_code', v_visitor.approval_code,
      'checked_in_at', v_visitor.checked_in_at,
      'checked_out_at', v_visitor.checked_out_at,
      'created_at', v_visitor.created_at
    ),
    'flat_number', v_flat.flat_number,
    'block_name', v_block.name,
    'group_members', v_members
  );
end;
$$;

grant execute on function public.verify_pre_approval(text, uuid) to authenticated;

-- ------------------------------------------------------------
-- 3) check_in_visitor / check_out_visitor — authorize, attribute  (P0-3)
--
-- Was: only "is signed in". Any user could move any visitor through the
-- gate by UUID. The history row also hardcoded changed_by_role, so the
-- audit trail recorded a role the caller may not have held.
-- ------------------------------------------------------------

-- Reports the caller's real role for a society, for audit attribution.
create or replace function public.caller_gate_role(p_society_id uuid)
returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.is_master_admin() then 'society_admin'
    when public.is_society_admin(p_society_id) then 'society_admin'
    when public.is_guard_or_admin(p_society_id) then 'guard'
    else 'resident'
  end;
$$;

grant execute on function public.caller_gate_role(uuid) to authenticated;

create function public.check_in_visitor(
  p_visitor_id uuid,
  p_entry_gate text default null
)
returns json
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_id uuid;
  v_visitor record;
  v_role text;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_visitor from public.visitors where id = p_visitor_id;
  if not found then
    return json_build_object('success', false, 'error', 'Visitor not found');
  end if;

  if not public.is_guard_or_admin(v_visitor.society_id) then
    return json_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_visitor.status != 'approved' then
    return json_build_object('success', false, 'error', 'Visitor must be in approved status to check in. Current: ' || v_visitor.status);
  end if;

  if v_visitor.entry_type = 'pre_approved' then
    if v_visitor.valid_until is not null and now() > v_visitor.valid_until then
      return json_build_object('success', false, 'error', 'Pre-approval has expired');
    end if;
  end if;

  v_role := public.caller_gate_role(v_visitor.society_id);

  update public.visitors set
    status = 'checked_in',
    checked_in_at = now(),
    checked_in_by = v_caller_id,
    entry_gate = coalesce(p_entry_gate, entry_gate)
  where id = p_visitor_id;

  insert into public.visitor_status_history (
    visitor_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_visitor_id, 'approved', 'checked_in', v_caller_id, v_role,
    'Checked in' || case when p_entry_gate is not null then ' at ' || p_entry_gate else '' end
  );

  return json_build_object('success', true);
end;
$$;

grant execute on function public.check_in_visitor(uuid, text) to authenticated;

create function public.check_out_visitor(
  p_visitor_id uuid
)
returns json
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_id uuid;
  v_visitor record;
  v_role text;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_visitor from public.visitors where id = p_visitor_id;
  if not found then
    return json_build_object('success', false, 'error', 'Visitor not found');
  end if;

  if not public.is_guard_or_admin(v_visitor.society_id) then
    return json_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_visitor.status != 'checked_in' then
    return json_build_object('success', false, 'error', 'Visitor must be checked in to check out. Current: ' || v_visitor.status);
  end if;

  v_role := public.caller_gate_role(v_visitor.society_id);

  update public.visitors set
    status = 'checked_out',
    checked_out_at = now(),
    checked_out_by = v_caller_id,
    -- Free the code back into the pool on the way out (see section 4).
    -- qr_payload embeds the same code, so it goes too.
    approval_code = null,
    qr_payload = null
  where id = p_visitor_id;

  insert into public.visitor_status_history (
    visitor_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_visitor_id, 'checked_in', 'checked_out', v_caller_id, v_role, 'Checked out'
  );

  return json_build_object('success', true);
end;
$$;

grant execute on function public.check_out_visitor(uuid) to authenticated;

-- ------------------------------------------------------------
-- 4) generate_approval_code — stop the code space filling up  (P1-8)
--
-- `approval_code` is globally unique and was never cleared, so the 10^6
-- space shrank monotonically across all societies. The generator loops
-- until it finds a free code: fine at 10k rows, ~20 attempts per call at
-- 950k, and a non-terminating loop past 10^6.
--
-- Three changes: release codes on terminal states, widen the alphabet,
-- and bound the loop so it raises instead of spinning forever.
-- ------------------------------------------------------------

-- Reclaim codes from visits that are over. Their pass is dead anyway —
-- verify_pre_approval now rejects these states outright.
update public.visitors
   set approval_code = null, qr_payload = null
 where approval_code is not null
   and status in ('checked_out', 'expired', 'cancelled', 'denied');

create or replace function public.generate_approval_code()
returns text
language plpgsql
security definer set search_path = public as $$
declare
  v_code text;
  v_exists boolean;
  v_attempts int := 0;
  -- Crockford-style: no I, L, O, U — avoids misreads when a guard keys in
  -- a code the visitor is reading off a phone screen.
  v_alphabet text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
begin
  loop
    v_attempts := v_attempts + 1;

    v_code := '';
    for i in 1..8 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;

    select exists(select 1 from public.visitors where approval_code = v_code) into v_exists;
    exit when not v_exists;

    if v_attempts >= 50 then
      raise exception 'Could not allocate a unique approval code after % attempts', v_attempts;
    end if;
  end loop;

  return v_code;
end;
$$;

grant execute on function public.generate_approval_code() to authenticated;

-- 32^8 ≈ 1.1e12 codes, so collisions stay negligible; the bounded loop
-- turns any future exhaustion into a loud error rather than a hang.

-- ------------------------------------------------------------
-- 5) VERIFICATION
-- ------------------------------------------------------------
-- Every security definer function in public that is callable by
-- `authenticated` should appear in a deliberate allow-list. Run this and
-- confirm each result is one you expect to be reachable without an
-- authorization check of its own:
--
--   select p.oid::regprocedure as fn, p.prosecdef as is_definer
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.prosecdef
--      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
--    order by 1;

-- ------------------------------------------------------------
-- 6) raise_sos_alert — suppress duplicate alerts  (P2-23)
--
-- The function correctly verifies the caller is an active resident of the
-- flat, but nothing stopped a second, third or tenth alert. Someone
-- panicking taps repeatedly, and each tap created a row plus an admin
-- notification — burying the original under its own copies.
--
-- An identical alert for the same flat within five minutes now returns the
-- existing one instead of inserting. The caller still gets success, so the
-- resident sees confirmation rather than an error during an emergency.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'raise_sos_alert'
  ) then
    raise notice 'raise_sos_alert not present; skipping dedup guard.';
    return;
  end if;
end $$;

create or replace function public.fn_sos_dedup_guard()
returns trigger
language plpgsql
security definer set search_path = public as $$
declare
  v_existing uuid;
begin
  select id into v_existing
    from public.sos_alerts
   where flat_id = new.flat_id
     and alert_type = new.alert_type
     and status in ('active', 'acknowledged')
     and created_at > now() - interval '5 minutes'
   order by created_at desc
   limit 1;

  if v_existing is not null then
    -- Skip the insert. The caller's RPC still reports success and the
    -- already-open alert keeps its place in the admin queue.
    return null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sos_dedup_guard on public.sos_alerts;
create trigger trg_sos_dedup_guard
  before insert on public.sos_alerts
  for each row execute function public.fn_sos_dedup_guard();
