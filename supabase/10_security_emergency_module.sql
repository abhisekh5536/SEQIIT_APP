-- ============================================================
-- MIGRATION 10: Security & Emergency Contacts Module
-- Includes:
--   1) emergency_contact_categories (admin + global categories)
--   2) emergency_contacts (admin-managed + pre-seeded global numbers)
--   3) emergency_contact_call_logs (tap-to-call attempt logging)
--   4) sos_alerts (resident-initiated emergency alerts)
--   5) sos_alert_status_history (full audit trail for SOS transitions)
--   6) RLS policies, Indexes, Triggers, RPC functions & Seed Data
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE: emergency_contact_categories
-- ------------------------------------------------------------
create table if not exists public.emergency_contact_categories (
  id          uuid primary key default gen_random_uuid(),
  society_id  uuid references public.societies(id) on delete cascade, -- NULL = global/system category
  name        text not null,
  icon_key    text not null default 'shield',                         -- maps to frontend icon set
  sort_order  int not null default 0,
  is_global   boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists idx_ecc_society_sort on public.emergency_contact_categories(society_id, sort_order);
create index if not exists idx_ecc_is_global on public.emergency_contact_categories(is_global);

-- ------------------------------------------------------------
-- 2) TABLE: emergency_contacts
-- ------------------------------------------------------------
create table if not exists public.emergency_contacts (
  id                     uuid primary key default gen_random_uuid(),
  society_id             uuid references public.societies(id) on delete cascade, -- NULL = global contact
  category_id            uuid not null references public.emergency_contact_categories(id) on delete cascade,
  name                   text not null,
  designation            text,                                                   -- e.g. "Head Electrician", "Security Supervisor"
  phone_number           text not null,
  alternate_phone_number text,
  photo_url              text,
  availability           text default '24/7',                                    -- e.g. "24/7", "Mon–Sat 9AM–6PM"
  is_active              boolean not null default true,                          -- soft-disable preserves call logs
  is_global              boolean not null default false,
  sort_order             int not null default 0,
  created_by             uuid references auth.users(id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index if not exists idx_ec_society_cat_active on public.emergency_contacts(society_id, category_id, is_active);
create index if not exists idx_ec_is_global on public.emergency_contacts(is_global);
create index if not exists idx_ec_sort_order on public.emergency_contacts(sort_order);

-- Keep updated_at fresh
drop trigger if exists trg_emergency_contacts_updated on public.emergency_contacts;
create trigger trg_emergency_contacts_updated
before update on public.emergency_contacts
for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3) TABLE: emergency_contact_call_logs
-- Tracks tap-to-call attempts ("who tapped call, on whom, when")
-- ------------------------------------------------------------
create table if not exists public.emergency_contact_call_logs (
  id          uuid primary key default gen_random_uuid(),
  society_id  uuid not null references public.societies(id) on delete cascade,
  contact_id  uuid not null references public.emergency_contacts(id) on delete cascade,
  flat_id     uuid not null references public.flats(id) on delete cascade,
  caller_type text not null default 'resident' check (caller_type in ('resident', 'society_admin')),
  caller_id   uuid not null,                                             -- auth.users(id)
  called_at   timestamptz not null default now()
);

create index if not exists idx_call_logs_society on public.emergency_contact_call_logs(society_id, called_at desc);
create index if not exists idx_call_logs_contact on public.emergency_contact_call_logs(contact_id);
create index if not exists idx_call_logs_flat on public.emergency_contact_call_logs(flat_id, called_at desc);
create index if not exists idx_call_logs_caller on public.emergency_contact_call_logs(caller_id);

-- ------------------------------------------------------------
-- 4) TABLE: sos_alerts
-- Resident-initiated emergency alerts
-- ------------------------------------------------------------
create table if not exists public.sos_alerts (
  id                    uuid primary key default gen_random_uuid(),
  society_id            uuid not null references public.societies(id) on delete cascade,
  flat_id               uuid not null references public.flats(id) on delete cascade,
  raised_by             uuid not null references public.residents(id) on delete cascade,
  alert_type            text not null check (alert_type in ('medical', 'fire', 'theft_security', 'other')),
  note                  text,
  status                text not null default 'active' check (status in ('active', 'acknowledged', 'resolved', 'cancelled')),
  acknowledged_by       uuid references auth.users(id) on delete set null,
  acknowledged_by_role  text check (acknowledged_by_role in ('society_admin', 'guard')),
  acknowledged_at       timestamptz,
  resolved_by           uuid references auth.users(id) on delete set null,
  resolved_at           timestamptz,
  created_at            timestamptz not null default now()
);

