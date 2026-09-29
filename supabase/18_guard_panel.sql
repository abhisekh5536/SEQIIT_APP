-- ============================================================
-- 18) GUARD PANEL
--
-- Everything the gate app needs beyond identity (migration 17):
--
--   1) notifications can target guards
--   2) visitors: tighter guard access, `approved_via`
--   3) guard_call_logs + guard_call_flat   — call a flat without ever
--                                            listing resident numbers
--   4) guard_resolve_gate_request          — record what the resident said
--                                            on the phone, or turn away
--   5) fetch_expected_visitors             — today's pre-approvals, no codes
--   6) SOS reaches guards                  — read, acknowledge, respond,
--                                            resolve; duplicate-tap fix
--   7) emergency contacts readable by guards
--
-- Rule kept from migration 14: a guard never approves on a resident's
-- behalf. The one exception is recording a decision the resident gave on
-- a phone call, and that is only accepted after a logged call to that
-- flat, is marked approved_via = 'guard_call', and the flat is told.
--
-- Prerequisites: migrations 07, 09, 10, 14, 15, 16, 17.
-- Idempotent: safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1) NOTIFICATIONS FOR GUARDS
--
-- The target_role check is an inline constraint from migration 07; find
-- it by definition rather than trusting its generated name.
-- ------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select c.conname
      from pg_constraint c
     where c.conrelid = 'public.notifications'::regclass
       and c.contype = 'c'
       and pg_get_constraintdef(c.oid) ilike '%target_role%'
  loop
    execute format('alter table public.notifications drop constraint %I', r.conname);
  end loop;

  alter table public.notifications add constraint notifications_target_role_check
    check (target_role in ('resident', 'society_admin', 'guard', 'all'));
end $$;

drop policy if exists "guards view guard notifications" on public.notifications;
create policy "guards view guard notifications"
on public.notifications for select to authenticated
using (
  public.is_society_guard(society_id)
  and user_id is null
  and target_role in ('guard', 'all')
);
-- Rows addressed to one guard (user_id = auth.uid()) are already covered
-- by "residents view own notifications" from migration 07.

-- ------------------------------------------------------------
-- 2) VISITORS
-- ------------------------------------------------------------
alter table public.visitors
  add column if not exists approved_via text
  check (approved_via is null or approved_via in ('resident_app', 'guard_call'));

-- A guard needs the last week and anyone still expected or inside — not
-- the society's full visitor history. Admins keep their own full policy.
drop policy if exists "guard read society visitors" on public.visitors;
create policy "guard read society visitors"
on public.visitors for select to authenticated
using (
  public.is_society_guard(society_id)
  and (
    created_at > now() - interval '7 days'
    or status in ('approved', 'checked_in')
  )
);

-- Direct inserts (the client fallback for databases without the RPC) get
-- the same rules create_visitor_entry enforces: honest attribution, and a
-- flat inside the guard's own society.
drop policy if exists "guard log gate request" on public.visitors;
create policy "guard log gate request"
on public.visitors for insert to authenticated
with check (
  public.is_society_guard(society_id)
  and entry_type = 'gate_request'
  and status = 'pending_approval'
  and created_by_type = 'guard'
  and created_by = auth.uid()
  and exists (
    select 1 from public.flats f
    join public.blocks b on b.id = f.block_id
    where f.id = visitors.flat_id
      and b.society_id = visitors.society_id
  )
);

-- Migration 14 let guards UPDATE approved / checked-in rows directly. The
-- policy constrained the status but not the other columns, so a guard
-- could rewrite a visitor's name or flat. Every guard write now goes
-- through a security-definer RPC (check_in_visitor, check_out_visitor,
-- guard_resolve_gate_request), each with its own checks.
drop policy if exists "guard check in out visitor" on public.visitors;

-- Status history: a guard may only append rows that say they are theirs.
-- Before, a guard could insert a row claiming changed_by_role='resident'
-- and forge an approval into the audit trail.
drop policy if exists "guard append visitor_status_history" on public.visitor_status_history;
create policy "guard append visitor_status_history"
on public.visitor_status_history for insert to authenticated
with check (
  changed_by = auth.uid()
  and changed_by_role = 'guard'
  and exists (
    select 1 from public.visitors v
    where v.id = visitor_status_history.visitor_id
      and public.is_society_guard(v.society_id)
  )
);

