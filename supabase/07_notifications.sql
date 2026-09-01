-- ============================================================
-- MIGRATION 07: Notifications System
-- Stores notifications for Admins and Residents, with triggers
-- for automated alerts on approvals, complaints, and status changes.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE: notifications
-- ------------------------------------------------------------
create table if not exists public.notifications (
  id            uuid primary key default gen_random_uuid(),
  society_id    uuid not null references public.societies(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete cascade, -- null if broadcast to role
  target_role   text not null default 'all' check (target_role in ('resident', 'society_admin', 'all')),
  title         text not null,
  body          text not null,
  type          text not null check (type in (
                  'complaint_created', 'complaint_updated', 'complaint_resolved',
                  'complaint_reopened', 'complaint_closed', 'join_request_created',
                  'join_request_approved', 'join_request_rejected', 'notice', 'general'
                )),
  entity_type   text, -- 'complaint', 'join_request', 'notice'
  entity_id     text, -- ID of the complaint, request, etc.
  route         text, -- target app route for deep navigation
  is_read       boolean not null default false,
  created_at    timestamptz not null default now()
);

create index if not exists idx_notifications_user_unread on public.notifications(user_id, is_read, created_at desc);
create index if not exists idx_notifications_society on public.notifications(society_id, target_role, created_at desc);
create index if not exists idx_notifications_created_at on public.notifications(created_at desc);

-- ------------------------------------------------------------
-- 2) ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------
alter table public.notifications enable row level security;

-- Master admins full access
drop policy if exists "master admins full access to notifications" on public.notifications;
create policy "master admins full access to notifications"
on public.notifications for all to authenticated
using (public.is_master_admin());

-- Society admins view society admin notifications & update read status
drop policy if exists "society admins view society notifications" on public.notifications;
create policy "society admins view society notifications"
on public.notifications for select to authenticated
using (
  public.is_society_admin(society_id)
  and (user_id = auth.uid() or user_id is null)
  and target_role in ('society_admin', 'all')
);

drop policy if exists "society admins update notification read status" on public.notifications;
create policy "society admins update notification read status"
on public.notifications for update to authenticated
using (
  public.is_society_admin(society_id)
  and (user_id = auth.uid() or user_id is null)
);

-- Residents view own notifications
drop policy if exists "residents view own notifications" on public.notifications;
create policy "residents view own notifications"
on public.notifications for select to authenticated
using (
  user_id = auth.uid()
  or (
    public.is_society_member(society_id)
    and user_id is null
    and target_role in ('resident', 'all')
  )
);

drop policy if exists "residents update own notification read status" on public.notifications;
create policy "residents update own notification read status"
on public.notifications for update to authenticated
using (user_id = auth.uid() or user_id is null);

-- ------------------------------------------------------------
-- 3) AUTOMATIC NOTIFICATION TRIGGERS
-- ------------------------------------------------------------