create index if not exists idx_sos_alerts_society_status on public.sos_alerts(society_id, status, created_at desc);
create index if not exists idx_sos_alerts_flat on public.sos_alerts(flat_id, status);
create index if not exists idx_sos_alerts_raised_by on public.sos_alerts(raised_by);
create index if not exists idx_sos_alerts_created_at on public.sos_alerts(created_at desc);

-- ------------------------------------------------------------
-- 5) TABLE: sos_alert_status_history
-- Full audit trail for SOS status transitions
-- ------------------------------------------------------------
create table if not exists public.sos_alert_status_history (
  id              uuid primary key default gen_random_uuid(),
  sos_alert_id    uuid not null references public.sos_alerts(id) on delete cascade,
  from_status     text,
  to_status       text not null,
  changed_by      uuid references auth.users(id) on delete set null,
  changed_by_role text not null check (changed_by_role in ('resident', 'society_admin', 'guard', 'system')),
  note            text,
  created_at      timestamptz not null default now()
);

create index if not exists idx_sos_history_alert on public.sos_alert_status_history(sos_alert_id, created_at asc);

-- ------------------------------------------------------------
-- 6) ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------
alter table public.emergency_contact_categories enable row level security;
alter table public.emergency_contacts enable row level security;
alter table public.emergency_contact_call_logs enable row level security;
alter table public.sos_alerts enable row level security;
alter table public.sos_alert_status_history enable row level security;

-- Categories RLS
drop policy if exists "members view categories" on public.emergency_contact_categories;
create policy "members view categories"
on public.emergency_contact_categories for select to authenticated
using (
  is_global = true
  or society_id is null
  or public.is_society_member(society_id)
  or public.is_master_admin()
);

drop policy if exists "admin manage categories" on public.emergency_contact_categories;
create policy "admin manage categories"
on public.emergency_contact_categories for all to authenticated
using (
  is_global = false
  and society_id is not null
  and (public.is_society_admin(society_id) or public.is_master_admin())
)
with check (
  is_global = false
  and society_id is not null
  and (public.is_society_admin(society_id) or public.is_master_admin())
);

-- Contacts RLS
drop policy if exists "members view contacts" on public.emergency_contacts;
create policy "members view contacts"
on public.emergency_contacts for select to authenticated
using (
  is_global = true
  or society_id is null
  or (
    public.is_society_member(society_id)
    and (is_active = true or public.is_society_admin(society_id) or public.is_master_admin())
  )
);

drop policy if exists "admin manage contacts" on public.emergency_contacts;
create policy "admin manage contacts"
on public.emergency_contacts for all to authenticated
using (
  is_global = false
  and society_id is not null
  and (public.is_society_admin(society_id) or public.is_master_admin())
)
with check (
  is_global = false
  and society_id is not null
  and (public.is_society_admin(society_id) or public.is_master_admin())
);

-- Call logs RLS
drop policy if exists "resident insert call log" on public.emergency_contact_call_logs;
create policy "resident insert call log"
on public.emergency_contact_call_logs for insert to authenticated
with check (
  caller_id = auth.uid()
  and (
    public.is_society_admin(society_id)
    or exists (
      select 1 from public.residents r
      where r.user_id = auth.uid()
      and r.flat_id = emergency_contact_call_logs.flat_id
      and r.status = 'active'
    )
  )
);

drop policy if exists "resident view own flat call logs" on public.emergency_contact_call_logs;
create policy "resident view own flat call logs"
on public.emergency_contact_call_logs for select to authenticated
using (
  exists (
    select 1 from public.residents r
    where r.user_id = auth.uid()
    and r.flat_id = emergency_contact_call_logs.flat_id
    and r.status = 'active'
  )
  or public.is_society_admin(society_id)
  or public.is_master_admin()
);

-- SOS alerts RLS
drop policy if exists "resident insert sos alert" on public.sos_alerts;
create policy "resident insert sos alert"
on public.sos_alerts for insert to authenticated
with check (
  exists (
    select 1 from public.residents r
    where r.id = sos_alerts.raised_by
    and r.user_id = auth.uid()
    and r.flat_id = sos_alerts.flat_id
    and r.society_id = sos_alerts.society_id
    and r.status = 'active'
  )
);