-- ------------------------------------------------------------
-- 3) CALLING A FLAT
--
-- The guard never sees a list of resident numbers. Tapping "Call flat"
-- asks this function for one number, which is logged against the guard,
-- the flat and (if any) the visitor waiting at the gate, and throttled so
-- it cannot be used to walk the whole society's phone book.
--
-- Honest limit: once dialled, the number is in the guard phone's call
-- log. Real masking needs a telephony bridge (Exotel, Knowlarity).
-- ------------------------------------------------------------
create table if not exists public.guard_call_logs (
  id          uuid primary key default gen_random_uuid(),
  society_id  uuid not null references public.societies(id) on delete cascade,
  caller_id   uuid not null references auth.users(id) on delete cascade,
  guard_id    uuid references public.society_guards(id) on delete set null,
  flat_id     uuid not null references public.flats(id) on delete cascade,
  resident_id uuid references public.residents(id) on delete set null,
  reason      text not null default 'other'
                check (reason in ('visitor_no_response', 'sos', 'vehicle', 'other')),
  visitor_id  uuid references public.visitors(id) on delete set null,
  called_at   timestamptz not null default now()
);

create index if not exists idx_guard_call_logs_society
  on public.guard_call_logs(society_id, called_at desc);
create index if not exists idx_guard_call_logs_caller
  on public.guard_call_logs(caller_id, called_at desc);
create index if not exists idx_guard_call_logs_visitor
  on public.guard_call_logs(visitor_id);

alter table public.guard_call_logs enable row level security;

drop policy if exists "guard_call_logs_admin_read" on public.guard_call_logs;
create policy "guard_call_logs_admin_read" on public.guard_call_logs
for select to authenticated
using (public.is_society_admin(society_id) or public.is_master_admin());

drop policy if exists "guard_call_logs_own_read" on public.guard_call_logs;
create policy "guard_call_logs_own_read" on public.guard_call_logs
for select to authenticated
using (caller_id = auth.uid());
-- No insert policy: rows are written only by guard_call_flat.

