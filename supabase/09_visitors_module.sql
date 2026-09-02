-- ============================================================
-- MIGRATION 09: Visitor Management Module
-- Gate-initiated + Pre-approved visitor flows with full
-- audit trail, approval codes, and notification integration.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE: visitors
-- Core visitor record — covers BOTH flows (gate-initiated and pre-approved)
-- ------------------------------------------------------------
create table if not exists public.visitors (
  id                  uuid primary key default gen_random_uuid(),
  society_id          uuid not null references public.societies(id) on delete cascade,
  flat_id             uuid not null references public.flats(id) on delete cascade,
  block_id            uuid references public.blocks(id),

  -- who created this record
  created_by_type     text not null check (created_by_type in ('resident','society_admin','guard')),
  created_by          uuid not null,

  -- visitor identity
  visitor_name        text not null,
  visitor_phone       text,
  visitor_photo_url   text,
  vehicle_number      text,

  category            text not null check (category in ('delivery','guest','group_invite','cab','others')),
  company_or_context  text,

  entry_type          text not null check (entry_type in ('gate_request','pre_approved')),

  status              text not null default 'pending_approval' check (status in (
                        'pending_approval', 'approved', 'denied', 'expired',
                        'checked_in', 'checked_out', 'cancelled'
                      )),

  -- pre-approval specific
  approval_code       text unique,
  qr_payload          text,
  duration_type       text check (duration_type in ('one_day','long_duration')),
  valid_from          timestamptz,
  valid_until         timestamptz,
  is_private          boolean not null default false,

  -- approval / denial
  approved_by         uuid,
  approved_at         timestamptz,
  denied_by           uuid,
  denied_at           timestamptz,
  denied_reason       text,

  -- gate check-in/out (Guard panel will populate these later; schema ready now)
  entry_gate          text,
  checked_in_at       timestamptz,
  checked_in_by       uuid,
  checked_out_at      timestamptz,
  checked_out_by      uuid,

  save_as_frequent    boolean not null default false,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2) TABLE: visitor_group_members
-- Multiple guests under a single pre-approval (Group Invite)
-- ------------------------------------------------------------
create table if not exists public.visitor_group_members (
  id          uuid primary key default gen_random_uuid(),
  visitor_id  uuid not null references public.visitors(id) on delete cascade,
  guest_name  text not null,
  guest_phone text,
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 3) TABLE: visitor_status_history
-- Full audit trail — same pattern as complaint_status_history
-- ------------------------------------------------------------
create table if not exists public.visitor_status_history (
  id              uuid primary key default gen_random_uuid(),
  visitor_id      uuid not null references public.visitors(id) on delete cascade,
  from_status     text,
  to_status       text not null,
  changed_by      uuid not null,
  changed_by_role text not null check (changed_by_role in ('resident','society_admin','guard','system')),
  note            text,
  created_at      timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 4) INDEXES
-- Performance for admin dashboard + resident feed
-- ------------------------------------------------------------
create index if not exists idx_visitors_society_status on public.visitors (society_id, status);
create index if not exists idx_visitors_flat_status on public.visitors (flat_id, status);
create index if not exists idx_visitors_approval_code on public.visitors (approval_code);
create index if not exists idx_visitors_created_at on public.visitors (created_at desc);
create index if not exists idx_visitor_group_members_visitor on public.visitor_group_members (visitor_id);
create index if not exists idx_visitor_status_history_visitor on public.visitor_status_history (visitor_id, created_at);

-- ------------------------------------------------------------
-- 5) ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------
alter table public.visitors enable row level security;
alter table public.visitor_group_members enable row level security;
alter table public.visitor_status_history enable row level security;

-- Master admin: full access
drop policy if exists "master admins full access to visitors" on public.visitors;
create policy "master admins full access to visitors"
on public.visitors for all to authenticated
using (public.is_master_admin());

-- Society Admin: full access scoped to own society
drop policy if exists "society admin full access visitors" on public.visitors;
create policy "society admin full access visitors"
on public.visitors for all to authenticated
using (public.is_society_admin(society_id));

-- Resident: can see visitors for their own flat(s)
drop policy if exists "resident view own flat visitors" on public.visitors;
create policy "resident view own flat visitors"
on public.visitors for select to authenticated
using (
  exists (
    select 1 from public.residents r
    where r.user_id = auth.uid()
    and r.flat_id = visitors.flat_id
    and r.status = 'active'
  )
);

