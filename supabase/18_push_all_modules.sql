-- ============================================================
-- 18) PUSH FOR EVERY MODULE + PER-MODULE PREFERENCES
--
-- Migration 17 pushed only visitor events, from a trigger on `visitors`.
-- But every module already records its alerts as rows in
-- public.notifications (helpdesk, notices, visitors, SOS, join requests,
-- parking). Pushing from THAT table covers all of them with one trigger,
-- and any future module that writes a notification gets push for free.
--
--   1) notification_preferences — per-user, per-module on/off.
--   2) notification_module()    — maps a notification type to its module.
--   3) push_recipients()        — resolves a notification's audience to
--                                 device tokens, honouring preferences.
--   4) Trigger on notifications -> `push-notify` Edge Function.
--   5) Retires the visitors-only trigger from migration 17.
--
-- Prerequisite: migrations 07, 16, 17.
-- Idempotent: safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE: notification_preferences
--
-- Absence of a row means "enabled", so new users and new modules are on
-- by default and only an explicit opt-out is stored.
-- ------------------------------------------------------------
create table if not exists public.notification_preferences (
  user_id      uuid not null references auth.users(id) on delete cascade,
  module       text not null check (module in (
                 'visitors', 'helpdesk', 'notices', 'security',
                 'approvals', 'parking', 'general'
               )),
  push_enabled boolean not null default true,
  updated_at   timestamptz not null default now(),
  primary key (user_id, module)
);

alter table public.notification_preferences enable row level security;

drop policy if exists "own notification preferences" on public.notification_preferences;
create policy "own notification preferences" on public.notification_preferences
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- ------------------------------------------------------------
-- 2) notification type -> module
-- ------------------------------------------------------------
create or replace function public.notification_module(p_type text)
returns text
language sql
immutable
as $$
  select case
    when p_type like 'visitor%'      then 'visitors'
    when p_type like 'complaint%'    then 'helpdesk'
    when p_type = 'notice'           then 'notices'
    when p_type like 'sos%'          then 'security'
    when p_type like 'join_request%' then 'approvals'
    when p_type like 'parking%'      then 'parking'
    else 'general'
  end;
$$;

-- ------------------------------------------------------------
-- 3) RECIPIENTS
--
-- Mirrors the audience rules of the notifications RLS policies:
--   user_id set             -> that user only
--   target_role resident    -> active residents of the society
--   target_role society_admin -> active admins of the society
--   target_role guard       -> users whose auth metadata marks them as a
--                              guard of the society
--   target_role all         -> all of the above
--   visitor decisions       -> also whoever logged the visitor at the gate.
--                              Those rows target society_admin only, which
--                              would leave a guard who is not an admin
--                              waiting at the barrier without an alert.
--
-- The actor (whoever caused the notification) is left out — nobody needs
-- a push about the notice they just published.
--
-- Callable only by the service role (the Edge Function).
-- ------------------------------------------------------------
create or replace function public.push_recipients(
  p_notification_id uuid,
  p_actor_id uuid default null
)
returns table (user_id uuid, token text)
language sql
stable
security definer
set search_path = public
as $$
  with n as (
    select * from public.notifications where id = p_notification_id
  ),
  audience as (
    select n.user_id as uid from n where n.user_id is not null

    union
    select r.user_id from n
      join public.residents r on r.society_id = n.society_id
     where n.user_id is null
       and n.target_role in ('resident', 'all')
       and r.status = 'active'
       and r.user_id is not null

    union
    select a.id from n
      join public.society_admin_users a on a.society_id = n.society_id
     where n.user_id is null
       and n.target_role in ('society_admin', 'all')
       and a.status = 'active'

    union
    select u.id from n
      join auth.users u
        on (u.raw_user_meta_data ->> 'society_id') = n.society_id::text
     where n.user_id is null
       and n.target_role in ('guard', 'all')
       and lower(coalesce(u.raw_user_meta_data ->> 'role', '')) in ('guard', 'security')

    union
    select v.created_by from n
      join public.visitors v on v.id::text = n.entity_id
     where n.entity_type = 'visitor'
       and n.type in ('visitor_approved', 'visitor_denied')
       and v.created_by_type in ('guard', 'society_admin')
  )
  select d.user_id, d.token
    from audience a
    join public.device_tokens d on d.user_id = a.uid
    cross join n
   where a.uid is distinct from p_actor_id
     and not exists (
       select 1 from public.notification_preferences pref
        where pref.user_id = a.uid
          and pref.module = public.notification_module(n.type)
          and pref.push_enabled = false
     );
$$;

revoke all on function public.push_recipients(uuid, uuid) from public, anon, authenticated;
grant execute on function public.push_recipients(uuid, uuid) to service_role;

-- ------------------------------------------------------------
-- 4) TRIGGER: notifications -> push-notify
--
-- Sends only the id and the actor; the function re-reads the row with the
-- service role, so nothing here depends on the payload being complete.
-- auth.uid() is the session that inserted the row (the actor) — known
-- here and nowhere later.
-- ------------------------------------------------------------
create or replace function public.fn_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
begin
  begin
    select decrypted_secret into v_url
      from vault.decrypted_secrets where name = 'push_notify_url';
    select decrypted_secret into v_secret
      from vault.decrypted_secrets where name = 'push_webhook_secret';

    if v_url is null or v_secret is null then
      return new;
    end if;

    perform net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', v_secret
      ),
      body    := jsonb_build_object(
        'notification_id', new.id,
        'actor_id', auth.uid()
      )
    );
  exception when others then
    -- A push failure must never roll back the action that notified.
    raise warning 'fn_push_notification: %', sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists trg_push_notification on public.notifications;
create trigger trg_push_notification
after insert on public.notifications
for each row execute function public.fn_push_notification();

-- ------------------------------------------------------------
-- 5) RETIRE THE VISITORS-ONLY PATH
--
-- Visitor events already produce notification rows, so keeping the
-- migration-17 trigger would push every visitor alert twice.
-- ------------------------------------------------------------
drop trigger if exists trg_push_visitor_change on public.visitors;
drop function if exists public.fn_push_visitor_change();

-- ------------------------------------------------------------
-- SETUP (run once, by hand)
--
--   select vault.create_secret(
--     'https://<project-ref>.supabase.co/functions/v1/push-notify',
--     'push_notify_url');
--
-- push_webhook_secret from migration 17 is reused.
-- ------------------------------------------------------------