create or replace function public.guard_call_flat(
  p_flat_id uuid,
  p_reason text default 'other',
  p_visitor_id uuid default null
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_society_id uuid;
  v_resident record;
  v_recent int;
  v_log_id uuid;
  v_reason text := coalesce(nullif(trim(p_reason), ''), 'other');
begin
  if auth.uid() is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select b.society_id into v_society_id
    from public.flats f
    join public.blocks b on b.id = f.block_id
   where f.id = p_flat_id;

  if v_society_id is null or not public.is_guard_or_admin(v_society_id) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_reason not in ('visitor_no_response', 'sos', 'vehicle', 'other') then
    v_reason := 'other';
  end if;

  if p_visitor_id is not null and not exists (
    select 1 from public.visitors v
     where v.id = p_visitor_id and v.flat_id = p_flat_id
  ) then
    return jsonb_build_object('success', false, 'error', 'That visitor is not for this flat');
  end if;

  -- A guard dialling through the society is harvesting numbers, not
  -- working the gate.
  select count(*) into v_recent
    from public.guard_call_logs
   where caller_id = auth.uid()
     and called_at > now() - interval '10 minutes';

  if v_recent >= 20 then
    return jsonb_build_object('success', false,
      'error', 'Too many calls in a short time. Use the intercom or contact the office.');
  end if;

  select r.id, r.full_name, r.phone into v_resident
    from public.residents r
   where r.flat_id = p_flat_id
     and r.status = 'active'
     and nullif(trim(coalesce(r.phone, '')), '') is not null
   order by r.is_primary desc, r.created_at asc
   limit 1;

  if not found then
    return jsonb_build_object('success', false, 'error', 'No phone number on file for this flat');
  end if;

  insert into public.guard_call_logs (
    society_id, caller_id, guard_id, flat_id, resident_id, reason, visitor_id
  ) values (
    v_society_id,
    auth.uid(),
    (select g.id from public.society_guards g
      where g.user_id = auth.uid() and g.society_id = v_society_id),
    p_flat_id,
    v_resident.id,
    v_reason,
    p_visitor_id
  )
  returning id into v_log_id;

  return jsonb_build_object(
    'success', true,
    'phone', v_resident.phone,
    'resident_first_name', nullif(split_part(trim(coalesce(v_resident.full_name, '')), ' ', 1), ''),
    'call_log_id', v_log_id
  );
end;
$$;

grant execute on function public.guard_call_flat(uuid, text, uuid) to authenticated;

-- ------------------------------------------------------------
-- 4) guard_resolve_gate_request
--
--   approved / denied — what the resident said on a phone call. Only
--                       after a call this caller logged to this flat in
--                       the last 15 minutes.
--   expired           — nobody answered; the visitor was turned away.
-- ------------------------------------------------------------
create or replace function public.guard_resolve_gate_request(
  p_visitor_id uuid,
  p_action text,
  p_note text default null
)
returns json
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_visitor record;
  v_role text;
  v_code text;
  v_by text;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if v_caller is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_visitor from public.visitors where id = p_visitor_id for update;
  if not found then
    return json_build_object('success', false, 'error', 'Visitor not found');
  end if;

  if not public.is_guard_or_admin(v_visitor.society_id) then
    return json_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_visitor.entry_type <> 'gate_request' then
    return json_build_object('success', false, 'error', 'Only gate requests can be resolved at the gate');
  end if;

  if v_visitor.status <> 'pending_approval' then
    return json_build_object('success', false, 'error', 'This request is already ' || v_visitor.status);
  end if;

  if p_action not in ('approved', 'denied', 'expired') then
    return json_build_object('success', false, 'error', 'Invalid action');
  end if;

  if p_action in ('approved', 'denied') and not exists (
    select 1 from public.guard_call_logs l
     where l.caller_id = v_caller
       and l.flat_id = v_visitor.flat_id
       and l.called_at > now() - interval '15 minutes'
       and (l.visitor_id is null or l.visitor_id = p_visitor_id)
  ) then
    return json_build_object('success', false,
      'error', 'Call the flat first. A decision taken on the phone must follow a logged call.');
  end if;

  if p_action = 'denied' and v_note is null then
    return json_build_object('success', false, 'error', 'Note what the resident said');
  end if;

  v_role := public.caller_gate_role(v_visitor.society_id);

  select g.full_name into v_by
    from public.society_guards g
   where g.user_id = v_caller and g.society_id = v_visitor.society_id;
  v_by := coalesce(v_by, 'the gate');

  if p_action = 'approved' then
    v_code := public.generate_approval_code();

    update public.visitors set
      status = 'approved',
      approved_by = v_caller,
      approved_at = now(),
      approved_via = 'guard_call',
      approval_code = v_code,
      qr_payload = 'SAQIIT:' || v_code
    where id = p_visitor_id;

    insert into public.visitor_status_history (
      visitor_id, from_status, to_status, changed_by, changed_by_role, note
    ) values (
      p_visitor_id, 'pending_approval', 'approved', v_caller, v_role,
      'Resident approved on a phone call · recorded by ' || v_by
        || coalesce(' · ' || v_note, '')
    );
  elsif p_action = 'denied' then
    update public.visitors set
      status = 'denied',
      denied_by = v_caller,
      denied_at = now(),
      denied_reason = v_note
    where id = p_visitor_id;

    insert into public.visitor_status_history (
      visitor_id, from_status, to_status, changed_by, changed_by_role, note
    ) values (
      p_visitor_id, 'pending_approval', 'denied', v_caller, v_role,
      'Resident refused on a phone call · recorded by ' || v_by || ' · ' || v_note
    );
  else
    update public.visitors set status = 'expired' where id = p_visitor_id;

    insert into public.visitor_status_history (
      visitor_id, from_status, to_status, changed_by, changed_by_role, note
    ) values (
      p_visitor_id, 'pending_approval', 'expired', v_caller, v_role,
      'No answer from the flat · turned away by ' || v_by
    );
  end if;

  update public.notifications
     set is_read = true
   where entity_type = 'visitor'
     and entity_id = p_visitor_id::text
     and type = 'visitor_approval_request';

  -- Tell the flat what the gate recorded in their name.
  begin
    insert into public.notifications (
      society_id, user_id, target_role,
      title, body, type, entity_type, entity_id, route
    )
    select
      v_visitor.society_id, r.user_id, 'resident',
      case p_action
        when 'approved' then '📞 Allowed after call: ' || v_visitor.visitor_name
        when 'denied'   then '📞 Turned away after call: ' || v_visitor.visitor_name
        else                 '🚪 Missed visitor: ' || v_visitor.visitor_name
      end,
      case p_action
        when 'approved' then 'The gate recorded that your flat approved this visitor on the phone. Not you? Contact the society office.'
        when 'denied'   then 'The gate recorded that your flat refused this visitor on the phone.'
        else                 'Nobody answered, so the gate turned this visitor away.'
      end,
      case p_action
        when 'approved' then 'visitor_approved'
        when 'denied'   then 'visitor_denied'
        else                 'visitor_expired'
      end,
      'visitor', p_visitor_id::text, '/visitors'
    from public.residents r
    where r.flat_id = v_visitor.flat_id
      and r.status = 'active'
      and r.user_id is not null;
  exception when others then
    null;
  end;

  return json_build_object('success', true, 'status', p_action, 'approval_code', v_code);