-- Resident: can INSERT pre-approvals for their own flat
drop policy if exists "resident create preapproval" on public.visitors;
create policy "resident create preapproval"
on public.visitors for insert to authenticated
with check (
  entry_type = 'pre_approved'
  and created_by_type = 'resident'
  and exists (
    select 1 from public.residents r
    where r.user_id = auth.uid()
    and r.flat_id = visitors.flat_id
    and r.status = 'active'
  )
);

-- Resident: can UPDATE gate_request visitors targeting their flat (approve/deny)
drop policy if exists "resident approve deny gate request" on public.visitors;
create policy "resident approve deny gate request"
on public.visitors for update to authenticated
using (
  exists (
    select 1 from public.residents r
    where r.user_id = auth.uid()
    and r.flat_id = visitors.flat_id
    and r.status = 'active'
  )
);

-- visitor_group_members: inherit through visitor_id
drop policy if exists "master admins full access to visitor_group_members" on public.visitor_group_members;
create policy "master admins full access to visitor_group_members"
on public.visitor_group_members for all to authenticated
using (public.is_master_admin());

drop policy if exists "society admin access visitor_group_members" on public.visitor_group_members;
create policy "society admin access visitor_group_members"
on public.visitor_group_members for all to authenticated
using (
  exists (
    select 1 from public.visitors v
    where v.id = visitor_group_members.visitor_id
    and public.is_society_admin(v.society_id)
  )
);

drop policy if exists "resident view own visitor_group_members" on public.visitor_group_members;
create policy "resident view own visitor_group_members"
on public.visitor_group_members for select to authenticated
using (
  exists (
    select 1 from public.visitors v
    join public.residents r on r.flat_id = v.flat_id
    where v.id = visitor_group_members.visitor_id
    and r.user_id = auth.uid()
    and r.status = 'active'
  )
);

drop policy if exists "resident insert visitor_group_members" on public.visitor_group_members;
create policy "resident insert visitor_group_members"
on public.visitor_group_members for insert to authenticated
with check (
  exists (
    select 1 from public.visitors v
    join public.residents r on r.flat_id = v.flat_id
    where v.id = visitor_group_members.visitor_id
    and r.user_id = auth.uid()
    and r.status = 'active'
    and v.created_by_type = 'resident'
  )
);

-- visitor_status_history: inherit through visitor_id
drop policy if exists "master admins full access to visitor_status_history" on public.visitor_status_history;
create policy "master admins full access to visitor_status_history"
on public.visitor_status_history for all to authenticated
using (public.is_master_admin());

drop policy if exists "society admin access visitor_status_history" on public.visitor_status_history;
create policy "society admin access visitor_status_history"
on public.visitor_status_history for all to authenticated
using (
  exists (
    select 1 from public.visitors v
    where v.id = visitor_status_history.visitor_id
    and public.is_society_admin(v.society_id)
  )
);

drop policy if exists "resident view own visitor_status_history" on public.visitor_status_history;
create policy "resident view own visitor_status_history"
on public.visitor_status_history for select to authenticated
using (
  exists (
    select 1 from public.visitors v
    join public.residents r on r.flat_id = v.flat_id
    where v.id = visitor_status_history.visitor_id
    and r.user_id = auth.uid()
    and r.status = 'active'
  )
);

drop policy if exists "insert visitor_status_history" on public.visitor_status_history;
create policy "insert visitor_status_history"
on public.visitor_status_history for insert to authenticated
with check (
  exists (
    select 1 from public.visitors v
    where v.id = visitor_status_history.visitor_id
    and (
      public.is_society_admin(v.society_id)
      or exists (
        select 1 from public.residents r
        where r.user_id = auth.uid()
        and r.flat_id = v.flat_id
        and r.status = 'active'
      )
    )
  )
);

-- ------------------------------------------------------------
-- 6) HELPER: Generate unique 6-digit approval code
-- ------------------------------------------------------------
create or replace function public.generate_approval_code()
returns text as $$
declare
  code text;
  exists_already boolean;
begin
  loop
    code := lpad(floor(random() * 1000000)::text, 6, '0');
    select exists(select 1 from public.visitors where approval_code = code) into exists_already;
    if not exists_already then
      return code;
    end if;
  end loop;
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 7) HELPER: updated_at trigger for visitors
-- ------------------------------------------------------------
create or replace function public.visitors_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_visitors_updated_at on public.visitors;
create trigger trg_visitors_updated_at
before update on public.visitors
for each row execute function public.visitors_updated_at();