-- Trigger on Join Request creation -> Notify Society Admins
create or replace function public.notify_on_join_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (
    society_id,
    user_id,
    target_role,
    title,
    body,
    type,
    entity_type,
    entity_id,
    route
  ) values (
    new.society_id,
    null,
    'society_admin',
    'New Resident Approval Request',
    new.full_name || ' requested to join as ' || new.resident_type,
    'join_request_created',
    'join_request',
    new.id::text,
    '/admin-approvals'
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_join_request on public.resident_join_requests;
create trigger trg_notify_join_request
after insert on public.resident_join_requests
for each row execute function public.notify_on_join_request();

-- Trigger on Join Request approval/rejection -> Notify Resident
create or replace function public.notify_on_join_request_reviewed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('approved', 'rejected') and old.status = 'pending' then
    insert into public.notifications (
      society_id,
      user_id,
      target_role,
      title,
      body,
      type,
      entity_type,
      entity_id,
      route
    ) values (
      new.society_id,
      new.user_id,
      'resident',
      case when new.status = 'approved' then 'Join Request Approved 🎉' else 'Join Request Rejected' end,
      case when new.status = 'approved'
        then 'Your request to join the society has been approved by the admin!'
        else coalesce('Reason: ' || new.rejection_reason, 'Your join request was declined by society administration.')
      end,
      case when new.status = 'approved' then 'join_request_approved' else 'join_request_rejected' end,
      'join_request',
      new.id::text,
      '/'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_join_request_reviewed on public.resident_join_requests;
create trigger trg_notify_join_request_reviewed
after update on public.resident_join_requests
for each row execute function public.notify_on_join_request_reviewed();

-- Trigger on Complaint creation -> Notify Society Admins
create or replace function public.notify_on_complaint_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_flat_info text := '';
begin
  select ' (Flat ' || coalesce(f.flat_number, '') || ')' into v_flat_info
    from public.flats f where f.id = new.flat_id;

  insert into public.notifications (
    society_id,
    user_id,
    target_role,
    title,
    body,
    type,
    entity_type,
    entity_id,
    route
  ) values (
    new.society_id,
    null,
    'society_admin',
    case when new.category = 'security' then '🚨 Security Complaint Raised' else 'New Complaint: ' || new.title end,
    'A new ' || new.category || ' complaint was raised' || v_flat_info,
    'complaint_created',
    'complaint',
    new.id::text,
    '/complaints'
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_complaint_created on public.complaints;
create trigger trg_notify_complaint_created
after insert on public.complaints
for each row execute function public.notify_on_complaint_created();

-- Trigger on Complaint Status Change -> Notify Resident or Admin
create or replace function public.notify_on_complaint_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complaint record;
  v_resident_user_id uuid;
begin
  select * into v_complaint from public.complaints where id = new.complaint_id;
  if v_complaint.id is null then return new; end if;

  select user_id into v_resident_user_id from public.residents where id = v_complaint.raised_by;

  if new.changed_by_role = 'society_admin' and v_resident_user_id is not null then
    -- Admin updated status -> notify resident
    insert into public.notifications (
      society_id,
      user_id,
      target_role,
      title,
      body,
      type,
      entity_type,
      entity_id,
      route
    ) values (
      v_complaint.society_id,
      v_resident_user_id,
      'resident',
      case
        when new.to_status = 'resolved' then 'Complaint Resolved 🛠️'
        when new.to_status = 'in_progress' then 'Work Started on Complaint ⏳'
        else 'Complaint Update'
      end,
      'Status updated to ' || new.to_status || coalesce(' · Note: ' || new.note, ''),
      case
        when new.to_status = 'resolved' then 'complaint_resolved'
        else 'complaint_updated'
      end,
      'complaint',
      new.complaint_id::text,
      '/complaints'
    );
  elsif new.changed_by_role = 'resident' and new.to_status in ('reopened', 'closed') then
    -- Resident reopened or closed -> notify society admin
    insert into public.notifications (
      society_id,
      user_id,
      target_role,
      title,
      body,
      type,
      entity_type,
      entity_id,
      route
    ) values (
      v_complaint.society_id,
      null,
      'society_admin',
      case
        when new.to_status = 'reopened' then 'Complaint Reopened ⚠️'
        else 'Complaint Confirmed & Closed ✅'
      end,
      'Resident marked complaint "' || v_complaint.title || '" as ' || new.to_status || coalesce(': ' || new.note, ''),
      case
        when new.to_status = 'reopened' then 'complaint_reopened'
        else 'complaint_closed'
      end,
      'complaint',
      new.complaint_id::text,
      '/complaints'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_complaint_history on public.complaint_status_history;
create trigger trg_notify_complaint_history
after insert on public.complaint_status_history
for each row execute function public.notify_on_complaint_history();

-- ------------------------------------------------------------
-- 4) RPC FUNCTIONS
-- ------------------------------------------------------------
create or replace function public.mark_notification_as_read(p_notification_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications
     set is_read = true
   where id = p_notification_id;

  return json_build_object('success', true);
end;
$$;

create or replace function public.mark_all_notifications_as_read(p_society_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications
     set is_read = true
   where society_id = p_society_id
     and (user_id = auth.uid() or user_id is null);

  return json_build_object('success', true);
end;
$$;

grant execute on function public.mark_notification_as_read(uuid) to authenticated;
grant execute on function public.mark_all_notifications_as_read(uuid) to authenticated;