end;
$$;

grant execute on function public.guard_resolve_gate_request(uuid, text, text) to authenticated;

-- ------------------------------------------------------------
-- 5) fetch_expected_visitors
--
-- Pre-approvals active now or starting within 12 hours. Deliberately
-- leaves out approval_code: the visitor has to show it.
-- ------------------------------------------------------------
create or replace function public.fetch_expected_visitors(p_society_id uuid)
returns jsonb
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if not public.is_guard_or_admin(p_society_id) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  select coalesce(jsonb_agg(s.item order by s.valid_from nulls first), '[]'::jsonb)
    into v_rows
    from (
      select
        v.valid_from,
        jsonb_build_object(
          'id', v.id,
          'visitor_name', v.visitor_name,
          'category', v.category,
          'company_or_context', v.company_or_context,
          'vehicle_number', v.vehicle_number,
          'duration_type', v.duration_type,
          'valid_from', v.valid_from,
          'valid_until', v.valid_until,
          'flat_id', v.flat_id,
          'flat_number', f.flat_number,
          'block_name', b.name,
          'group_size', (
            select count(*) from public.visitor_group_members m
             where m.visitor_id = v.id
          )
        ) as item
      from public.visitors v
      join public.flats f on f.id = v.flat_id
      left join public.blocks b on b.id = f.block_id
      where v.society_id = p_society_id
        and v.entry_type = 'pre_approved'
        and v.status = 'approved'
        and (v.valid_from is null or v.valid_from <= now() + interval '12 hours')
        and (v.valid_until is null or v.valid_until >= now())
      order by v.valid_from nulls first
      limit 100
    ) s;

  return jsonb_build_object('success', true, 'visitors', v_rows);
end;
$$;

grant execute on function public.fetch_expected_visitors(uuid) to authenticated;

-- ------------------------------------------------------------
-- 6) SOS REACHES GUARDS
--
-- The resident SOS screen has always said "Instant alert to Guards &
-- Admin". Until now guards could not read sos_alerts at all.
-- ------------------------------------------------------------
drop policy if exists "view sos alerts" on public.sos_alerts;
create policy "view sos alerts"
on public.sos_alerts for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or (public.is_society_guard(society_id) and created_at > now() - interval '30 days')
  or exists (
    select 1 from public.residents r
    where r.user_id = auth.uid()
      and r.flat_id = sos_alerts.flat_id
      and r.status = 'active'
  )
);

drop policy if exists "view sos history" on public.sos_alert_status_history;
create policy "view sos history"
on public.sos_alert_status_history for select to authenticated
using (
  exists (
    select 1 from public.sos_alerts s
    where s.id = sos_alert_status_history.sos_alert_id
      and (
        public.is_society_admin(s.society_id)
        or public.is_master_admin()
        or public.is_society_guard(s.society_id)
        or exists (
          select 1 from public.residents r
          where r.user_id = auth.uid()
            and r.flat_id = s.flat_id
            and r.status = 'active'
        )
      )
  )
);