drop policy if exists "view sos alerts" on public.sos_alerts;
create policy "view sos alerts"
on public.sos_alerts for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or exists (
    select 1 from public.residents r
    where r.user_id = auth.uid()
    and r.flat_id = sos_alerts.flat_id
    and r.status = 'active'
  )
);

drop policy if exists "update sos alerts" on public.sos_alerts;
create policy "update sos alerts"
on public.sos_alerts for update to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or (
    -- Resident can only cancel their own active/acknowledged alert
    status in ('active', 'acknowledged')
    and exists (
      select 1 from public.residents r
      where r.id = sos_alerts.raised_by
      and r.user_id = auth.uid()
      and r.status = 'active'
    )
  )
);

-- SOS status history RLS
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
      or exists (
        select 1 from public.residents r
        where r.user_id = auth.uid()
        and r.flat_id = s.flat_id
        and r.status = 'active'
      )
    )
  )
);

drop policy if exists "insert sos history" on public.sos_alert_status_history;
create policy "insert sos history"
on public.sos_alert_status_history for insert to authenticated
with check (
  exists (
    select 1 from public.sos_alerts s
    where s.id = sos_alert_status_history.sos_alert_id
    and (
      public.is_society_admin(s.society_id)
      or public.is_master_admin()
      or exists (
        select 1 from public.residents r
        where r.user_id = auth.uid()
        and r.flat_id = s.flat_id
        and r.status = 'active'
      )
    )
  )
);

-- ------------------------------------------------------------
-- 7) UPDATE NOTIFICATIONS TYPE CHECK CONSTRAINT
-- ------------------------------------------------------------
do $$
begin
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
        'sos_alert_raised', 'sos_alert_acknowledged', 'sos_alert_resolved', 'sos_alert_cancelled'
      ));
  exception when others then
    raise notice 'Could not update notifications type check constraint: %', sqlerrm;
  end;
end $$;

-- ------------------------------------------------------------
-- 8) RPC: raise_sos_alert
-- Atomic resident action: inserts alert, status history, and notifies admins
-- ------------------------------------------------------------
create or replace function public.raise_sos_alert(
  p_society_id uuid,
  p_flat_id uuid,
  p_alert_type text,
  p_note text default null
)
returns json as $$
declare
  v_caller_user_id uuid;
  v_resident_id uuid;
  v_resident_name text;
  v_flat_number text;
  v_alert_id uuid;
  v_type_label text;
begin
  v_caller_user_id := auth.uid();
  if v_caller_user_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  -- Validate caller is an active resident of this flat
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

  select f.flat_number into v_flat_number
  from public.flats f
  where f.id = p_flat_id;

  -- Insert SOS alert
  insert into public.sos_alerts (
    society_id, flat_id, raised_by, alert_type, note, status
  ) values (
    p_society_id, p_flat_id, v_resident_id, p_alert_type, p_note, 'active'
  )
  returning id into v_alert_id;

  -- Insert initial status history
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

  -- Notify all society admins immediately
  begin
    insert into public.notifications (
      society_id, target_role, title, body, type, entity_type, entity_id, route
    ) values (
      p_society_id,
      'society_admin',
      '🚨 SOS: Flat ' || coalesce(v_flat_number, 'Unknown') || ' (' || v_type_label || ')',
      coalesce(v_resident_name, 'A resident') || ' triggered ' || v_type_label || '!' ||
        case when p_note is not null and length(trim(p_note)) > 0 then ' Note: ' || p_note else '' end,
      'sos_alert_raised',
      'sos_alert',
      v_alert_id::text,
      '/security'
    );
  exception when others then
    null; -- Notification failure must never block emergency creation
  end;

  return json_build_object(
    'success', true,
    'alert_id', v_alert_id,
    'status', 'active',
    'resident_name', v_resident_name,
    'flat_number', v_flat_number
  );
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 9) RPC: acknowledge_sos_alert (Society Admin / Guard action)
-- ------------------------------------------------------------
create or replace function public.acknowledge_sos_alert(
  p_alert_id uuid,
  p_note text default null
)
returns json as $$
declare
  v_caller_user_id uuid;
  v_alert record;
  v_admin_name text;
