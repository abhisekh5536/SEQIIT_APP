-- ============================================================
-- MIGRATION 08: Notices & Announcements Module
-- Provides tables, RLS, storage bucket, triggers, and RPC functions
-- for scheduled notices, event announcements, targeting, read tracking,
-- and mandatory resident acknowledgments.
-- ============================================================

-- ------------------------------------------------------------
-- 1) TABLE: notices
-- ------------------------------------------------------------
create table if not exists public.notices (
  id                      uuid primary key default gen_random_uuid(),
  society_id              uuid not null references public.societies(id) on delete cascade,
  title                   text not null,
  body                    text not null,
  category                text not null default 'general' check (category in
                            ('important', 'event', 'safety', 'maintenance', 'billing', 'general')),
  attachment_url          text,

  target_type             text not null default 'all' check (target_type in ('all', 'block')),
  target_block_id         uuid references public.blocks(id) on delete set null,

  -- Event-specific fields
  is_event                boolean not null default false,
  event_starts_at         timestamptz,
  event_ends_at           timestamptz,
  event_venue             text,

  is_pinned               boolean not null default false,
  requires_acknowledgment boolean not null default false,

  status                  text not null default 'draft' check (status in
                            ('draft', 'scheduled', 'published', 'expired', 'archived')),

  publish_at              timestamptz not null default now(),
  expires_at              timestamptz,

  created_by              uuid references auth.users(id) on delete set null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),

  constraint event_fields_required check (
    not is_event or (event_starts_at is not null and event_ends_at is not null)
  ),
  constraint event_end_after_start check (
    event_ends_at is null or event_starts_at is null or event_ends_at >= event_starts_at
  )
);

create index if not exists idx_notices_society_status   on public.notices(society_id, status);
create index if not exists idx_notices_publish_at       on public.notices(publish_at);
create index if not exists idx_notices_expires_at       on public.notices(expires_at);
create index if not exists idx_notices_target_block     on public.notices(target_block_id);
create index if not exists idx_notices_pinned           on public.notices(is_pinned, created_at desc);
create index if not exists idx_notices_event_starts_at  on public.notices(event_starts_at) where is_event = true;

-- Keep updated_at fresh
drop trigger if exists trg_notices_updated on public.notices;
create trigger trg_notices_updated
before update on public.notices
for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 2) TABLE: notice_reads
-- ------------------------------------------------------------
create table if not exists public.notice_reads (
  id            uuid primary key default gen_random_uuid(),
  notice_id     uuid not null references public.notices(id) on delete cascade,
  resident_id   uuid not null references public.residents(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete set null,
  read_at       timestamptz not null default now(),
  constraint uq_notice_resident_read unique (notice_id, resident_id)
);

create index if not exists idx_notice_reads_notice    on public.notice_reads(notice_id);
create index if not exists idx_notice_reads_resident  on public.notice_reads(resident_id);

-- ------------------------------------------------------------
-- 3) TABLE: notice_acknowledgments
-- ------------------------------------------------------------
create table if not exists public.notice_acknowledgments (
  id              uuid primary key default gen_random_uuid(),
  notice_id       uuid not null references public.notices(id) on delete cascade,
  resident_id     uuid not null references public.residents(id) on delete cascade,
  user_id         uuid references auth.users(id) on delete set null,
  acknowledged_at timestamptz not null default now(),
  constraint uq_notice_resident_ack unique (notice_id, resident_id)
);

create index if not exists idx_notice_acks_notice    on public.notice_acknowledgments(notice_id);
create index if not exists idx_notice_acks_resident  on public.notice_acknowledgments(resident_id);

-- ------------------------------------------------------------
-- 4) ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------
alter table public.notices enable row level security;
alter table public.notice_reads enable row level security;
alter table public.notice_acknowledgments enable row level security;

-- Master Admins full access
drop policy if exists "master admins full access to notices" on public.notices;
create policy "master admins full access to notices"
on public.notices for all to authenticated
using (public.is_master_admin());

drop policy if exists "master admins full access to notice reads" on public.notice_reads;
create policy "master admins full access to notice reads"
on public.notice_reads for all to authenticated
using (public.is_master_admin());

drop policy if exists "master admins full access to notice acks" on public.notice_acknowledgments;
create policy "master admins full access to notice acks"
on public.notice_acknowledgments for all to authenticated
using (public.is_master_admin());

-- Society Admins manage own society's notices
drop policy if exists "society admins manage own notices" on public.notices;
create policy "society admins manage own notices"
on public.notices for all to authenticated
using (public.is_society_admin(society_id))
with check (public.is_society_admin(society_id));

-- Society Admins view read & ack stats
drop policy if exists "society admins view read stats" on public.notice_reads;
create policy "society admins view read stats"
on public.notice_reads for select to authenticated
using (
  notice_id in (
    select n.id from public.notices n where public.is_society_admin(n.society_id)
  )
);

drop policy if exists "society admins view ack stats" on public.notice_acknowledgments;
create policy "society admins view ack stats"
on public.notice_acknowledgments for select to authenticated
using (
  notice_id in (
    select n.id from public.notices n where public.is_society_admin(n.society_id)
  )
);