-- Guards cannot read `residents`, so the usual embedded select gives them
-- an alert without a name. This returns the same nested shape the app
-- already parses, with the resident's name and without their phone.
create or replace function public.fetch_gate_sos_alerts(
  p_society_id uuid,
  p_include_closed boolean default false
)
returns jsonb
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if not public.is_guard_or_admin(p_society_id) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  select coalesce(jsonb_agg(s.item order by s.created_at desc), '[]'::jsonb)
    into v_rows
    from (
      select
        a.created_at,
        to_jsonb(a) || jsonb_build_object(
          'flats', jsonb_build_object(
            'flat_number', f.flat_number,
            'blocks', jsonb_build_object('name', b.name)
          ),
          'residents', jsonb_build_object('full_name', r.full_name)
        ) as item
      from public.sos_alerts a
      join public.flats f on f.id = a.flat_id
      left join public.blocks b on b.id = f.block_id
      left join public.residents r on r.id = a.raised_by
      where a.society_id = p_society_id
        and (
          a.status in ('active', 'acknowledged')
          or (p_include_closed and a.created_at > now() - interval '7 days')
        )
      order by a.created_at desc
      limit 50
    ) s;

  return jsonb_build_object('success', true, 'alerts', v_rows);
end;
$$;

grant execute on function public.fetch_gate_sos_alerts(uuid, boolean) to authenticated;

-- raise_sos_alert: now also alerts guards, and survives the dedup trigger.
--
-- Migration 15's fn_sos_dedup_guard returns NULL to skip a repeat alert.
-- The old body then carried on with a NULL alert id and failed on the
-- status-history insert (sos_alert_id is NOT NULL) — so a panicked second
-- tap got an error instead of the confirmation the trigger promised.
create or replace function public.raise_sos_alert(
  p_society_id uuid,
  p_flat_id uuid,
  p_alert_type text,
  p_note text default null
)
returns json
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_user_id uuid := auth.uid();
  v_resident_id uuid;
  v_resident_name text;
  v_flat_number text;
  v_alert_id uuid;
  v_type_label text;
  v_title text;
  v_body text;
begin
  if v_caller_user_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select r.id, r.full_name into v_resident_id, v_resident_name
    from public.residents r
   where r.user_id = v_caller_user_id
     and r.flat_id = p_flat_id
     and r.society_id = p_society_id
     and r.status = 'active'
   limit 1;

  if v_resident_id is null then
    return json_build_object('success', false, 'error', 'User is not an active resident of the specified flat');
  end if;

  select f.flat_number into v_flat_number from public.flats f where f.id = p_flat_id;

  insert into public.sos_alerts (
    society_id, flat_id, raised_by, alert_type, note, status
  ) values (
    p_society_id, p_flat_id, v_resident_id, p_alert_type, p_note, 'active'
  )
  returning id into v_alert_id;

  if v_alert_id is null then
    -- The dedup trigger kept the earlier alert. Hand that one back so the
    -- resident still gets a confirmation.
    select a.id into v_alert_id
      from public.sos_alerts a
     where a.flat_id = p_flat_id
       and a.alert_type = p_alert_type
       and a.status in ('active', 'acknowledged')
     order by a.created_at desc
     limit 1;

    return json_build_object(
      'success', true,
      'alert_id', v_alert_id,
      'status', 'active',
      'deduplicated', true,
      'resident_name', v_resident_name,
      'flat_number', v_flat_number
    );
  end if;

  insert into public.sos_alert_status_history (
    sos_alert_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    v_alert_id, null, 'active', v_caller_user_id, 'resident',
    coalesce(p_note, 'Emergency SOS raised')
  );

  v_type_label := case p_alert_type
    when 'medical' then 'Medical Emergency'
    when 'fire' then 'Fire / Gas Leak'
    when 'theft_security' then 'Theft / Intrusion'
    else 'Emergency'
  end;

  v_title := '🚨 SOS: Flat ' || coalesce(v_flat_number, 'Unknown') || ' (' || v_type_label || ')';
  v_body := coalesce(v_resident_name, 'A resident') || ' triggered ' || v_type_label || '!' ||
    case when p_note is not null and length(trim(p_note)) > 0 then ' Note: ' || p_note else '' end;

  begin
    insert into public.notifications (
      society_id, target_role, title, body, type, entity_type, entity_id, route
    ) values
      (p_society_id, 'society_admin', v_title, v_body, 'sos_alert_raised', 'sos_alert', v_alert_id::text, '/security'),
      (p_society_id, 'guard',         v_title, v_body, 'sos_alert_raised', 'sos_alert', v_alert_id::text, '/security');
  exception when others then
    null; -- A notification failure must never block the emergency itself
  end;

  return json_build_object(
    'success', true,
    'alert_id', v_alert_id,
    'status', 'active',
    'resident_name', v_resident_name,
    'flat_number', v_flat_number
  );
