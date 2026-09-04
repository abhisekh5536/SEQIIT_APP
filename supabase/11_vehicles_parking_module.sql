-- ============================================================
-- MIGRATION 11: Vehicles & Parking Management Module
-- Includes:
--   1) vehicles (Resident-owned vehicle registry)
--   2) parking_slots (Physical society slot inventory)
--   3) parking_allocations (Per-flat slot allocation with optional vehicle binding)
--   4) vehicle_entry_logs (Gate security check & audit log)
--   5) parking_society_configs (Society-level policy configuration)
--   6) Triggers: slot status synchronization & updated_at
--   7) Server Action RPCs:
--        - allocate_parking_slot
--        - end_parking_allocation
--        - bulk_create_parking_slots
--        - lookup_vehicle_by_plate
--        - log_vehicle_entry
--        - log_vehicle_exit
--   8) RLS policies for Master Admin, Society Admin, Guard, Resident
--   9) Backwards-compatible data migration from resident_vehicles
-- ============================================================

-- ------------------------------------------------------------
-- 0) PREREQUISITE HELPER FUNCTIONS (Idempotent guarantees)
-- ------------------------------------------------------------
create or replace function public.is_master_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.master_admin_users m
    where m.id = auth.uid()
  );
$$;

create or replace function public.is_society_admin(p_society_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.society_admin_users a
    where a.id = auth.uid()
      and a.society_id = p_society_id
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

grant execute on function public.is_master_admin() to authenticated;
grant execute on function public.is_society_admin(uuid) to authenticated;
grant execute on function public.lives_in_flat(uuid) to authenticated;

-- ------------------------------------------------------------
-- 1) TABLE: vehicles
-- ------------------------------------------------------------
create table if not exists public.vehicles (
  id              uuid primary key default gen_random_uuid(),
  society_id      uuid not null references public.societies(id) on delete cascade,
  flat_id         uuid not null references public.flats(id) on delete cascade,
  resident_id     uuid references public.residents(id) on delete set null,
  type            text not null default 'four_wheeler' check (type in ('two_wheeler', 'four_wheeler', 'other')),
  vehicle_number  text not null, -- normalized uppercase, no spaces e.g. "MH12AB1234"
  make_model      text not null, -- e.g. "Hyundai Creta", "Honda Activa 6G"
  color           text,          -- e.g. "Polar White", "Matte Grey"
  rc_photo_url    text,          -- URL or storage path to RC image
  status          text not null default 'active' check (status in ('active', 'inactive')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint uq_society_vehicle_number unique (society_id, vehicle_number)
);

create index if not exists idx_vehicles_society on public.vehicles(society_id);
create index if not exists idx_vehicles_flat on public.vehicles(flat_id);
create index if not exists idx_vehicles_resident on public.vehicles(resident_id);
create index if not exists idx_vehicles_number on public.vehicles(vehicle_number);
create index if not exists idx_vehicles_status on public.vehicles(society_id, status);

-- ------------------------------------------------------------
-- 2) TABLE: parking_slots
-- ------------------------------------------------------------
create table if not exists public.parking_slots (
  id            uuid primary key default gen_random_uuid(),
  society_id    uuid not null references public.societies(id) on delete cascade,
  block_id      uuid references public.blocks(id) on delete set null,
  slot_number   text not null, -- e.g. "P-101", "B1-04"
  vehicle_type  text not null default 'four_wheeler' check (vehicle_type in ('two_wheeler', 'four_wheeler', 'other')),
  category      text not null default 'covered' check (category in ('covered', 'open')),
  status        text not null default 'vacant' check (status in ('vacant', 'allocated', 'reserved', 'maintenance')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint uq_society_slot_number unique (society_id, slot_number)
);

create index if not exists idx_slots_society on public.parking_slots(society_id);
create index if not exists idx_slots_block on public.parking_slots(block_id);
create index if not exists idx_slots_status on public.parking_slots(society_id, status);
create index if not exists idx_slots_type on public.parking_slots(society_id, vehicle_type);

-- ------------------------------------------------------------
-- 3) TABLE: parking_allocations
-- ------------------------------------------------------------
create table if not exists public.parking_allocations (
  id              uuid primary key default gen_random_uuid(),
  society_id      uuid not null references public.societies(id) on delete cascade,
  slot_id         uuid not null references public.parking_slots(id) on delete cascade,
  flat_id         uuid not null references public.flats(id) on delete cascade,
  resident_id     uuid references public.residents(id) on delete set null,
  vehicle_id      uuid references public.vehicles(id) on delete set null, -- optional binding to vehicle
  allocated_from  timestamptz not null default now(),
  allocated_until timestamptz,
  status          text not null default 'active' check (status in ('active', 'ended')),
  allocated_by    uuid references auth.users(id) on delete set null,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Crucial: a slot can only have ONE active allocation at any given time
create unique index if not exists idx_unique_active_slot_allocation
  on public.parking_allocations(slot_id)
  where (status = 'active');

create index if not exists idx_allocations_society on public.parking_allocations(society_id);
create index if not exists idx_allocations_flat on public.parking_allocations(flat_id);
create index if not exists idx_allocations_status on public.parking_allocations(society_id, status);
create index if not exists idx_allocations_vehicle on public.parking_allocations(vehicle_id);

-- ------------------------------------------------------------
-- 4) TABLE: vehicle_entry_logs (Gate security log)
-- ------------------------------------------------------------
create table if not exists public.vehicle_entry_logs (
  id                      uuid primary key default gen_random_uuid(),
  society_id              uuid not null references public.societies(id) on delete cascade,
  vehicle_id              uuid references public.vehicles(id) on delete set null,
  vehicle_number_entered  text not null, -- raw license plate string entered by guard
  match_status            text not null check (match_status in ('registered', 'unregistered')),
  entry_at                timestamptz not null default now(),
  exit_at                 timestamptz,
  logged_by               uuid references auth.users(id) on delete set null,
  notes                   text,          -- e.g. "Delivery - Amazon", "Guest of 302"
  created_at              timestamptz not null default now()
);