-- ------------------------------------------------------------
-- 8) RPC: create_visitor_entry (gate-initiated, Flow A)
-- Called by admin (standing in for guard) when a walk-in visitor arrives
-- ------------------------------------------------------------
create or replace function public.create_visitor_entry(
  p_society_id uuid,
  p_flat_id uuid,
  p_block_id uuid default null,
  p_visitor_name text default '',
  p_visitor_phone text default null,
  p_visitor_photo_url text default null,
  p_vehicle_number text default null,
  p_category text default 'others',
  p_company_or_context text default null
)
returns json as $$
declare
  v_id uuid;
  v_caller_id uuid;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  -- Insert visitor record
  insert into public.visitors (
    society_id, flat_id, block_id,
    created_by_type, created_by,
    visitor_name, visitor_phone, visitor_photo_url, vehicle_number,
    category, company_or_context,
    entry_type, status
  ) values (
    p_society_id, p_flat_id, p_block_id,
    'society_admin', v_caller_id,
    p_visitor_name, p_visitor_phone, p_visitor_photo_url, p_vehicle_number,
    p_category, p_company_or_context,
    'gate_request', 'pending_approval'
  )
  returning id into v_id;

  -- Insert initial status history
  insert into public.visitor_status_history (
    visitor_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    v_id, null, 'pending_approval', v_caller_id, 'society_admin',
    'Visitor logged at gate'
  );

  -- Create notification for resident(s) of this flat
  begin
    insert into public.notifications (
      society_id, user_id, target_role,
      title, body, type, entity_type, entity_id, route
    )
    select
      p_society_id, r.user_id, 'resident',
      '🚪 Visitor at Gate: ' || p_visitor_name,
      coalesce(p_category, 'visitor') || ' · Tap to approve or deny',
      'visitor_approval_request', 'visitor', v_id::text, '/visitors'
    from public.residents r
    where r.flat_id = p_flat_id
    and r.status = 'active'
    and r.user_id is not null;
  exception when others then
    -- notification insert is best-effort
    null;
  end;

  return json_build_object('success', true, 'visitor_id', v_id);
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 9) RPC: create_pre_approval (resident-initiated, Flow B)
-- ------------------------------------------------------------
create or replace function public.create_pre_approval(
  p_society_id uuid,
  p_flat_id uuid,
  p_block_id uuid default null,
  p_visitor_name text default '',
  p_visitor_phone text default null,
  p_vehicle_number text default null,
  p_category text default 'guest',
  p_company_or_context text default null,
  p_duration_type text default 'one_day',
  p_valid_from timestamptz default now(),
  p_valid_until timestamptz default null,
  p_is_private boolean default false,
  p_group_members jsonb default '[]'::jsonb
)
returns json as $$
declare
  v_id uuid;
  v_caller_id uuid;
  v_code text;
  v_valid_until timestamptz;
  v_member jsonb;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  -- Validate the caller is a resident of this flat
  if not exists (
    select 1 from public.residents r
    where r.user_id = v_caller_id
    and r.flat_id = p_flat_id
    and r.status = 'active'
  ) then
    return json_build_object('success', false, 'error', 'You are not a resident of this flat');
  end if;

  -- Generate unique approval code
  v_code := public.generate_approval_code();

  -- Compute valid_until if not provided
  if p_valid_until is not null then
    v_valid_until := p_valid_until;
  elsif p_duration_type = 'one_day' then
    v_valid_until := date_trunc('day', p_valid_from) + interval '1 day' - interval '1 second';
  else
    -- long_duration: default 30 days
    v_valid_until := p_valid_from + interval '30 days';
  end if;

  -- Find the resident ID (not user_id) for created_by
  -- We need a resident row ID, not auth user ID
  declare v_resident_id uuid;
  begin
    select r.id into v_resident_id
    from public.residents r
    where r.user_id = v_caller_id
    and r.flat_id = p_flat_id
    and r.status = 'active'
    limit 1;

    insert into public.visitors (
      society_id, flat_id, block_id,
      created_by_type, created_by,
      visitor_name, visitor_phone, vehicle_number,
      category, company_or_context,
      entry_type, status,
      approval_code, qr_payload,
      duration_type, valid_from, valid_until,
      is_private,
      approved_by, approved_at
    ) values (
      p_society_id, p_flat_id, p_block_id,
      'resident', coalesce(v_resident_id, v_caller_id),
      p_visitor_name, p_visitor_phone, p_vehicle_number,
      p_category, p_company_or_context,
      'pre_approved', 'approved',
      v_code, 'SAQIIT:' || v_code,
      p_duration_type, p_valid_from, v_valid_until,
      p_is_private,
      v_caller_id, now()
    )
    returning id into v_id;
  end;

  -- Insert initial status history
  insert into public.visitor_status_history (
    visitor_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    v_id, null, 'approved', v_caller_id, 'resident',
    'Pre-approval created by resident'
  );

  -- Insert group members if category is group_invite
  if p_category = 'group_invite' and jsonb_array_length(p_group_members) > 0 then
    for v_member in select * from jsonb_array_elements(p_group_members)
    loop
      insert into public.visitor_group_members (visitor_id, guest_name, guest_phone)
      values (
        v_id,
        v_member->>'name',
        v_member->>'phone'
      );
    end loop;
  end if;

  -- Create notifications
  begin
    if p_is_private then
      -- Only notify the creator
      insert into public.notifications (
        society_id, user_id, target_role,
        title, body, type, entity_type, entity_id, route
      ) values (
        p_society_id, v_caller_id, 'resident',
        '✅ Pre-Approval Created',
        p_visitor_name || ' · Code: ' || v_code,
        'visitor_preapproved_created', 'visitor', v_id::text, '/visitors'
      );
    else
      -- Notify all residents of the flat
      insert into public.notifications (
        society_id, user_id, target_role,
        title, body, type, entity_type, entity_id, route
      )
      select
        p_society_id, r.user_id, 'resident',
        '✅ Pre-Approval Created',
        p_visitor_name || ' · Code: ' || v_code,
        'visitor_preapproved_created', 'visitor', v_id::text, '/visitors'
      from public.residents r
      where r.flat_id = p_flat_id
      and r.status = 'active'
      and r.user_id is not null;
    end if;

    -- Informational notification for admin
    insert into public.notifications (
      society_id, target_role,
      title, body, type, entity_type, entity_id, route
    ) values (
      p_society_id, 'society_admin',
      'Pre-Approval: ' || p_visitor_name,
      p_category || ' · Code: ' || v_code,
      'visitor_preapproved_created', 'visitor', v_id::text, '/visitors'
    );
  exception when others then
    null;
  end;

  return json_build_object('success', true, 'visitor_id', v_id, 'approval_code', v_code);
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 10) RPC: respond_to_visitor_request (approve/deny)
-- Called by resident for gate_request visitors
-- ------------------------------------------------------------
create or replace function public.respond_to_visitor_request(
  p_visitor_id uuid,
  p_action text,          -- 'approved' or 'denied'
  p_denied_reason text default null
)
returns json as $$
declare
  v_caller_id uuid;
  v_visitor record;
  v_code text;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  -- Fetch the visitor
  select * into v_visitor from public.visitors where id = p_visitor_id;
  if not found then
    return json_build_object('success', false, 'error', 'Visitor not found');
  end if;

  -- Validate: must be a gate_request in pending_approval status
  if v_visitor.entry_type != 'gate_request' then
    return json_build_object('success', false, 'error', 'Only gate requests can be approved/denied');
  end if;

  if v_visitor.status != 'pending_approval' then
    return json_build_object('success', false, 'error', 'This request has already been ' || v_visitor.status);
  end if;

  -- Validate caller is a resident of the flat
  if not exists (
    select 1 from public.residents r
    where r.user_id = v_caller_id
    and r.flat_id = v_visitor.flat_id
    and r.status = 'active'
  ) then
    return json_build_object('success', false, 'error', 'You are not a resident of this flat');
  end if;

  if p_action = 'approved' then
    -- Generate approval code
    v_code := public.generate_approval_code();

    update public.visitors set
      status = 'approved',
      approved_by = v_caller_id,
      approved_at = now(),
      approval_code = v_code,
      qr_payload = 'SAQIIT:' || v_code
    where id = p_visitor_id;

    -- Status history
    insert into public.visitor_status_history (
      visitor_id, from_status, to_status, changed_by, changed_by_role, note
    ) values (
      p_visitor_id, 'pending_approval', 'approved', v_caller_id, 'resident',
      'Approved by resident'
    );

    -- Mark gate approval request notification as read
    update public.notifications
    set is_read = true
    where entity_type = 'visitor'
      and entity_id = p_visitor_id::text
      and type = 'visitor_approval_request';

    -- Notify admin
    begin
      insert into public.notifications (
        society_id, target_role,
        title, body, type, entity_type, entity_id, route
      ) values (
        v_visitor.society_id, 'society_admin',
        '✅ Visitor Approved: ' || v_visitor.visitor_name,
        'Approved for entry · Code: ' || v_code,
        'visitor_approved', 'visitor', p_visitor_id::text, '/visitors'
      );
    exception when others then null;
    end;

    return json_build_object('success', true, 'approval_code', v_code);

  elsif p_action = 'denied' then
    -- Require denial reason
    if p_denied_reason is null or trim(p_denied_reason) = '' then
      return json_build_object('success', false, 'error', 'Denial reason is required');
    end if;

    update public.visitors set
      status = 'denied',
      denied_by = v_caller_id,
      denied_at = now(),
      denied_reason = p_denied_reason
    where id = p_visitor_id;

    insert into public.visitor_status_history (
      visitor_id, from_status, to_status, changed_by, changed_by_role, note
    ) values (
      p_visitor_id, 'pending_approval', 'denied', v_caller_id, 'resident',
      'Denied: ' || p_denied_reason
    );

    -- Mark gate approval request notification as read
    update public.notifications
    set is_read = true
    where entity_type = 'visitor'
      and entity_id = p_visitor_id::text
      and type = 'visitor_approval_request';

    -- Notify admin
    begin
      insert into public.notifications (
        society_id, target_role,
        title, body, type, entity_type, entity_id, route
      ) values (
        v_visitor.society_id, 'society_admin',
        '❌ Visitor Denied: ' || v_visitor.visitor_name,
        'Reason: ' || p_denied_reason,
        'visitor_denied', 'visitor', p_visitor_id::text, '/visitors'
      );
    exception when others then null;
    end;

    return json_build_object('success', true);

  else
    return json_build_object('success', false, 'error', 'Invalid action. Use approved or denied.');
  end if;
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 11) RPC: check_in_visitor / check_out_visitor
-- Admin stand-in for future guard actions
-- ------------------------------------------------------------
create or replace function public.check_in_visitor(
  p_visitor_id uuid,
  p_entry_gate text default null
)
returns json as $$
declare
  v_caller_id uuid;
  v_visitor record;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_visitor from public.visitors where id = p_visitor_id;
  if not found then
    return json_build_object('success', false, 'error', 'Visitor not found');
  end if;

  if v_visitor.status != 'approved' then
    return json_build_object('success', false, 'error', 'Visitor must be in approved status to check in. Current: ' || v_visitor.status);
  end if;

  -- For pre-approved, check validity window
  if v_visitor.entry_type = 'pre_approved' then
    if v_visitor.valid_until is not null and now() > v_visitor.valid_until then
      return json_build_object('success', false, 'error', 'Pre-approval has expired');
    end if;
  end if;

  update public.visitors set
    status = 'checked_in',
    checked_in_at = now(),
    checked_in_by = v_caller_id,
    entry_gate = coalesce(p_entry_gate, entry_gate)
  where id = p_visitor_id;

  insert into public.visitor_status_history (
    visitor_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_visitor_id, 'approved', 'checked_in', v_caller_id, 'society_admin',
    'Checked in' || case when p_entry_gate is not null then ' at ' || p_entry_gate else '' end
  );

  return json_build_object('success', true);