end;
$$;

grant execute on function public.raise_sos_alert(uuid, uuid, text, text) to authenticated;

-- Responder name for SOS notes and notifications.
create or replace function public.gate_responder_name(p_society_id uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select g.full_name from public.society_guards g
      where g.user_id = auth.uid() and g.society_id = p_society_id),
    (select a.name from public.society_admin_users a where a.id = auth.uid()),
    'Security'
  );
$$;

grant execute on function public.gate_responder_name(uuid) to authenticated;

create or replace function public.acknowledge_sos_alert(
  p_alert_id uuid,
  p_note text default null
)
returns json
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_alert record;
  v_role text;
  v_name text;
  v_flat_number text;
begin
  if v_caller is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_alert from public.sos_alerts where id = p_alert_id for update;
  if not found then
    return json_build_object('success', false, 'error', 'SOS alert not found');
  end if;

  if not public.is_guard_or_admin(v_alert.society_id) then
    return json_build_object('success', false,
      'error', 'Unauthorized: only society admins and guards can acknowledge SOS alerts');
  end if;

  if v_alert.status <> 'active' then
    return json_build_object('success', false,
      'error', 'Alert is not in active state (currently ' || v_alert.status || ')');
  end if;

  v_role := public.caller_gate_role(v_alert.society_id);
  v_name := public.gate_responder_name(v_alert.society_id);

  update public.sos_alerts
     set status = 'acknowledged',
         acknowledged_by = v_caller,
         acknowledged_by_role = v_role,
         acknowledged_at = now()
   where id = p_alert_id;

  insert into public.sos_alert_status_history (
    sos_alert_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_alert_id, 'active', 'acknowledged', v_caller, v_role,
    coalesce(nullif(trim(p_note), ''),
      case when v_role = 'guard' then 'Acknowledged by guard ' || v_name
           else 'Alert acknowledged by society admin' end)
  );

  begin
    insert into public.notifications (
      society_id, user_id, target_role, title, body, type, entity_type, entity_id, route
    )
    select
      v_alert.society_id, r.user_id, 'resident',
      '🛡️ SOS Acknowledged',
      case when v_role = 'guard'
        then v_name || ' from the gate has seen your alert and is on the way.'
        else 'Society management has acknowledged your emergency and help is on the way.'
      end,
      'sos_alert_acknowledged', 'sos_alert', p_alert_id::text, '/security'
    from public.residents r
    where r.id = v_alert.raised_by
      and r.user_id is not null;

    if v_role = 'guard' then
      select f.flat_number into v_flat_number from public.flats f where f.id = v_alert.flat_id;
      insert into public.notifications (
        society_id, target_role, title, body, type, entity_type, entity_id, route
      ) values (
        v_alert.society_id, 'society_admin',
        '🛡️ Guard responding: Flat ' || coalesce(v_flat_number, 'Unknown'),
        v_name || ' acknowledged the SOS alert.',
        'sos_alert_acknowledged', 'sos_alert', p_alert_id::text, '/security'
      );
    end if;
  exception when others then
    null;
  end;

  return json_build_object('success', true, 'status', 'acknowledged');
end;
$$;

grant execute on function public.acknowledge_sos_alert(uuid, text) to authenticated;

create or replace function public.resolve_sos_alert(
  p_alert_id uuid,
  p_note text default null
)
returns json
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_alert record;
  v_role text;
  v_name text;
  v_flat_number text;