-- Residents view published notices targeted to them
drop policy if exists "residents view published notices for their scope" on public.notices;
create policy "residents view published notices for their scope"
on public.notices for select to authenticated
using (
  (
    status = 'published'
    and publish_at <= now()
    and (expires_at is null or expires_at > now())
    and (
      target_type = 'all'
      or target_block_id is null
      or target_block_id in (
        select f.block_id from public.residents r
        join public.flats f on f.id = r.flat_id
        where r.user_id = auth.uid() and r.society_id = notices.society_id
      )
    )
  )
  or public.is_society_admin(society_id)
);

-- Residents insert & view their own read records
drop policy if exists "residents mark own reads" on public.notice_reads;
create policy "residents mark own reads"
on public.notice_reads for insert to authenticated
with check (
  resident_id in (
    select r.id from public.residents r where r.user_id = auth.uid()
  )
);

drop policy if exists "residents view own reads" on public.notice_reads;
create policy "residents view own reads"
on public.notice_reads for select to authenticated
using (
  resident_id in (
    select r.id from public.residents r where r.user_id = auth.uid()
  )
);

-- Residents insert & view their own acknowledgment records
drop policy if exists "residents mark own acknowledgment" on public.notice_acknowledgments;
create policy "residents mark own acknowledgment"
on public.notice_acknowledgments for insert to authenticated
with check (
  resident_id in (
    select r.id from public.residents r where r.user_id = auth.uid()
  )
);

drop policy if exists "residents view own acks" on public.notice_acknowledgments;
create policy "residents view own acks"
on public.notice_acknowledgments for select to authenticated
using (
  resident_id in (
    select r.id from public.residents r where r.user_id = auth.uid()
  )
);

-- ------------------------------------------------------------
-- 5) AUTOMATIC NOTIFICATION TRIGGER ON NOTICE PUBLISH
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
  if (new.status = 'published') and (TG_OP = 'INSERT' or old.status is distinct from 'published') then
    -- Only attempt to insert if notifications table exists in database
    if to_regclass('public.notifications') is not null then
      v_category_label := case new.category
        when 'important' then '⚠️ Important Notice'
        when 'event' then '🎉 Upcoming Event'
        when 'safety' then '🛡️ Safety Alert'
        when 'maintenance' then '🔧 Maintenance Update'
        when 'billing' then '💳 Billing Notice'
        else '📢 Notice'
      end;

      execute $sql$
        insert into public.notifications (
          society_id,
          user_id,
          target_role,
          title,
          body,
          type,
          entity_type,
          entity_id,
          route,
          is_read,
          created_at
        ) values (
          $1,
          null,
          'resident',
          $2,
          $3,
          'notice',
          'notice',
          $4,
          '/notices',
          false,
          now()
        )
      $sql$ using new.society_id, (v_category_label || ': ' || new.title), substring(new.body from 1 for 140), new.id::text;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notice_published on public.notices;
create trigger trg_notice_published
after update on public.notices
for each row execute function public.notify_on_notice_published();

drop trigger if exists trg_notice_published_insert on public.notices;
create trigger trg_notice_published_insert
after insert on public.notices
for each row execute function public.notify_on_notice_published();

-- ------------------------------------------------------------
-- 6) RPC: Auto-publish and Auto-expire due notices
-- ------------------------------------------------------------
create or replace function public.publish_due_notices()
returns table (
  published_count int,
  expired_count int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pub int := 0;
  v_exp int := 0;
begin
  with updated_pub as (
    update public.notices
    set status = 'published', updated_at = now()
    where status = 'scheduled' and publish_at <= now()
    returning id
  )
  select count(*) into v_pub from updated_pub;

  with updated_exp as (
    update public.notices
    set status = 'expired', updated_at = now()
    where status = 'published' and expires_at is not null and expires_at <= now()
    returning id
  )
  select count(*) into v_exp from updated_exp;

  return query select v_pub, v_exp;
end;
$$;

-- ------------------------------------------------------------
-- 7) STORAGE BUCKET: notice-attachments
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('notice-attachments', 'notice-attachments', true)
on conflict (id) do update set public = true;

drop policy if exists "Public notice attachments are readable" on storage.objects;
create policy "Public notice attachments are readable"
on storage.objects for select to public
using (bucket_id = 'notice-attachments');

drop policy if exists "Authenticated users upload notice attachments" on storage.objects;
create policy "Authenticated users upload notice attachments"
on storage.objects for insert to authenticated
with check (bucket_id = 'notice-attachments');

drop policy if exists "Authenticated users update own notice attachments" on storage.objects;
create policy "Authenticated users update own notice attachments"
on storage.objects for update to authenticated
using (bucket_id = 'notice-attachments');

drop policy if exists "Authenticated users delete own notice attachments" on storage.objects;
create policy "Authenticated users delete own notice attachments"
on storage.objects for delete to authenticated
using (bucket_id = 'notice-attachments');