end;
$$ language plpgsql security definer;

create or replace function public.check_out_visitor(
  p_visitor_id uuid
)
returns json as $$
declare
  v_caller_id uuid;
  v_visitor record;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_visitor from public.visitors where id = p_visitor_id;
  if not found then
    return json_build_object('success', false, 'error', 'Visitor not found');
  end if;

  if v_visitor.status != 'checked_in' then
    return json_build_object('success', false, 'error', 'Visitor must be checked in to check out. Current: ' || v_visitor.status);
  end if;

  update public.visitors set
    status = 'checked_out',
    checked_out_at = now(),
    checked_out_by = v_caller_id
  where id = p_visitor_id;

  insert into public.visitor_status_history (
    visitor_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_visitor_id, 'checked_in', 'checked_out', v_caller_id, 'society_admin',
    'Checked out'
  );

  return json_build_object('success', true);
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 12) RPC: cancel_pre_approval
-- Resident cancels their own pre-approval (not yet checked in)
-- ------------------------------------------------------------
create or replace function public.cancel_pre_approval(
  p_visitor_id uuid
)
returns json as $$
declare
  v_caller_id uuid;
  v_visitor record;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_visitor from public.visitors where id = p_visitor_id;
  if not found then
    return json_build_object('success', false, 'error', 'Visitor not found');
  end if;

  if v_visitor.entry_type != 'pre_approved' then
    return json_build_object('success', false, 'error', 'Only pre-approvals can be cancelled');
  end if;

  if v_visitor.status not in ('approved') then
    return json_build_object('success', false, 'error', 'Cannot cancel. Current status: ' || v_visitor.status);
  end if;

  -- Verify caller is a resident of the flat
  if not exists (
    select 1 from public.residents r
    where r.user_id = v_caller_id
    and r.flat_id = v_visitor.flat_id
    and r.status = 'active'
  ) then
    return json_build_object('success', false, 'error', 'You are not a resident of this flat');
  end if;

  update public.visitors set
    status = 'cancelled'
  where id = p_visitor_id;

  insert into public.visitor_status_history (
    visitor_id, from_status, to_status, changed_by, changed_by_role, note
  ) values (
    p_visitor_id, v_visitor.status, 'cancelled', v_caller_id, 'resident',
    'Cancelled by resident'
  );

  return json_build_object('success', true);