begin
  v_caller_user_id := auth.uid();
  if v_caller_user_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_alert from public.sos_alerts where id = p_alert_id;
  if not found then
    return json_build_object('success', false, 'error', 'SOS alert not found');
  end if;

  if not (public.is_society_admin(v_alert.society_id) or public.is_master_admin()) then
    return json_build_object('success', false, 'error', 'Unauthorized: Only society admins can acknowledge SOS alerts');
  end if;

  if v_alert.status != 'active' then
    return json_build_object('success', false, 'error', 'Alert is not in active state (currently ' || v_alert.status || ')');
  end if;

  -- Get admin name
  select name into v_admin_name
  from public.society_admin_users
  where id = v_caller_user_id;

  -- Update alert
  update public.sos_alerts
  set status = 'acknowledged',
      acknowledged_by = v_caller_user_id,
      acknowledged_by_role = 'society_admin',
      acknowledged_at = now()
  where id = p_alert_id;

  -- Insert status history
  insert into public.sos_alert_status_history (
    sos_alert_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_alert_id, 'active', 'acknowledged', v_caller_user_id, 'society_admin',
    coalesce(p_note, 'Alert acknowledged by society admin')
  );

  -- Notify resident who raised the alert
  begin
    insert into public.notifications (
      society_id, user_id, target_role, title, body, type, entity_type, entity_id, route
    )
    select
      v_alert.society_id,
      r.user_id,
      'resident',
      '🛡️ SOS Acknowledged',
      'Society management has acknowledged your emergency and help is on the way.',
      'sos_alert_acknowledged',
      'sos_alert',
      p_alert_id::text,
      '/security'
    from public.residents r
    where r.id = v_alert.raised_by
      and r.user_id is not null;
  exception when others then
    null;
  end;

  return json_build_object('success', true, 'status', 'acknowledged');
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 10) RPC: resolve_sos_alert (Society Admin action)
-- ------------------------------------------------------------
create or replace function public.resolve_sos_alert(
  p_alert_id uuid,
  p_note text default null
)
returns json as $$
declare
  v_caller_user_id uuid;
  v_alert record;
begin
  v_caller_user_id := auth.uid();
  if v_caller_user_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_alert from public.sos_alerts where id = p_alert_id;
  if not found then
    return json_build_object('success', false, 'error', 'SOS alert not found');
  end if;

  if not (public.is_society_admin(v_alert.society_id) or public.is_master_admin()) then
    return json_build_object('success', false, 'error', 'Unauthorized: Only society admins can resolve SOS alerts');
  end if;

  if v_alert.status in ('resolved', 'cancelled') then
    return json_build_object('success', false, 'error', 'Alert is already ' || v_alert.status);
  end if;

  -- Update alert
  update public.sos_alerts
  set status = 'resolved',
      resolved_by = v_caller_user_id,
      resolved_at = now()
  where id = p_alert_id;

  -- Insert status history
  insert into public.sos_alert_status_history (
    sos_alert_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_alert_id, v_alert.status, 'resolved', v_caller_user_id, 'society_admin',
    coalesce(p_note, 'Alert marked resolved')
  );

  -- Notify resident
  begin
    insert into public.notifications (
      society_id, user_id, target_role, title, body, type, entity_type, entity_id, route
    )
    select
      v_alert.society_id,
      r.user_id,
      'resident',
      '✅ SOS Resolved',
      'The emergency alert for your flat has been marked as resolved.',
      'sos_alert_resolved',
      'sos_alert',
      p_alert_id::text,
      '/security'
    from public.residents r
    where r.id = v_alert.raised_by
      and r.user_id is not null;
  exception when others then
    null;
  end;

  return json_build_object('success', true, 'status', 'resolved');
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 11) RPC: cancel_sos_alert (Resident false-alarm cancellation)
-- ------------------------------------------------------------
create or replace function public.cancel_sos_alert(
  p_alert_id uuid,
  p_note text default null
)
returns json as $$
declare
  v_caller_user_id uuid;
  v_alert record;
  v_flat_number text;