begin
  if v_caller is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_alert from public.sos_alerts where id = p_alert_id for update;
  if not found then
    return json_build_object('success', false, 'error', 'SOS alert not found');
  end if;

  if not public.is_guard_or_admin(v_alert.society_id) then
    return json_build_object('success', false,
      'error', 'Unauthorized: only society admins and guards can resolve SOS alerts');
  end if;

  if v_alert.status in ('resolved', 'cancelled') then
    return json_build_object('success', false, 'error', 'Alert is already ' || v_alert.status);
  end if;

  v_role := public.caller_gate_role(v_alert.society_id);
  v_name := public.gate_responder_name(v_alert.society_id);

  update public.sos_alerts
     set status = 'resolved',
         resolved_by = v_caller,
         resolved_at = now()
   where id = p_alert_id;

  insert into public.sos_alert_status_history (
    sos_alert_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_alert_id, v_alert.status, 'resolved', v_caller, v_role,
    coalesce(nullif(trim(p_note), ''), 'Alert marked resolved')
      || case when v_role = 'guard' then ' · by guard ' || v_name else '' end
  );

  begin
    insert into public.notifications (
      society_id, user_id, target_role, title, body, type, entity_type, entity_id, route
    )
    select
      v_alert.society_id, r.user_id, 'resident',
      '✅ SOS Resolved',
      'The emergency alert for your flat has been marked as resolved.',
      'sos_alert_resolved', 'sos_alert', p_alert_id::text, '/security'
    from public.residents r
    where r.id = v_alert.raised_by
      and r.user_id is not null;

    if v_role = 'guard' then
      select f.flat_number into v_flat_number from public.flats f where f.id = v_alert.flat_id;
      insert into public.notifications (
        society_id, target_role, title, body, type, entity_type, entity_id, route
      ) values (
        v_alert.society_id, 'society_admin',
        '✅ SOS closed by guard: Flat ' || coalesce(v_flat_number, 'Unknown'),
        v_name || ': ' || coalesce(nullif(trim(p_note), ''), 'marked resolved'),
        'sos_alert_resolved', 'sos_alert', p_alert_id::text, '/security'
      );
    end if;
  exception when others then
    null;
  end;

  return json_build_object('success', true, 'status', 'resolved');
end;
$$;

grant execute on function public.resolve_sos_alert(uuid, text) to authenticated;

-- A progress note on an open alert ("Reached flat", "Ambulance called").
-- Guards cannot insert status history directly, so this is the way in.
create or replace function public.log_sos_response(
  p_alert_id uuid,
  p_note text
)
returns json
language plpgsql
security definer set search_path = public
as $$
declare
  v_alert record;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if auth.uid() is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  if v_note is null then
    return json_build_object('success', false, 'error', 'Note is required');
  end if;

  select * into v_alert from public.sos_alerts where id = p_alert_id;
  if not found then
    return json_build_object('success', false, 'error', 'SOS alert not found');
  end if;

  if not public.is_guard_or_admin(v_alert.society_id) then
    return json_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_alert.status not in ('active', 'acknowledged') then
    return json_build_object('success', false, 'error', 'Alert is already ' || v_alert.status);
  end if;

  insert into public.sos_alert_status_history (
    sos_alert_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_alert_id, v_alert.status, v_alert.status, auth.uid(),
    public.caller_gate_role(v_alert.society_id),
    left(v_note, 280) || ' · ' || public.gate_responder_name(v_alert.society_id)
  );

  return json_build_object('success', true);
end;
$$;

grant execute on function public.log_sos_response(uuid, text) to authenticated;

-- ------------------------------------------------------------
-- 7) EMERGENCY CONTACTS FOR GUARDS
--
-- is_society_member() counts admins and residents only, so a guard saw
-- the national helplines but not the society's own plumber, electrician
-- or facility manager — the numbers the gate actually rings.
-- ------------------------------------------------------------
drop policy if exists "members view categories" on public.emergency_contact_categories;
create policy "members view categories"
on public.emergency_contact_categories for select to authenticated
using (
  is_global = true
  or society_id is null
  or public.is_society_member(society_id)
  or public.is_society_guard(society_id)
  or public.is_master_admin()
);

drop policy if exists "members view contacts" on public.emergency_contacts;
create policy "members view contacts"
on public.emergency_contacts for select to authenticated
using (
  is_global = true
  or society_id is null
  or (
    (public.is_society_member(society_id) or public.is_society_guard(society_id))
    and (is_active = true or public.is_society_admin(society_id) or public.is_master_admin())
  )
);

-- ------------------------------------------------------------
-- 8) DELIBERATELY NOT GRANTED TO GUARDS
--
--   residents, resident_join_requests, complaints, dues/billing,
--   parking_bay_requests, notice read stats, admin tables.
-- A guard gets flat numbers and first names through the RPCs above and
-- nothing else about who lives where.
-- ------------------------------------------------------------