create index if not exists idx_entry_logs_society on public.vehicle_entry_logs(society_id, entry_at desc);
create index if not exists idx_entry_logs_plate on public.vehicle_entry_logs(society_id, vehicle_number_entered);
create index if not exists idx_entry_logs_vehicle on public.vehicle_entry_logs(vehicle_id);

-- ------------------------------------------------------------
-- 5) TABLE: parking_society_configs
-- ------------------------------------------------------------
create table if not exists public.parking_society_configs (
  society_id              uuid primary key references public.societies(id) on delete cascade,
  max_slots_per_flat      int not null default 2,
  require_vehicle_binding boolean not null default false,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 6) TRIGGERS
-- ------------------------------------------------------------

-- Keep updated_at fresh
create or replace function public.fn_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_vehicles_updated on public.vehicles;
create trigger trg_vehicles_updated
before update on public.vehicles
for each row execute function public.fn_set_updated_at();

drop trigger if exists trg_parking_slots_updated on public.parking_slots;
create trigger trg_parking_slots_updated
before update on public.parking_slots
for each row execute function public.fn_set_updated_at();

drop trigger if exists trg_parking_allocations_updated on public.parking_allocations;
create trigger trg_parking_allocations_updated
before update on public.parking_allocations
for each row execute function public.fn_set_updated_at();

drop trigger if exists trg_parking_configs_updated on public.parking_society_configs;
create trigger trg_parking_configs_updated
before update on public.parking_society_configs
for each row execute function public.fn_set_updated_at();

-- Automatically synchronize parking_slots.status with parking_allocations
create or replace function public.fn_sync_slot_status_on_allocation()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op = 'INSERT' or tg_op = 'UPDATE') then
    if new.status = 'active' then
      update public.parking_slots
      set status = 'allocated', updated_at = now()
      where id = new.slot_id;
    elsif new.status = 'ended' then
      -- If allocation ended, revert slot to vacant unless it was marked reserved or maintenance
      update public.parking_slots
      set status = 'vacant', updated_at = now()
      where id = new.slot_id and status = 'allocated';
    end if;
  elsif (tg_op = 'DELETE') then
    if old.status = 'active' then
      update public.parking_slots
      set status = 'vacant', updated_at = now()
      where id = old.slot_id and status = 'allocated';
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_sync_slot_status_on_allocation on public.parking_allocations;
create trigger trg_sync_slot_status_on_allocation
after insert or update of status or delete on public.parking_allocations
for each row execute function public.fn_sync_slot_status_on_allocation();

