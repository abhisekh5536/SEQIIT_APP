-- ============================================================
-- 16) PER-USER NOTIFICATION READ STATE
--
-- `notifications` stores one row per AUDIENCE, not per user: user_id is
-- nullable and null means "broadcast to everyone with target_role". But
-- `is_read` is a single boolean on that shared row, and the RLS update
-- policy explicitly permits writing rows where user_id is null.
--
-- So one admin opening a broadcast notification marked it read for every
-- admin in the society. The client's SharedPreferences cache hid this on
-- the acting device while corrupting everyone else's state.
--
-- This adds a per-user read ledger. `is_read` is left on the table for
-- backwards compatibility with existing triggers and direct-user rows,
-- but the app now reads and writes through here.
--
-- Prerequisite: migration 07.
-- Idempotent: safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE: notification_reads
-- ------------------------------------------------------------
create table if not exists public.notification_reads (
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (notification_id, user_id)
);

create index if not exists idx_notification_reads_user
  on public.notification_reads(user_id, read_at desc);

alter table public.notification_reads enable row level security;

-- A read marker is private to the user who made it.
drop policy if exists "own notification reads" on public.notification_reads;
create policy "own notification reads" on public.notification_reads
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- ------------------------------------------------------------
-- 2) BACKFILL
--
-- Rows already addressed to a single user carry meaningful read state;
-- migrate those. Broadcast rows are deliberately NOT backfilled — their
-- is_read flag is the corrupted shared value this migration exists to
-- replace, so it would be wrong to copy it onto anybody.
-- ------------------------------------------------------------
insert into public.notification_reads (notification_id, user_id, read_at)
select n.id, n.user_id, coalesce(n.created_at, now())
  from public.notifications n
 where n.user_id is not null
   and n.is_read = true
on conflict (notification_id, user_id) do nothing;

-- ------------------------------------------------------------
-- 3) STOP THE BLEEDING ON THE SHARED COLUMN
--
-- Narrow the update policies so nobody can flip is_read on a broadcast
-- row any more. Per-user state now lives in notification_reads; the
-- column stays only for rows that target one user.
-- ------------------------------------------------------------
drop policy if exists "society admins update notification read status" on public.notifications;
create policy "society admins update notification read status"
on public.notifications for update to authenticated
using (
  public.is_society_admin(society_id)
  and user_id = auth.uid()
)
with check (
  public.is_society_admin(society_id)
  and user_id = auth.uid()
);

drop policy if exists "residents update own notification read status" on public.notifications;
create policy "residents update own notification read status"
on public.notifications for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- ------------------------------------------------------------
-- 4) RPCs
-- ------------------------------------------------------------
create or replace function public.mark_notifications_read(p_ids uuid[])
returns jsonb
language plpgsql
security definer set search_path = public as $$
declare
  v_count int;
begin
  if auth.uid() is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  -- The select is RLS-filtered for the caller, so a user can only mark
  -- notifications they are actually allowed to see.
  insert into public.notification_reads (notification_id, user_id)
  select n.id, auth.uid()
    from public.notifications n
   where n.id = any(p_ids)
  on conflict (notification_id, user_id) do nothing;

  get diagnostics v_count = row_count;
  return jsonb_build_object('success', true, 'marked', v_count);
end;
$$;

grant execute on function public.mark_notifications_read(uuid[]) to authenticated;

create or replace function public.mark_all_notifications_as_read(p_society_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public as $$
declare
  v_count int;
begin
  if auth.uid() is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  insert into public.notification_reads (notification_id, user_id)
  select n.id, auth.uid()
    from public.notifications n
   where n.society_id = p_society_id
     and (n.user_id is null or n.user_id = auth.uid())
  on conflict (notification_id, user_id) do nothing;

  get diagnostics v_count = row_count;
  return jsonb_build_object('success', true, 'marked', v_count);
end;
$$;

grant execute on function public.mark_all_notifications_as_read(uuid) to authenticated;

-- ------------------------------------------------------------
-- 5) CONVENIENCE VIEW
--
-- Resolves each notification's read state for the CURRENT caller, so the
-- client does not have to join it client-side.
-- ------------------------------------------------------------
create or replace view public.notifications_for_me
with (security_invoker = true) as
select
  n.*,
  (nr.notification_id is not null) as read_by_me,
  nr.read_at as read_by_me_at
from public.notifications n
left join public.notification_reads nr
  on nr.notification_id = n.id
 and nr.user_id = auth.uid();

grant select on public.notifications_for_me to authenticated;

-- ------------------------------------------------------------
-- 6) REALTIME
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notification_reads'
  ) then
    alter publication supabase_realtime add table public.notification_reads;
  end if;
exception when others then
  raise notice 'Could not add notification_reads to realtime publication: %', sqlerrm;
end $$;