end;
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 13) RPC: verify_pre_approval
-- Admin lookup by approval_code (gate stand-in)
-- ------------------------------------------------------------
create or replace function public.verify_pre_approval(
  p_approval_code text
)
returns json as $$
declare
  v_visitor record;
  v_members jsonb;
  v_flat record;
  v_block record;
begin
  select * into v_visitor
  from public.visitors
  where approval_code = p_approval_code;

  if not found then
    return json_build_object('success', false, 'error', 'No visitor found with this approval code');
  end if;

  -- Fetch flat info
  select * into v_flat from public.flats where id = v_visitor.flat_id;
  select * into v_block from public.blocks where id = v_visitor.block_id;

  -- Fetch group members if group invite
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
$$ language plpgsql security definer;

-- ------------------------------------------------------------
-- 14) Expiry: pg_cron job to expire pre-approvals
-- This only works if pg_cron is enabled on your Supabase instance.
-- If pg_cron is not available, run manually or via edge function.
-- ------------------------------------------------------------
-- Uncomment below if pg_cron is available:
-- select cron.schedule(
--   'expire-visitor-preapprovals',
--   '*/5 * * * *',  -- every 5 minutes
--   $$
--     update public.visitors
--     set status = 'expired', updated_at = now()
--     where entry_type = 'pre_approved'
--     and status = 'approved'
--     and valid_until is not null
--     and valid_until < now();
--
--     insert into public.visitor_status_history (visitor_id, from_status, to_status, changed_by, changed_by_role, note)
--     select id, 'approved', 'expired', '00000000-0000-0000-0000-000000000000', 'system', 'Auto-expired: validity window ended'
--     from public.visitors
--     where status = 'expired'
--     and updated_at >= now() - interval '6 minutes';
--   $$
-- );

