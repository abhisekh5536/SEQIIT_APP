-- ============================================================
-- 17) PUSH NOTIFICATIONS (FCM) FOR VISITORS
--
-- Realtime (migration 13) only reaches a phone while the app process is
-- alive. Once Android kills the app the socket is gone, so a resident
-- never hears that a visitor is at the gate. Android's only channel for
-- waking a closed app is Firebase Cloud Messaging.
--
-- Supabase remains the backend. Firebase is used purely as the delivery
-- pipe:
--   1) device_tokens      — each phone's FCM token, owned by a user.
--   2) register / unregister RPCs the app calls on login / logout.
--   3) A trigger on visitors that POSTs the change to the `push-visitor`
--      Edge Function (via pg_net), which resolves recipients and sends
--      through FCM.
--
-- The function URL and shared secret live in Supabase Vault, not in this
-- file. Until both are set the trigger is a no-op, so running this
-- migration first is harmless. See the setup block at the bottom.
--
-- Prerequisite: migrations 01, 09. Extension pg_net.
-- Idempotent: safe to re-run.
-- ============================================================

create extension if not exists pg_net;

-- ------------------------------------------------------------
-- 1) TABLE: device_tokens
-- ------------------------------------------------------------
create table if not exists public.device_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  society_id  uuid references public.societies(id) on delete set null,
  platform    text,
  updated_at  timestamptz not null default now()
);

create index if not exists idx_device_tokens_user
  on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

-- Users may see their own devices. All writes go through the RPCs below,
-- and the Edge Function reads with the service role.
drop policy if exists "own device tokens" on public.device_tokens;
create policy "own device tokens" on public.device_tokens
for select to authenticated
using (user_id = auth.uid());

-- ------------------------------------------------------------
-- 2) RPCs
--
-- security definer because a token must be able to move between users:
-- when someone signs in on a phone last used by another account, the row
-- belongs to that other user and plain RLS would refuse the update —
-- leaving the previous user receiving this phone's alerts.
-- ------------------------------------------------------------
create or replace function public.register_device_token(
  p_token text,
  p_platform text default null,
  p_society_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if coalesce(length(p_token), 0) = 0 then
    return;
  end if;

  insert into public.device_tokens (token, user_id, society_id, platform, updated_at)
  values (p_token, auth.uid(), p_society_id, p_platform, now())
  on conflict (token) do update
    set user_id    = excluded.user_id,
        society_id = excluded.society_id,
        platform   = excluded.platform,
        updated_at = now();
end;
$$;

create or replace function public.unregister_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.device_tokens
   where token = p_token
     and user_id = auth.uid();
end;
$$;

revoke all on function public.register_device_token(text, text, uuid) from public, anon;
revoke all on function public.unregister_device_token(text) from public, anon;
grant execute on function public.register_device_token(text, text, uuid) to authenticated;
grant execute on function public.unregister_device_token(text) to authenticated;

-- ------------------------------------------------------------
-- 3) TRIGGER: visitors -> push-visitor Edge Function
--
-- Fires only for the two moments worth a push:
--   * a new gate request (INSERT with status pending_approval)
--   * a resident's decision (pending_approval -> approved / denied)
-- Everything else (check-in, check-out, edits) is ignored here so the
-- function is not woken for nothing.
--
-- net.http_post is asynchronous: the visitor write never waits on, or
-- fails because of, the push.
-- ------------------------------------------------------------
create or replace function public.fn_push_visitor_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'pending_approval' then
      return new;
    end if;
  elsif tg_op = 'UPDATE' then
    if not (old.status = 'pending_approval'
            and new.status in ('approved', 'denied')) then
      return new;
    end if;
  end if;

  begin
    select decrypted_secret into v_url
      from vault.decrypted_secrets where name = 'push_function_url';
    select decrypted_secret into v_secret
      from vault.decrypted_secrets where name = 'push_webhook_secret';

    if v_url is null or v_secret is null then
      return new; -- push not configured yet
    end if;

    perform net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', v_secret
      ),
      body    := jsonb_build_object(
        'type', tg_op,
        'record', to_jsonb(new),
        'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) end
      )
    );
  exception when others then
    -- A push failure must never roll back the gate entry.
    raise warning 'fn_push_visitor_change: %', sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists trg_push_visitor_change on public.visitors;
create trigger trg_push_visitor_change
after insert or update of status on public.visitors
for each row execute function public.fn_push_visitor_change();

-- ------------------------------------------------------------
-- SETUP (run once, by hand, with your own values — do not commit them)
--
--   select vault.create_secret(
--     'https://<project-ref>.supabase.co/functions/v1/push-visitor',
--     'push_function_url');
--   select vault.create_secret('<long random string>', 'push_webhook_secret');
--
-- The same random string must be set as the Edge Function secret
-- PUSH_WEBHOOK_SECRET.
-- ------------------------------------------------------------