begin
  v_caller_user_id := auth.uid();
  if v_caller_user_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_alert from public.sos_alerts where id = p_alert_id;
  if not found then
    return json_build_object('success', false, 'error', 'SOS alert not found');
  end if;

  -- Verify caller is the resident who raised it or belongs to the same flat
  if not exists (
    select 1 from public.residents r
    where r.user_id = v_caller_user_id
      and r.flat_id = v_alert.flat_id
      and r.status = 'active'
  ) and not (public.is_society_admin(v_alert.society_id) or public.is_master_admin()) then
    return json_build_object('success', false, 'error', 'Unauthorized to cancel this SOS alert');
  end if;

  if v_alert.status in ('resolved', 'cancelled') then
    return json_build_object('success', false, 'error', 'Alert is already ' || v_alert.status);
  end if;

  -- Update alert
  update public.sos_alerts
  set status = 'cancelled'
  where id = p_alert_id;

  -- Insert status history
  insert into public.sos_alert_status_history (
    sos_alert_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_alert_id, v_alert.status, 'cancelled', v_caller_user_id, 'resident',
    coalesce(p_note, 'Alert cancelled by resident (False alarm)')
  );

  select flat_number into v_flat_number from public.flats where id = v_alert.flat_id;

  -- Notify admins of cancellation
  begin
    insert into public.notifications (
      society_id, target_role, title, body, type, entity_type, entity_id, route
    ) values (
      v_alert.society_id,
      'society_admin',
      'ℹ️ SOS Cancelled: Flat ' || coalesce(v_flat_number, 'Unknown'),
      'Resident cancelled their emergency alert (False alarm).',
      'sos_alert_cancelled',
      'sos_alert',
      p_alert_id::text,
      '/security'
    );
  exception when others then
    null;
  end;

  return json_build_object('success', true, 'status', 'cancelled');
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 12) RPC: log_emergency_call_attempt
-- Lightweight helper to log dialer tap without blocking
-- ------------------------------------------------------------
create or replace function public.log_emergency_call_attempt(
  p_society_id uuid,
  p_contact_id uuid,
  p_flat_id uuid
)
returns json as $$
declare
  v_caller_user_id uuid;
  v_caller_type text;
  v_log_id uuid;
begin
  v_caller_user_id := auth.uid();
  if v_caller_user_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  if public.is_society_admin(p_society_id) then
    v_caller_type := 'society_admin';
  else
    v_caller_type := 'resident';
  end if;

  insert into public.emergency_contact_call_logs (
    society_id, contact_id, flat_id, caller_type, caller_id, called_at
  ) values (
    p_society_id, p_contact_id, p_flat_id, v_caller_type, v_caller_user_id, now()
  )
  returning id into v_log_id;

  return json_build_object('success', true, 'call_log_id', v_log_id);
end;
$$ language plpgsql security definer;

-- Grant execution permissions
grant execute on function public.raise_sos_alert(uuid, uuid, text, text) to authenticated;
grant execute on function public.acknowledge_sos_alert(uuid, text) to authenticated;
grant execute on function public.resolve_sos_alert(uuid, text) to authenticated;
grant execute on function public.cancel_sos_alert(uuid, text) to authenticated;
grant execute on function public.log_emergency_call_attempt(uuid, uuid, uuid) to authenticated;

-- ------------------------------------------------------------
-- 13) PRE-SEEDED GLOBAL EMERGENCY CATEGORIES & NUMBERS
-- ------------------------------------------------------------
do $$
declare
  v_cat_helpline uuid;
  v_cat_police uuid;
  v_cat_medical uuid;
  v_cat_fire uuid;
  v_cat_disaster uuid;
