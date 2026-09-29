-- ============================================================
-- 20) NOTICES / SECURITY / HELPDESK: REACH EVERYONE, ON TIME
--
-- Push already runs off public.notifications (migrations 17–19). Checking
-- the live data showed why these modules still did not reach everyone:
--
--   1) Notices were written for target_role 'resident' only, so admins and
--      guards never got them — in the bell or on the phone.
--   2) Block-targeted notices were broadcast to EVERY resident: in the
--      bell (RLS) and as a push.
--   3) Admins with status 'invited' — who already act as admins, since
--      is_society_admin() ignores status — were skipped by push.
--   3b) Guards were resolved from auth metadata only; guards managed in
--      public.society_guards (the table is_society_guard() uses) could be
--      missed.
--   4) Scheduled notices never published at all: publish_due_notices()
--      had no caller (no pg_cron job, and the app never invoked it). So a
--      scheduled notice produced no notification either.
--
-- Prerequisite: migrations 07, 08, 18, 19. Extension pg_cron.
-- Idempotent: safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1) Who a block-targeted notice is for
--
-- True when the notice is society-wide or the caller lives in its block.
-- Used by the bell (RLS) and push; admins/guards are handled separately.
-- ------------------------------------------------------------
create or replace function public.notice_reaches_user(p_notice_id text, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select n.target_type is distinct from 'block'
        or n.target_block_id is null
        or exists (
             select 1
               from public.residents r
               join public.flats f on f.id = r.flat_id
              where r.user_id = p_user_id
                and r.status = 'active'
                and f.block_id = n.target_block_id
           )
      from public.notices n
     where n.id::text = p_notice_id
  ), true);
$$;

grant execute on function public.notice_reaches_user(text, uuid) to authenticated;

-- ------------------------------------------------------------
-- 2) Notices go to everyone in the society
-- ------------------------------------------------------------
create or replace function public.notify_on_notice_published()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category_label text;
begin
  if (new.status = 'published') and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    v_category_label := case new.category
      when 'important'   then '⚠️ Important Notice'
      when 'event'       then '🎉 Upcoming Event'
      when 'safety'      then '🛡️ Safety Alert'
      when 'maintenance' then '🔧 Maintenance Update'
      when 'billing'     then '💳 Billing Notice'
      else '📢 Notice'
    end;

    insert into public.notifications (
      society_id, user_id, target_role, title, body,
      type, entity_type, entity_id, route, is_read, created_at
    ) values (
      new.society_id,
      null,
      'all',   -- residents, admins and guards; block targeting is applied
               -- per reader by RLS and push_recipients()
      v_category_label || ': ' || new.title,
      substring(new.body from 1 for 140),
      'notice',
      'notice',
      new.id::text,
      '/notices',
      false,
      now()
    );
  end if;
  return new;
end;
$$;

-- Bell: a resident outside the targeted block no longer sees the row.
drop policy if exists "residents view own notifications" on public.notifications;
create policy "residents view own notifications" on public.notifications
for select to authenticated
using (
  user_id = auth.uid()
  or (
    public.is_society_member(society_id)
    and user_id is null
    and target_role in ('resident', 'all')
    and (entity_type is distinct from 'notice'
         or public.is_society_admin(society_id)
         or public.notice_reaches_user(entity_id, auth.uid()))
  )
);

-- ------------------------------------------------------------
-- 3) Recipients: guards from society_guards, notice block targeting
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
       and (n.entity_type is distinct from 'notice'
            or public.notice_reaches_user(n.entity_id, r.user_id))

    union
    select a.id from n
      join public.society_admin_users a on a.society_id = n.society_id
     where n.user_id is null
       and n.target_role in ('society_admin', 'all')
       -- Same rule as is_society_admin(): an 'invited' admin already acts
       -- as admin everywhere, so they must get the admin alerts too.
       and a.status <> 'disabled'

    union
    select g.user_id from n
      join public.society_guards g on g.society_id = n.society_id
     where n.user_id is null
       and n.target_role in ('guard', 'all')
       and g.status = 'active'
       and g.user_id is not null

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
     and coalesce(
       (select pref.push_enabled from public.notification_preferences pref
         where pref.user_id = a.uid
           and pref.module = public.notification_module(n.type)),
       public.push_module_default(public.notification_module(n.type))
     );
$$;

revoke all on function public.push_recipients(uuid, uuid) from public, anon, authenticated;
grant execute on function public.push_recipients(uuid, uuid) to service_role;

-- ------------------------------------------------------------
-- 4) Scheduled notices: publish every minute
--
-- Publishing flips status to 'published', which fires the trigger above,
-- which writes the notification, which pushes. Also expires old notices.
-- ------------------------------------------------------------
create extension if not exists pg_cron;

select cron.unschedule(jobid)
  from cron.job
 where jobname = 'publish-due-notices';

select cron.schedule(
  'publish-due-notices',
  '* * * * *',
  $$select public.publish_due_notices()$$
);
