-- ============================================================
-- MIGRATION: Resident Join Requests & Admin Approval Flow
-- Enables unlisted users to discover societies, pick vacant flats,
-- and request approval. Enables Society Admins to approve/reject.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE: resident_join_requests
-- ------------------------------------------------------------
create table if not exists public.resident_join_requests (
  id                    uuid primary key default gen_random_uuid(),
  society_id            uuid not null references public.societies(id) on delete cascade,
  flat_id               uuid not null references public.flats(id) on delete cascade,
  user_id               uuid not null references auth.users(id) on delete cascade,
  full_name             text not null,
  email                 text not null,
  phone                 text not null,
  resident_type         text not null check (resident_type in ('owner', 'tenant', 'family')),
  is_primary            boolean not null default true,
  agreement_holder_name text,
  agreement_date        date,
  aadhar_last4          varchar(4) check (aadhar_last4 ~ '^[0-9]{4}$'),
  status                text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  rejection_reason      text,
  reviewed_by           uuid references auth.users(id),
  reviewed_at           timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists idx_resident_join_requests_user on public.resident_join_requests(user_id);
create index if not exists idx_resident_join_requests_society on public.resident_join_requests(society_id, status);
create index if not exists idx_resident_join_requests_flat on public.resident_join_requests(flat_id);

-- Keep updated_at fresh
drop trigger if exists trg_resident_join_requests_updated on public.resident_join_requests;
create trigger trg_resident_join_requests_updated
before update on public.resident_join_requests
for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 2) RLS POLICIES
-- ------------------------------------------------------------
alter table public.resident_join_requests enable row level security;

-- Users can view their own requests
drop policy if exists "Users can view own join requests" on public.resident_join_requests;
create policy "Users can view own join requests"
on public.resident_join_requests
for select
using (auth.uid() = user_id);

-- Authenticated users can insert their own request
drop policy if exists "Users can create own join request" on public.resident_join_requests;
create policy "Users can create own join request"
on public.resident_join_requests
for insert
with check (auth.uid() = user_id);

-- Users can cancel their own pending requests
drop policy if exists "Users can cancel own pending join request" on public.resident_join_requests;
create policy "Users can cancel own pending join request"
on public.resident_join_requests
for update
using (auth.uid() = user_id and status = 'pending')
with check (auth.uid() = user_id and status = 'cancelled');

-- Society admins can view all requests for their society
drop policy if exists "Society admins can view society join requests" on public.resident_join_requests;
create policy "Society admins can view society join requests"
on public.resident_join_requests
for select
using (
  exists (
    select 1 from public.society_admin_users sau
     where sau.id = auth.uid()
       and sau.society_id = resident_join_requests.society_id
       and sau.status = 'active'
  )
);

-- Ensure authenticated users can view societies, blocks, and vacant flats for onboarding
drop policy if exists "Authenticated users can view societies" on public.societies;
create policy "Authenticated users can view societies"
on public.societies
for select
to authenticated
using (status = 'active');

drop policy if exists "Authenticated users can view blocks" on public.blocks;
create policy "Authenticated users can view blocks"
on public.blocks
for select
to authenticated
using (true);

drop policy if exists "Authenticated users can view flats" on public.flats;
create policy "Authenticated users can view flats"
on public.flats
for select
to authenticated
using (true);

-- ------------------------------------------------------------
-- 3) ATOMIC RPC FUNCTIONS FOR ADMIN REVIEW
-- ------------------------------------------------------------

-- Approve Join Request
create or replace function public.approve_resident_join_request(p_request_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req record;
  v_new_resident_id uuid;
begin
  -- 1. Fetch request
  select * into v_req
    from public.resident_join_requests
   where id = p_request_id;

  if v_req.id is null then
    return json_build_object('success', false, 'error', 'Request not found');
  end if;

  if v_req.status != 'pending' then
    return json_build_object('success', false, 'error', 'Request is already ' || v_req.status);
  end if;

  -- 2. Verify caller is active society admin for this society
  if not exists (
    select 1 from public.society_admin_users sau
     where sau.id = auth.uid()
       and sau.society_id = v_req.society_id
       and sau.status = 'active'
  ) then
    return json_build_object('success', false, 'error', 'Unauthorized: Only society admins can approve requests');
  end if;

  -- 3. Insert or update resident record in public.residents
  insert into public.residents (
    society_id,
    flat_id,
    user_id,
    full_name,
    email,
    phone,
    resident_type,
    is_primary,
    agreement_holder_name,
    agreement_date,
    aadhar_last4,
    status,
    created_by
  ) values (
    v_req.society_id,
    v_req.flat_id,
    v_req.user_id,
    v_req.full_name,
    v_req.email,
    v_req.phone,
    v_req.resident_type,
    coalesce(v_req.is_primary, true),
    v_req.agreement_holder_name,
    v_req.agreement_date,
    v_req.aadhar_last4,
    'active',
    auth.uid()
  )
  returning id into v_new_resident_id;

  -- 4. Mark flat as occupied
  update public.flats
     set status = 'occupied'
   where id = v_req.flat_id;

  -- 5. Mark request as approved
  update public.resident_join_requests
     set status = 'approved',
         reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = p_request_id;

  return json_build_object(
    'success', true,
    'resident_id', v_new_resident_id,
    'message', 'Resident request approved successfully'
  );
end;
$$;

-- Reject Join Request
create or replace function public.reject_resident_join_request(
  p_request_id uuid,
  p_reason text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req record;
begin
  -- 1. Fetch request
  select * into v_req
    from public.resident_join_requests
   where id = p_request_id;

  if v_req.id is null then
    return json_build_object('success', false, 'error', 'Request not found');
  end if;

  if v_req.status != 'pending' then
    return json_build_object('success', false, 'error', 'Request is already ' || v_req.status);
  end if;

  -- 2. Verify caller is active society admin
  if not exists (
    select 1 from public.society_admin_users sau
     where sau.id = auth.uid()
       and sau.society_id = v_req.society_id
       and sau.status = 'active'
  ) then
    return json_build_object('success', false, 'error', 'Unauthorized: Only society admins can reject requests');
  end if;

  -- 3. Update request status to rejected
  update public.resident_join_requests
     set status = 'rejected',
         rejection_reason = p_reason,
         reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = p_request_id;

  return json_build_object(
    'success', true,
    'message', 'Resident request rejected'
  );
end;
$$;