-- ------------------------------------------------------------
-- 15) Update notifications type check constraint to include visitor types
-- (best-effort: some setups may not have this constraint)
-- ------------------------------------------------------------
do $$
begin
  -- Try to alter the check constraint on notifications.type
  -- to include visitor-related types
  begin
    alter table public.notifications drop constraint if exists notifications_type_check;
    alter table public.notifications add constraint notifications_type_check
      check (type in (
        'complaint_created', 'complaint_updated', 'complaint_resolved',
        'complaint_reopened', 'complaint_closed', 'join_request_created',
        'join_request_approved', 'join_request_rejected', 'notice', 'general',
        'visitor_approval_request', 'visitor_approved', 'visitor_denied',
        'visitor_preapproved_created', 'visitor_checked_in', 'visitor_checked_out',
        'visitor_cancelled', 'visitor_expired'
      ));
  exception when others then
    raise notice 'Could not update notifications type check constraint: %', sqlerrm;
  end;
end $$;

-- ------------------------------------------------------------
-- 16) Storage Bucket: visitor-photos
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('visitor-photos', 'visitor-photos', true)
on conflict (id) do nothing;

drop policy if exists "Authenticated users can upload visitor photos" on storage.objects;
create policy "Authenticated users can upload visitor photos"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'visitor-photos');

drop policy if exists "Authenticated users can read visitor photos" on storage.objects;
create policy "Authenticated users can read visitor photos"
on storage.objects
for select
to authenticated
using (bucket_id = 'visitor-photos');

drop policy if exists "Public can read visitor photos" on storage.objects;
create policy "Public can read visitor photos"
on storage.objects
for select
to public
using (bucket_id = 'visitor-photos');