-- ------------------------------------------------------------
-- 7) SERVER ACTION RPCs
-- ------------------------------------------------------------

-- 7.1 Allocate a parking slot to a flat (and optionally a vehicle)
create or replace function public.allocate_parking_slot(
  p_society_id uuid,
  p_slot_id uuid,
  p_flat_id uuid,
  p_resident_id uuid default null,
  p_vehicle_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller_uid uuid := auth.uid();
  v_slot record;
  v_config record;
  v_active_count int;
  v_new_allocation record;
begin
  -- Permission check: Society Admin or Master Admin
  if not (public.is_society_admin(p_society_id) or public.is_master_admin()) then
    return jsonb_build_object('success', false, 'error', 'Permission denied: only society admins can allocate slots');
  end if;

  -- Verify slot exists and belongs to society
  select * into v_slot from public.parking_slots
  where id = p_slot_id and society_id = p_society_id;

  if not found then
    return jsonb_build_object('success', false, 'error', 'Parking slot not found in this society');
  end if;

  -- Recheck slot status in DB transaction
  if v_slot.status <> 'vacant' then
    return jsonb_build_object('success', false, 'error', 'Parking slot is not vacant (current status: ' || v_slot.status || ')');
  end if;

  -- Check flat's active allocation count against society policy
  select coalesce(max_slots_per_flat, 2) as max_slots, coalesce(require_vehicle_binding, false) as req_veh
  into v_config
  from public.parking_society_configs
  where society_id = p_society_id;

  if not found then
    v_config.max_slots := 2;
    v_config.req_veh := false;
  end if;

  select count(*) into v_active_count
  from public.parking_allocations
  where flat_id = p_flat_id and society_id = p_society_id and status = 'active';

  if v_active_count >= v_config.max_slots then
    return jsonb_build_object(
      'success', false,
      'error', 'Flat has reached the maximum allowed parking slots (' || v_config.max_slots || ')'
    );
  end if;

  -- If vehicle binding is required, enforce p_vehicle_id
  if v_config.req_veh and p_vehicle_id is null then
    return jsonb_build_object('success', false, 'error', 'Society policy requires binding a specific vehicle to the slot');
  end if;

  -- If vehicle is provided, verify it belongs to flat
  if p_vehicle_id is not null then
    if not exists (select 1 from public.vehicles where id = p_vehicle_id and flat_id = p_flat_id and society_id = p_society_id) then
      return jsonb_build_object('success', false, 'error', 'Vehicle does not belong to the selected flat');
    end if;
  end if;

  -- Insert active allocation
  insert into public.parking_allocations (
    society_id, slot_id, flat_id, resident_id, vehicle_id,
    allocated_from, status, allocated_by, notes
  ) values (
    p_society_id, p_slot_id, p_flat_id, p_resident_id, p_vehicle_id,
    now(), 'active', v_caller_uid, p_notes
  ) returning * into v_new_allocation;

  return jsonb_build_object(
    'success', true,
    'allocation_id', v_new_allocation.id,
    'slot_id', v_new_allocation.slot_id,
    'flat_id', v_new_allocation.flat_id
  );
end;
$$;

grant execute on function public.allocate_parking_slot to authenticated;

-- 7.2 End parking allocation (Revoke / Move-out)
create or replace function public.end_parking_allocation(
  p_allocation_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_alloc record;
begin
  select * into v_alloc from public.parking_allocations where id = p_allocation_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Allocation not found');
  end if;

  if not (public.is_society_admin(v_alloc.society_id) or public.is_master_admin()) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  update public.parking_allocations
  set status = 'ended',
      allocated_until = now(),
      notes = case when p_notes is not null then coalesce(notes || ' | ', '') || p_notes else notes end,
      updated_at = now()
  where id = p_allocation_id;

  return jsonb_build_object('success', true, 'allocation_id', p_allocation_id, 'slot_id', v_alloc.slot_id);
end;
$$;

grant execute on function public.end_parking_allocation to authenticated;

-- 7.3 Bulk create parking slots
create or replace function public.bulk_create_parking_slots(
  p_society_id uuid,
  p_prefix text,
  p_start_num int,
  p_end_num int,
  p_block_id uuid default null,
  p_vehicle_type text default 'four_wheeler',
  p_category text default 'covered'
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_i int;
  v_slot_num text;
  v_created int := 0;
begin
  if not (public.is_society_admin(p_society_id) or public.is_master_admin()) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if p_start_num > p_end_num or (p_end_num - p_start_num) > 300 then
    return jsonb_build_object('success', false, 'error', 'Invalid range (maximum 300 slots per bulk operation)');
  end if;

  for v_i in p_start_num..p_end_num loop
    v_slot_num := coalesce(p_prefix, '') || lpad(v_i::text, 2, '0');
    begin
      insert into public.parking_slots (
        society_id, block_id, slot_number, vehicle_type, category, status
      ) values (
        p_society_id, p_block_id, v_slot_num, p_vehicle_type, p_category, 'vacant'
      );
      v_created := v_created + 1;
    exception when unique_violation then
      -- Skip existing slot number without aborting whole batch
      null;
    end;
  end loop;

  return jsonb_build_object('success', true, 'created_count', v_created);
end;
$$;

grant execute on function public.bulk_create_parking_slots to authenticated;

-- 7.4 Lookup vehicle by plate number (Guard fast gate check)
create or replace function public.lookup_vehicle_by_plate(
  p_society_id uuid,
  p_plate_number text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_norm_plate text;
  v_res jsonb;
begin
  -- Normalize plate: uppercase and remove non-alphanumeric
  v_norm_plate := upper(regexp_replace(p_plate_number, '[^a-zA-Z0-9]', '', 'g'));

  select jsonb_build_object(
    'found', true,
    'match_status', 'registered',
    'vehicle_id', v.id,
    'vehicle_number', v.vehicle_number,
    'make_model', v.make_model,
    'color', v.color,
    'type', v.type,
    'status', v.status,
    'flat_id', f.id,
    'flat_number', f.flat_number,
    'block_name', coalesce(b.name, ''),
    'resident_id', r.id,
    'resident_name', r.full_name,
    'resident_phone', r.phone,
    'slot_id', s.id,
    'slot_number', s.slot_number,
    'slot_category', s.category
  ) into v_res
  from public.vehicles v
  join public.flats f on f.id = v.flat_id
  left join public.blocks b on b.id = f.block_id
  left join public.residents r on r.id = v.resident_id
  left join public.parking_allocations pa on (
    pa.society_id = v.society_id
    and pa.status = 'active'
    and (pa.vehicle_id = v.id or (pa.flat_id = v.flat_id and pa.vehicle_id is null))
  )
  left join public.parking_slots s on s.id = pa.slot_id
  where v.society_id = p_society_id
    and upper(regexp_replace(v.vehicle_number, '[^a-zA-Z0-9]', '', 'g')) = v_norm_plate
    and v.status = 'active'
  limit 1;

  if v_res is not null then
    return v_res;
  end if;

  return jsonb_build_object(
    'found', false,
    'match_status', 'unregistered',
    'normalized_query', v_norm_plate
  );
end;
$$;

grant execute on function public.lookup_vehicle_by_plate to authenticated;

-- 7.5 Log vehicle gate entry
create or replace function public.log_vehicle_entry(
  p_society_id uuid,
  p_plate_number text,
  p_vehicle_id uuid default null,
  p_match_status text default 'unregistered',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_log_id uuid;
begin
  insert into public.vehicle_entry_logs (
    society_id, vehicle_id, vehicle_number_entered, match_status,
    entry_at, logged_by, notes
  ) values (
    p_society_id, p_vehicle_id, upper(trim(p_plate_number)), p_match_status,
    now(), auth.uid(), p_notes
  ) returning id into v_log_id;

  return jsonb_build_object('success', true, 'log_id', v_log_id);
end;
$$;

grant execute on function public.log_vehicle_entry to authenticated;

-- 7.6 Log vehicle gate exit
create or replace function public.log_vehicle_exit(
  p_log_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
begin
  update public.vehicle_entry_logs
  set exit_at = now()
  where id = p_log_id and exit_at is null;

  return jsonb_build_object('success', true, 'log_id', p_log_id);
end;
$$;

grant execute on function public.log_vehicle_exit to authenticated;

-- ------------------------------------------------------------
-- 8) ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------

alter table public.vehicles enable row level security;
alter table public.parking_slots enable row level security;
alter table public.parking_allocations enable row level security;
alter table public.vehicle_entry_logs enable row level security;
alter table public.parking_society_configs enable row level security;

-- 8.1 vehicles
drop policy if exists "vehicles_select" on public.vehicles;
create policy "vehicles_select" on public.vehicles
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or public.lives_in_flat(flat_id)
);

drop policy if exists "vehicles_insert" on public.vehicles;
create policy "vehicles_insert" on public.vehicles
for insert to authenticated
with check (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or public.lives_in_flat(flat_id)
);

drop policy if exists "vehicles_update" on public.vehicles;
create policy "vehicles_update" on public.vehicles
for update to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or public.lives_in_flat(flat_id)
)
with check (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or public.lives_in_flat(flat_id)
);

drop policy if exists "vehicles_delete" on public.vehicles;
create policy "vehicles_delete" on public.vehicles
for delete to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or (public.lives_in_flat(flat_id) and not exists (
      select 1 from public.parking_allocations pa where pa.vehicle_id = vehicles.id
  ))
);

-- 8.2 parking_slots
drop policy if exists "parking_slots_select" on public.parking_slots;
create policy "parking_slots_select" on public.parking_slots
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or exists (select 1 from public.residents r where r.society_id = parking_slots.society_id and r.user_id = auth.uid())
);

drop policy if exists "parking_slots_admin_all" on public.parking_slots;
create policy "parking_slots_admin_all" on public.parking_slots
for all to authenticated
using (public.is_society_admin(society_id) or public.is_master_admin())
with check (public.is_society_admin(society_id) or public.is_master_admin());

-- 8.3 parking_allocations
drop policy if exists "parking_allocations_select" on public.parking_allocations;
create policy "parking_allocations_select" on public.parking_allocations
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or public.lives_in_flat(flat_id)
);