begin
  -- Category: National Emergency Helplines
  select id into v_cat_helpline from public.emergency_contact_categories
  where is_global = true and name = 'National Emergency Helplines' limit 1;

  if v_cat_helpline is null then
    insert into public.emergency_contact_categories (
      society_id, name, icon_key, sort_order, is_global
    ) values (
      null, 'National Emergency Helplines', 'emergency', 0, true
    ) returning id into v_cat_helpline;
  end if;

  -- Category: Police & Security
  select id into v_cat_police from public.emergency_contact_categories
  where is_global = true and name = 'Police & Security' limit 1;

  if v_cat_police is null then
    insert into public.emergency_contact_categories (
      society_id, name, icon_key, sort_order, is_global
    ) values (
      null, 'Police & Security', 'local_police', 1, true
    ) returning id into v_cat_police;
  end if;

  -- Category: Medical & Ambulance
  select id into v_cat_medical from public.emergency_contact_categories
  where is_global = true and name = 'Medical & Ambulance' limit 1;

  if v_cat_medical is null then
    insert into public.emergency_contact_categories (
      society_id, name, icon_key, sort_order, is_global
    ) values (
      null, 'Medical & Ambulance', 'medical_services', 2, true
    ) returning id into v_cat_medical;
  end if;

  -- Category: Fire & Rescue
  select id into v_cat_fire from public.emergency_contact_categories
  where is_global = true and name = 'Fire & Rescue' limit 1;

  if v_cat_fire is null then
    insert into public.emergency_contact_categories (
      society_id, name, icon_key, sort_order, is_global
    ) values (
      null, 'Fire & Rescue', 'local_fire_department', 3, true
    ) returning id into v_cat_fire;
  end if;

  -- Category: Women & Child Safety
  select id into v_cat_disaster from public.emergency_contact_categories
  where is_global = true and name = 'Women & Child Safety' limit 1;

  if v_cat_disaster is null then
    insert into public.emergency_contact_categories (
      society_id, name, icon_key, sort_order, is_global
    ) values (
      null, 'Women & Child Safety', 'shield', 4, true
    ) returning id into v_cat_disaster;
  end if;

  -- ── Contacts: 112 National Emergency Number ──
  if not exists (select 1 from public.emergency_contacts where is_global = true and phone_number = '112') then
    insert into public.emergency_contacts (
      society_id, category_id, name, designation, phone_number,
      availability, is_active, is_global, sort_order
    ) values (
      null, v_cat_helpline, 'National Emergency Helpline', 'All-in-one Police, Fire & Medical (Pan-India)', '112',
      '24/7 Toll Free', true, true, 0
    );
  end if;

  -- ── Contacts: Police ──
  if not exists (select 1 from public.emergency_contacts where is_global = true and phone_number = '100') then
    insert into public.emergency_contacts (
      society_id, category_id, name, designation, phone_number,
      availability, is_active, is_global, sort_order
    ) values (
      null, v_cat_police, 'Police Control Room', 'Law Enforcement & Distress Assistance', '100',
      '24/7 Toll Free', true, true, 1
    );
  end if;

  -- ── Contacts: Ambulance ──
  if not exists (select 1 from public.emergency_contacts where is_global = true and phone_number = '102') then
    insert into public.emergency_contacts (
      society_id, category_id, name, designation, phone_number, alternate_phone_number,
      availability, is_active, is_global, sort_order
    ) values (
      null, v_cat_medical, 'Emergency Ambulance Service', 'Government Ambulance & Medical First Response', '102', '108',
      '24/7 Toll Free', true, true, 2
    );
  end if;

  -- ── Contacts: Fire ──
  if not exists (select 1 from public.emergency_contacts where is_global = true and phone_number = '101') then
    insert into public.emergency_contacts (
      society_id, category_id, name, designation, phone_number,
      availability, is_active, is_global, sort_order
    ) values (
      null, v_cat_fire, 'Fire Brigade & Rescue', 'Fire Outbreak & Gas Leak Emergency Response', '101',
      '24/7 Toll Free', true, true, 3
    );
  end if;

  -- ── Contacts: Women Helpline ──
  if not exists (select 1 from public.emergency_contacts where is_global = true and phone_number = '1091') then
    insert into public.emergency_contacts (
      society_id, category_id, name, designation, phone_number, alternate_phone_number,
      availability, is_active, is_global, sort_order
    ) values (
      null, v_cat_disaster, 'Women in Distress Helpline', 'National Women Safety & Support', '1091', '181',
      '24/7 Toll Free', true, true, 4
    );
  end if;

  -- ── Contacts: Disaster Management ──
  if not exists (select 1 from public.emergency_contacts where is_global = true and phone_number = '1078') then
    insert into public.emergency_contacts (
      society_id, category_id, name, designation, phone_number,
      availability, is_active, is_global, sort_order
    ) values (
      null, v_cat_helpline, 'National Disaster Helpline (NDMA)', 'Floods, Earthquakes & Building Collapse', '1078',
      '24/7 Toll Free', true, true, 5
    );
  end if;

end $$;

-- ------------------------------------------------------------
-- 14) Enable Realtime for SOS Alerts table
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sos_alerts'
  ) then
    alter publication supabase_realtime add table public.sos_alerts;
  end if;
exception when others then
  raise notice 'Could not add sos_alerts to realtime publication: %', sqlerrm;
end $$;
