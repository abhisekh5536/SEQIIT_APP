  -- ============================================================
  -- 17) GUARD IDENTITY
  --
  -- Until now a guard was whoever had `role: 'guard'` in their auth
  -- user_metadata. Supabase lets every signed-in user rewrite their own
  -- user_metadata:
  --
  --   supabase.auth.updateUser(UserAttributes(data: {
  --     'role': 'guard', 'society_id': '<any society uuid>' }))
  --
  -- and society ids are readable by every signed-in user (migration 05,
  -- needed by the join screen). So any account could make itself a guard
  -- of any society — and read every visitor's name, phone and photo, look
  -- up plates for owner names and phones, and ring any flat with a fake
  -- "visitor at gate" request.
  --
  -- Guard identity now comes from `society_guards`, a table only society
  -- admins can write. `is_guard_or_admin()` keeps its signature, so every
  -- policy and RPC from migrations 11, 14 and 15 picks up the fix without
  -- being rewritten.
  --
  -- Also closes the two gate functions migration 15 missed:
  --   lookup_vehicle_by_plate — no authorization check at all
  --   create_visitor_entry    — no authorization check, and recorded every
  --                             guard entry as an admin entry
  --
  -- Prerequisites: migrations 01, 03, 09, 11, 14. Migration 15 is strongly
  -- recommended (it closes other gate holes), but the one helper 17/18 need
  -- from it, caller_gate_role, is re-declared below.
  -- Idempotent: safe to re-run.
  -- ============================================================

  -- ------------------------------------------------------------
  -- 1) TABLE: society_gates
  -- ------------------------------------------------------------
  create table if not exists public.society_gates (
    id          uuid primary key default gen_random_uuid(),
    society_id  uuid not null references public.societies(id) on delete cascade,
    name        text not null check (length(trim(name)) > 0),
    is_active   boolean not null default true,
    sort_order  int not null default 0,
    created_at  timestamptz not null default now(),
    constraint uq_society_gate_name unique (society_id, name)
  );

  create index if not exists idx_society_gates_society
    on public.society_gates(society_id, sort_order);

  -- ------------------------------------------------------------
  -- 2) TABLE: society_guards
  --
  -- user_id is null until the guard first signs in with `email` — the same
  -- email-link pattern residents use (migrations 01 and 03).
  -- ------------------------------------------------------------
  create table if not exists public.society_guards (
    id              uuid primary key default gen_random_uuid(),
    society_id      uuid not null references public.societies(id) on delete cascade,
    user_id         uuid unique references auth.users(id) on delete set null,
    full_name       text not null check (length(trim(full_name)) > 0),
    email           text not null check (position('@' in email) > 1),
    phone           text not null check (length(trim(phone)) > 0),
    photo_url       text,
    employee_code   text,
    agency_name     text,
    default_gate_id uuid references public.society_gates(id) on delete set null,
    status          text not null default 'active' check (status in ('active', 'inactive')),
    created_by      uuid references auth.users(id) on delete set null,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
  );

  create unique index if not exists uq_guard_email_per_society
    on public.society_guards(society_id, lower(email));
  create index if not exists idx_society_guards_email
    on public.society_guards(lower(email));
  create index if not exists idx_society_guards_society_status
    on public.society_guards(society_id, status);

  drop trigger if exists trg_society_guards_updated on public.society_guards;
  create trigger trg_society_guards_updated
  before update on public.society_guards
  for each row execute function public.set_updated_at();

  -- ------------------------------------------------------------
  -- 3) WRITE RULES ON society_guards
  --
  -- user_id is never taken from the client. On insert (or an email change)
  -- it is resolved from auth.users by email; otherwise it keeps its value.
  -- Without this an admin could type any user's uuid into user_id and make
  -- that person a guard without them ever signing in.
  --
  -- The rule applies to requests that arrive through the API, recognised by
  -- the JWT role claim. `current_user` cannot be used for this: inside a
  -- security-definer function it is always the owner. The signup trigger
  -- below runs inside the auth service with no JWT, so it may set user_id.
  -- ------------------------------------------------------------
  create or replace function public.society_guards_before_write()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
  declare
    v_api_role text :=
      nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
    v_relink boolean;
  begin
    new.email := lower(trim(new.email));
    new.full_name := trim(new.full_name);
    new.phone := trim(new.phone);

    if v_api_role in ('authenticated', 'anon') then
      if tg_op = 'INSERT' then
        v_relink := true;
      else
        v_relink := new.email is distinct from old.email;
      end if;

      if v_relink then
        new.user_id := null;
        select u.id into new.user_id
          from auth.users u
        where lower(u.email) = new.email
          and not exists (
            select 1 from public.society_guards g
              where g.user_id = u.id
                and g.id is distinct from new.id
          )
        limit 1;
      else
        new.user_id := old.user_id;
      end if;
    end if;

    if new.default_gate_id is not null and not exists (
      select 1 from public.society_gates sg
      where sg.id = new.default_gate_id
        and sg.society_id = new.society_id
    ) then
      raise exception 'Default gate belongs to a different society';
    end if;

    if tg_op = 'INSERT' and new.created_by is null then
      new.created_by := auth.uid();
    end if;

    return new;
  end $$;

  drop trigger if exists trg_society_guards_before_write on public.society_guards;
  create trigger trg_society_guards_before_write
  before insert or update on public.society_guards
  for each row execute function public.society_guards_before_write();

  -- Link on signup. Wrapped so a guard-linking problem can never block an
  -- account from being created. Picks one row per account: user_id is
  -- unique, so two societies listing the same email must not both claim it.
  create or replace function public.link_guard_on_signup()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $$
  begin
    begin
      update public.society_guards g
        set user_id = new.id
      where g.id = (
              select g2.id from public.society_guards g2
                where lower(g2.email) = lower(new.email)
                  and g2.user_id is null
                order by (g2.status = 'active') desc, g2.created_at desc
                limit 1
            )
        and not exists (
              select 1 from public.society_guards g3 where g3.user_id = new.id
            );
    exception when others then
      raise warning 'link_guard_on_signup skipped for %: %', new.id, sqlerrm;
    end;
    return new;
  end $$;

  drop trigger if exists on_auth_user_created_link_guard on auth.users;
  create trigger on_auth_user_created_link_guard
  after insert on auth.users
  for each row execute function public.link_guard_on_signup();

  -- Backfill: rows added before an account existed, one row per account.
  with pick as (
    select distinct on (u.id) g.id as guard_id, u.id as user_id
      from public.society_guards g
      join auth.users u on lower(u.email) = lower(g.email)
    where g.user_id is null
      and not exists (select 1 from public.society_guards x where x.user_id = u.id)
    order by u.id, (g.status = 'active') desc, g.created_at desc
  )
  update public.society_guards g
    set user_id = pick.user_id
    from pick
  where g.id = pick.guard_id;

  -- ------------------------------------------------------------
  -- 4) HELPERS
  -- ------------------------------------------------------------
  create or replace function public.is_society_guard(p_society_id uuid)
  returns boolean
  language sql stable security definer set search_path = public as $$
    select exists (
      select 1 from public.society_guards g
      where g.user_id = auth.uid()
        and g.society_id = p_society_id
        and g.status = 'active'
    );
  $$;

  grant execute on function public.is_society_guard(uuid) to authenticated;

  -- Same signature as migration 11, so every existing policy and RPC that
  -- calls it is fixed in place. The user_metadata branch is gone.
  create or replace function public.is_guard_or_admin(p_society_id uuid)
  returns boolean
  language sql stable security definer set search_path = public as $$
    select public.is_society_admin(p_society_id)
        or public.is_master_admin()
        or public.is_society_guard(p_society_id);
  $$;

  grant execute on function public.is_guard_or_admin(uuid) to authenticated;

  -- The caller's real role, for the audit trail. Also created by migration
  -- 15; declared again here because 17 and 18 call it, and a database that
  -- skipped 15 otherwise fails every gate action with 42883 "function
  -- public.caller_gate_role(uuid) does not exist". Identical definition, so
  -- running both is harmless.
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

  -- ------------------------------------------------------------
  -- 5) RLS
  -- ------------------------------------------------------------
  alter table public.society_gates enable row level security;
  alter table public.society_guards enable row level security;

  drop policy if exists "gates_admin_all" on public.society_gates;
  create policy "gates_admin_all" on public.society_gates
  for all to authenticated
  using (public.is_society_admin(society_id) or public.is_master_admin())
  with check (public.is_society_admin(society_id) or public.is_master_admin());

  drop policy if exists "gates_guard_select" on public.society_gates;
  create policy "gates_guard_select" on public.society_gates
  for select to authenticated
  using (public.is_society_guard(society_id));

  drop policy if exists "guards_admin_all" on public.society_guards;
  create policy "guards_admin_all" on public.society_guards
  for all to authenticated
  using (public.is_society_admin(society_id) or public.is_master_admin())
  with check (public.is_society_admin(society_id) or public.is_master_admin());

  -- A guard reads their own row even when inactive, so the app can say
  -- "your access was turned off" instead of looking like a broken login.
  drop policy if exists "guards_select_own" on public.society_guards;
  create policy "guards_select_own" on public.society_guards
  for select to authenticated
  using (user_id = auth.uid());

  -- Residents get nothing on either table. Deliberately no policy.

  -- ------------------------------------------------------------
  -- 6) DROP STALE OVERLOADS of the two functions rewritten below.
  --    create_visitor_entry gains p_gate_id, so `create or replace` would
  --    leave the old unguarded version callable beside it.
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
        and p.proname in ('lookup_vehicle_by_plate', 'create_visitor_entry')
    loop
      execute format('drop function if exists %s', r.sig);
    end loop;
  end $$;

  -- ------------------------------------------------------------
  -- 7) lookup_vehicle_by_plate — authorize, and stop handing out phones
  --
  -- Was: security definer, granted to authenticated, no check. Returned
  -- the owner's full name and phone for any plate in any society.
  --
  -- Now: guard or admin of that society only. A guard gets the owner's
  -- first name (enough to say "Mr Sharma's car"); calls go through
  -- guard_call_flat, which logs them. Admins still get name and phone.
  -- ------------------------------------------------------------
  create function public.lookup_vehicle_by_plate(
    p_society_id uuid,
    p_plate_number text
  )
  returns jsonb
  language plpgsql
  security definer set search_path = public
  as $$
  declare
    v_norm_plate text;
    v_res jsonb;
    v_is_admin boolean;
  begin
    if not public.is_guard_or_admin(p_society_id) then
      return jsonb_build_object('success', false, 'error', 'Permission denied');
    end if;

    v_is_admin := public.is_society_admin(p_society_id) or public.is_master_admin();
    v_norm_plate := upper(regexp_replace(coalesce(p_plate_number, ''), '[^a-zA-Z0-9]', '', 'g'));

    if length(v_norm_plate) < 4 then
      return jsonb_build_object('success', false, 'error', 'Enter at least 4 characters of the plate');
    end if;

    select jsonb_build_object(
      'success', true,
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
      'resident_name', case
        when v_is_admin then r.full_name
        else nullif(split_part(trim(coalesce(r.full_name, '')), ' ', 1), '')
      end,
      'resident_phone', case when v_is_admin then r.phone else null end,
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
      'success', true,
      'found', false,
      'match_status', 'unregistered',
      'normalized_query', v_norm_plate
    );
  end;
  $$;

  grant execute on function public.lookup_vehicle_by_plate(uuid, text) to authenticated;

  -- ------------------------------------------------------------
  -- 8) create_visitor_entry — authorize, scope the flat, attribute honestly
  --
  -- Was: any signed-in user could create a pending gate request for any
  -- flat in any society, which pushes "Visitor at Gate" to real residents.
  -- created_by_type and changed_by_role were hardcoded to 'society_admin',
  -- so every guard entry was recorded as an admin entry.
  -- ------------------------------------------------------------
  alter table public.visitors
    add column if not exists gate_id uuid references public.society_gates(id) on delete set null;

  create function public.create_visitor_entry(
    p_society_id uuid,
    p_flat_id uuid,
    p_block_id uuid default null,
    p_visitor_name text default '',
    p_visitor_phone text default null,
    p_visitor_photo_url text default null,
    p_vehicle_number text default null,
    p_category text default 'others',
    p_company_or_context text default null,
    p_gate_id uuid default null
  )
  returns json
  language plpgsql
  security definer set search_path = public
  as $$
  declare
    v_id uuid;
    v_caller_id uuid := auth.uid();
    v_role text;
    v_block_id uuid;
    v_name text := trim(coalesce(p_visitor_name, ''));
  begin
    if v_caller_id is null then
      return json_build_object('success', false, 'error', 'Not authenticated');
    end if;

    if not public.is_guard_or_admin(p_society_id) then
      return json_build_object('success', false, 'error', 'Permission denied');
    end if;

    if v_name = '' then
      return json_build_object('success', false, 'error', 'Visitor name is required');
    end if;

    -- The flat must be in this society, or a guard of one society could
    -- ring the residents of another.
    select f.block_id into v_block_id
      from public.flats f
      join public.blocks b on b.id = f.block_id
    where f.id = p_flat_id
      and b.society_id = p_society_id;

    if not found then
      return json_build_object('success', false, 'error', 'Flat does not belong to this society');
    end if;

    if p_gate_id is not null and not exists (
      select 1 from public.society_gates g
      where g.id = p_gate_id and g.society_id = p_society_id
    ) then
      return json_build_object('success', false, 'error', 'Gate does not belong to this society');
    end if;

    v_role := public.caller_gate_role(p_society_id);

    insert into public.visitors (
      society_id, flat_id, block_id, gate_id,
      created_by_type, created_by,
      visitor_name, visitor_phone, visitor_photo_url, vehicle_number,
      category, company_or_context,
      entry_type, status
    ) values (
      p_society_id, p_flat_id, v_block_id, p_gate_id,
      v_role, v_caller_id,
      v_name, nullif(trim(coalesce(p_visitor_phone, '')), ''), p_visitor_photo_url,
      nullif(upper(trim(coalesce(p_vehicle_number, ''))), ''),
      p_category, nullif(trim(coalesce(p_company_or_context, '')), ''),
      'gate_request', 'pending_approval'
    )
    returning id into v_id;

    insert into public.visitor_status_history (
      visitor_id, from_status, to_status, changed_by, changed_by_role, note
    ) values (
      v_id, null, 'pending_approval', v_caller_id, v_role,
      'Visitor logged at gate'
    );

    begin
      insert into public.notifications (
        society_id, user_id, target_role,
        title, body, type, entity_type, entity_id, route
      )
      select
        p_society_id, r.user_id, 'resident',
        '🚪 Visitor at Gate: ' || v_name,
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
  $$;

  grant execute on function public.create_visitor_entry(uuid, uuid, uuid, text, text, text, text, text, text, uuid) to authenticated;

  -- ------------------------------------------------------------
  -- 9) VERIFICATION
  -- ------------------------------------------------------------
  -- As a resident, after:
  --   supabase.auth.updateUser(UserAttributes(data: {'role': 'guard',
  --     'society_id': '<society uuid>'}))
  -- and signing in again, all of these must fail:
  --   select public.is_guard_or_admin('<society uuid>');          -- false
  --   select public.lookup_vehicle_by_plate('<society uuid>', 'MH12AB1234');
  --                                           -- {"success":false,...}
  --   select public.create_visitor_entry('<society uuid>', '<flat uuid>',
  --     p_visitor_name => 'x');               -- {"success":false,...}