drop policy if exists "parking_allocations_admin_all" on public.parking_allocations;
create policy "parking_allocations_admin_all" on public.parking_allocations
for all to authenticated
using (public.is_society_admin(society_id) or public.is_master_admin())
with check (public.is_society_admin(society_id) or public.is_master_admin());

-- 8.4 vehicle_entry_logs
drop policy if exists "vehicle_entry_logs_select" on public.vehicle_entry_logs;
create policy "vehicle_entry_logs_select" on public.vehicle_entry_logs
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
);

drop policy if exists "vehicle_entry_logs_insert" on public.vehicle_entry_logs;
create policy "vehicle_entry_logs_insert" on public.vehicle_entry_logs
for insert to authenticated
with check (
  public.is_society_admin(society_id)
  or public.is_master_admin()
);

-- 8.5 parking_society_configs
drop policy if exists "parking_society_configs_select" on public.parking_society_configs;
create policy "parking_society_configs_select" on public.parking_society_configs
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or exists (select 1 from public.residents r where r.society_id = parking_society_configs.society_id and r.user_id = auth.uid())
);

drop policy if exists "parking_society_configs_admin_all" on public.parking_society_configs;
create policy "parking_society_configs_admin_all" on public.parking_society_configs
for all to authenticated
using (public.is_society_admin(society_id) or public.is_master_admin())
with check (public.is_society_admin(society_id) or public.is_master_admin());

-- ------------------------------------------------------------
-- 9) DATA MIGRATION HELPER
-- Copies any legacy records from resident_vehicles into vehicles
-- ------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from information_schema.tables 
    where table_schema = 'public' and table_name = 'resident_vehicles'
  ) then
    insert into public.vehicles (
      id, society_id, flat_id, resident_id, type, vehicle_number, make_model, status, created_at
    )
    select
      rv.id,
      rv.society_id,
      rv.flat_id,
      rv.resident_id,
      'four_wheeler',
      upper(regexp_replace(coalesce(rv.registration_no, 'UNREG'), '\s+', '', 'g')),
      coalesce(rv.make_model, 'Vehicle'),
      'active',
      coalesce(rv.created_at, now())
    from public.resident_vehicles rv
    on conflict (society_id, vehicle_number) do nothing;
  end if;
end $$;
