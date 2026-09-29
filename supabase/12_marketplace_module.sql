-- ============================================================
-- MIGRATION 12: Marketplace Module (Phase 5)
-- Includes:
--   1) marketplace_categories   (global defaults + per-society additions)
--   2) marketplace_listings     (resident posts, society-scoped)
--   3) marketplace_images       (URLs into the marketplace-images bucket)
--   4) marketplace_reports      (resident reports → admin moderation queue)
--   5) marketplace_blocked_residents (admin posting bans)
--   6) marketplace_settings     (per-society expiry / auto-flag policy)
--   7) Server Action RPCs — seller identity and society scope are ALWAYS
--      derived from auth.uid(), never from client parameters:
--        - get_marketplace_context
--        - get_marketplace_feed
--        - get_marketplace_listing
--        - reveal_marketplace_seller_phone
--        - create_marketplace_listing
--        - update_marketplace_listing
--        - set_marketplace_listing_status
--        - report_marketplace_listing
--        - resolve_marketplace_report
--        - set_marketplace_enabled      (module_flags, module_key = 'marketplace')
--        - update_marketplace_settings
--        - expire_marketplace_listings  (auto-expiry; pg_cron if available)
--   8) RLS policies, notification types, storage bucket
--
-- Seller name / flat / block / phone are NEVER copied into listings —
-- they are joined from residents → flats → blocks at read time.
-- Residents cannot read each other's resident rows (residents_select),
-- so all cross-resident reads go through the security-definer RPCs below.
-- ============================================================

-- ------------------------------------------------------------
-- 0) HELPERS
-- ------------------------------------------------------------

-- The caller's own active resident record (primary flat first).
create or replace function public.mkt_my_resident_id()
returns uuid
language sql stable security definer set search_path = public as $$
  select r.id
    from public.residents r
   where r.user_id = auth.uid()
     and r.status = 'active'
   order by r.is_primary desc, r.created_at asc
   limit 1;
$$;

-- The caller's society: society admin first, else their resident record.
create or replace function public.mkt_my_society_id()
returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select a.society_id from public.society_admin_users a
      where a.id = auth.uid() limit 1),
    (select r.society_id from public.residents r
      where r.id = public.mkt_my_resident_id())
  );
$$;

-- Module flag lookup. No row = enabled (opt-out, like the other modules).
create or replace function public.is_marketplace_enabled(p_society_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select m.enabled from public.module_flags m
      where m.society_id = p_society_id
        and m.module_key = 'marketplace'
      limit 1),
    true
  );
$$;

grant execute on function public.mkt_my_resident_id() to authenticated;
grant execute on function public.mkt_my_society_id() to authenticated;
grant execute on function public.is_marketplace_enabled(uuid) to authenticated;

-- ------------------------------------------------------------
-- 1) TABLE: marketplace_categories
-- society_id null = global default visible to every society.
-- ------------------------------------------------------------
create table if not exists public.marketplace_categories (
  id          uuid primary key default gen_random_uuid(),
  society_id  uuid references public.societies(id) on delete cascade,
  name        text not null check (char_length(trim(name)) between 2 and 40),
  icon_key    text not null default 'other',
  sort_order  int not null default 100,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create unique index if not exists uq_marketplace_category_name
  on public.marketplace_categories (
    coalesce(society_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(trim(name))
  );
create index if not exists idx_marketplace_categories_society
  on public.marketplace_categories (society_id);

insert into public.marketplace_categories (society_id, name, icon_key, sort_order) values
  (null, 'Furniture',             'furniture',   10),
  (null, 'Electronics',           'electronics', 20),
  (null, 'Home & Kitchen',        'kitchen',     30),
  (null, 'Baby & Kids',           'kids',        40),
  (null, 'Books & Stationery',    'books',       50),
  (null, 'Vehicles',              'vehicles',    60),
  (null, 'Clothing & Accessories','clothing',    70),
  (null, 'Sports & Fitness',      'sports',      80),
  (null, 'Other',                 'other',      999)
on conflict do nothing;

-- ------------------------------------------------------------
-- 2) TABLE: marketplace_listings
-- society_id is a deliberate denormalization: it is the single
-- indexed filter that enforces "same society only".
-- ------------------------------------------------------------
create table if not exists public.marketplace_listings (
  id              uuid primary key default gen_random_uuid(),
  society_id      uuid not null references public.societies(id) on delete cascade,
  resident_id     uuid not null references public.residents(id) on delete cascade,
  category_id     uuid references public.marketplace_categories(id) on delete set null,
  title           text not null check (char_length(trim(title)) between 3 and 80),
  description     text check (description is null or char_length(description) <= 2000),
  price           numeric(12,2) check (price is null or price >= 0),
  price_type      text not null default 'fixed'
                    check (price_type in ('fixed', 'negotiable', 'free', 'on_request')),
  status          text not null default 'active'
                    check (status in ('active', 'sold', 'removed', 'flagged', 'expired')),
  removed_reason  text,
  report_count    int not null default 0,
  sold_at         timestamptz,
  expires_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint chk_marketplace_price_matches_type check (
    (price_type in ('fixed', 'negotiable') and price is not null)
    or (price_type in ('free', 'on_request') and price is null)
  )
);

create index if not exists idx_marketplace_listings_feed
  on public.marketplace_listings (society_id, status, created_at desc);
create index if not exists idx_marketplace_listings_resident
  on public.marketplace_listings (resident_id);
create index if not exists idx_marketplace_listings_category
  on public.marketplace_listings (category_id);
create index if not exists idx_marketplace_listings_expiry
  on public.marketplace_listings (expires_at) where status = 'active';

drop trigger if exists trg_marketplace_listings_updated on public.marketplace_listings;
create trigger trg_marketplace_listings_updated
before update on public.marketplace_listings
for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3) TABLE: marketplace_images
-- ------------------------------------------------------------
create table if not exists public.marketplace_images (
  id          uuid primary key default gen_random_uuid(),
  listing_id  uuid not null references public.marketplace_listings(id) on delete cascade,
  image_url   text not null,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists idx_marketplace_images_listing
  on public.marketplace_images (listing_id, sort_order);

-- ------------------------------------------------------------
-- 4) TABLE: marketplace_reports
-- ------------------------------------------------------------
create table if not exists public.marketplace_reports (
  id            uuid primary key default gen_random_uuid(),
  society_id    uuid not null references public.societies(id) on delete cascade,
  listing_id    uuid not null references public.marketplace_listings(id) on delete cascade,
  reported_by   uuid references public.residents(id) on delete set null,
  reason        text not null
                  check (reason in ('spam', 'inappropriate', 'prohibited', 'fraud', 'other')),
  details       text check (details is null or char_length(details) <= 500),
  status        text not null default 'pending' check (status in ('pending', 'reviewed')),
  action_taken  text check (action_taken in (
                  'dismissed', 'seller_warned', 'listing_removed', 'seller_blocked'
                )),
  admin_note    text,
  reviewed_by   uuid references auth.users(id) on delete set null,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);

-- One open report per resident per listing.
create unique index if not exists uq_marketplace_report_pending
  on public.marketplace_reports (listing_id, reported_by)
  where status = 'pending';
create index if not exists idx_marketplace_reports_queue
  on public.marketplace_reports (society_id, status, created_at desc);

-- ------------------------------------------------------------
-- 5) TABLE: marketplace_blocked_residents
-- ------------------------------------------------------------
create table if not exists public.marketplace_blocked_residents (
  society_id   uuid not null references public.societies(id) on delete cascade,
  resident_id  uuid not null references public.residents(id) on delete cascade,
  reason       text,
  blocked_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  primary key (society_id, resident_id)
);

-- ------------------------------------------------------------
-- 6) TABLE: marketplace_settings
-- ------------------------------------------------------------
create table if not exists public.marketplace_settings (
  society_id           uuid primary key references public.societies(id) on delete cascade,
  listing_expiry_days  int not null default 30 check (listing_expiry_days between 7 and 180),
  auto_flag_threshold  int not null default 3 check (auto_flag_threshold between 1 and 20),
  updated_at           timestamptz not null default now()
);

drop trigger if exists trg_marketplace_settings_updated on public.marketplace_settings;
create trigger trg_marketplace_settings_updated
before update on public.marketplace_settings
for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 7) NOTIFICATION TYPES
-- Keeps every type added by migrations 07, 09 and 10.
-- ------------------------------------------------------------
do $$
begin
  begin
    alter table public.notifications drop constraint if exists notifications_type_check;
    alter table public.notifications add constraint notifications_type_check
      check (type in (
        'complaint_created', 'complaint_updated', 'complaint_resolved',
        'complaint_reopened', 'complaint_closed', 'join_request_created',
        'join_request_approved', 'join_request_rejected', 'notice', 'general',
        'visitor_approval_request', 'visitor_approved', 'visitor_denied',
        'visitor_preapproved_created', 'visitor_checked_in', 'visitor_checked_out',
        'visitor_cancelled', 'visitor_expired',
        'sos_alert_raised', 'sos_alert_acknowledged', 'sos_alert_resolved', 'sos_alert_cancelled',
        'marketplace_report_submitted', 'marketplace_listing_reported',
        'marketplace_listing_removed', 'marketplace_seller_warned',
        'marketplace_seller_blocked'
      ));
  exception when others then
    raise notice 'Could not update notifications type check constraint: %', sqlerrm;
  end;
end $$;

-- Sends a personal notification to the resident's linked account (if any).
create or replace function public.mkt_notify_resident(
  p_resident_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_listing_id uuid
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid;
  v_society_id uuid;
begin
  select r.user_id, r.society_id into v_user_id, v_society_id
    from public.residents r where r.id = p_resident_id;
  if v_user_id is null then
    return; -- resident hasn't signed up yet; nothing to deliver to
  end if;

  insert into public.notifications (
    society_id, user_id, target_role, title, body, type,
    entity_type, entity_id, route
  ) values (
    v_society_id, v_user_id, 'resident', p_title, p_body, p_type,
    'marketplace_listing', p_listing_id::text, '/marketplace'
  );
end;
$$;

-- ------------------------------------------------------------
-- 8) RPCs
-- ------------------------------------------------------------

-- 8.1 Context for the current user: society, module flag, poster identity.
create or replace function public.get_marketplace_context()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_society_id uuid := public.mkt_my_society_id();
  v_resident_id uuid := public.mkt_my_resident_id();
  v_settings record;
  v_seller record;
begin
  if v_society_id is null then
    return jsonb_build_object('success', false, 'error', 'You are not linked to a society yet');
  end if;

  select s.listing_expiry_days, s.auto_flag_threshold into v_settings
    from public.marketplace_settings s where s.society_id = v_society_id;

  select r.full_name, f.flat_number, b.name as block_name, (r.phone is not null and trim(r.phone) <> '') as has_phone
    into v_seller
    from public.residents r
    join public.flats f on f.id = r.flat_id
    left join public.blocks b on b.id = f.block_id
   where r.id = v_resident_id;

  return jsonb_build_object(
    'success', true,
    'society_id', v_society_id,
    'enabled', public.is_marketplace_enabled(v_society_id),
    'is_admin', public.is_society_admin(v_society_id),
    'resident_id', v_resident_id,
    'is_blocked', exists (
      select 1 from public.marketplace_blocked_residents br
       where br.society_id = v_society_id and br.resident_id = v_resident_id
    ),
    'seller_name', v_seller.full_name,
    'flat_number', v_seller.flat_number,
    'block_name', v_seller.block_name,
    'has_phone', coalesce(v_seller.has_phone, false),
    'listing_expiry_days', coalesce(v_settings.listing_expiry_days, 30),
    'auto_flag_threshold', coalesce(v_settings.auto_flag_threshold, 3)
  );
end;
$$;

grant execute on function public.get_marketplace_context() to authenticated;

-- 8.2 Society-scoped feed. The society comes from the session only.
create or replace function public.get_marketplace_feed(
  p_category_id uuid default null,
  p_search text default null,
  p_sort text default 'newest',
  p_limit int default 40,
  p_offset int default 0
)
returns table (
  id               uuid,
  title            text,
  description      text,
  price            numeric,
  price_type       text,
  status           text,
  category_id      uuid,
  category_name    text,
  category_icon    text,
  created_at       timestamptz,
  expires_at       timestamptz,
  cover_image_url  text,
  image_count      int,
  seller_name      text,
  flat_number      text,
  block_name       text,
  is_mine          boolean
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_society_id uuid := public.mkt_my_society_id();
  v_my_resident uuid := public.mkt_my_resident_id();
  v_search text := nullif(trim(coalesce(p_search, '')), '');
begin
  if v_society_id is null or not public.is_marketplace_enabled(v_society_id) then
    return;
  end if;

  return query
  -- Explicit casts: RETURN QUERY needs exact type matches, and the
  -- pre-existing flats/blocks/residents columns may be varchar.
  select
    l.id, l.title, l.description, l.price::numeric, l.price_type, l.status,
    l.category_id, c.name::text, c.icon_key::text,
    l.created_at, l.expires_at,
    (select i.image_url from public.marketplace_images i
      where i.listing_id = l.id order by i.sort_order, i.created_at limit 1),
    (select count(*)::int from public.marketplace_images i where i.listing_id = l.id),
    r.full_name::text, f.flat_number::text, b.name::text,
    coalesce(l.resident_id = v_my_resident, false)
  from public.marketplace_listings l
  join public.residents r on r.id = l.resident_id and r.status = 'active'
  join public.flats f on f.id = r.flat_id
  left join public.blocks b on b.id = f.block_id
  left join public.marketplace_categories c on c.id = l.category_id
  where l.society_id = v_society_id
    and l.status = 'active'
    and (l.expires_at is null or l.expires_at > now())
    and (p_category_id is null or l.category_id = p_category_id)
    and (v_search is null
         or l.title ilike '%' || v_search || '%'
         or l.description ilike '%' || v_search || '%')
  order by
    case when p_sort = 'price_low'
         then (case when l.price_type = 'free' then 0 else l.price end) end asc nulls last,
    case when p_sort = 'price_high' then l.price end desc nulls last,
    l.created_at desc
  limit greatest(1, least(coalesce(p_limit, 40), 100))
  offset greatest(0, coalesce(p_offset, 0));
end;
$$;

grant execute on function public.get_marketplace_feed(uuid, text, text, int, int) to authenticated;

-- 8.3 Listing detail with images and live seller info (phone excluded).
create or replace function public.get_marketplace_listing(p_listing_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_society_id uuid := public.mkt_my_society_id();
  v_my_resident uuid := public.mkt_my_resident_id();
  v_is_admin boolean;
  v_l record;
begin
  select l.*, c.name as category_name, c.icon_key as category_icon,
         r.full_name as seller_name, r.phone as seller_phone,
         r.status as seller_status,
         f.flat_number, b.name as block_name
    into v_l
    from public.marketplace_listings l
    join public.residents r on r.id = l.resident_id
    join public.flats f on f.id = r.flat_id
    left join public.blocks b on b.id = f.block_id
    left join public.marketplace_categories c on c.id = l.category_id
   where l.id = p_listing_id;

  if not found or v_l.society_id is distinct from v_society_id then
    return jsonb_build_object('success', false, 'error', 'Listing not found');
  end if;

  v_is_admin := public.is_society_admin(v_l.society_id);

  if v_l.status <> 'active'
     and v_l.resident_id is distinct from v_my_resident
     and not v_is_admin then
    return jsonb_build_object('success', false, 'error', 'This listing is no longer available');
  end if;

  return jsonb_build_object(
    'success', true,
    'listing', jsonb_build_object(
      'id', v_l.id,
      'society_id', v_l.society_id,
      'resident_id', v_l.resident_id,
      'category_id', v_l.category_id,
      'category_name', v_l.category_name,
      'category_icon', v_l.category_icon,
      'title', v_l.title,
      'description', v_l.description,
      'price', v_l.price,
      'price_type', v_l.price_type,
      'status', v_l.status,
      'removed_reason', v_l.removed_reason,
      'report_count', v_l.report_count,
      'sold_at', v_l.sold_at,
      'expires_at', v_l.expires_at,
      'created_at', v_l.created_at,
      'updated_at', v_l.updated_at,
      'seller_name', v_l.seller_name,
      'flat_number', v_l.flat_number,
      'block_name', v_l.block_name,
      'seller_active', v_l.seller_status = 'active',
      'has_seller_phone', v_l.seller_phone is not null and trim(v_l.seller_phone) <> '',
      'is_mine', v_l.resident_id = v_my_resident,
      'viewer_is_admin', v_is_admin,
      'my_report_pending', exists (
        select 1 from public.marketplace_reports mr
         where mr.listing_id = v_l.id
           and mr.reported_by = v_my_resident
           and mr.status = 'pending'
      ),
      'images', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', i.id, 'image_url', i.image_url, 'sort_order', i.sort_order
               ) order by i.sort_order, i.created_at)
          from public.marketplace_images i where i.listing_id = v_l.id
      ), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_marketplace_listing(uuid) to authenticated;

-- 8.4 Tap-to-reveal: the seller's phone is read live from residents.phone.
create or replace function public.reveal_marketplace_seller_phone(p_listing_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_society_id uuid := public.mkt_my_society_id();
  v_row record;
begin
  select l.society_id, l.status, r.phone, r.status as seller_status
    into v_row
    from public.marketplace_listings l
    join public.residents r on r.id = l.resident_id
   where l.id = p_listing_id;

  if not found or v_row.society_id is distinct from v_society_id then
    return jsonb_build_object('success', false, 'error', 'Listing not found');
  end if;
  if v_row.status <> 'active' and not public.is_society_admin(v_row.society_id) then
    return jsonb_build_object('success', false, 'error', 'This listing is no longer available');
  end if;
  if v_row.seller_status <> 'active' then
    return jsonb_build_object('success', false, 'error', 'The seller has moved out of the society');
  end if;
  if v_row.phone is null or trim(v_row.phone) = '' then
    return jsonb_build_object('success', false, 'error', 'The seller has not added a phone number');
  end if;

  return jsonb_build_object('success', true, 'phone', trim(v_row.phone));
end;
$$;

grant execute on function public.reveal_marketplace_seller_phone(uuid) to authenticated;

-- Shared validation for create/update. Returns an error message or null.
create or replace function public.mkt_validate_listing(
  p_society_id uuid,
  p_title text,
  p_description text,
  p_price numeric,
  p_price_type text,
  p_category_id uuid,
  p_image_urls text[]
)
returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if p_title is null or char_length(trim(p_title)) < 3 then
    return 'Title must be at least 3 characters';
  end if;
  if char_length(trim(p_title)) > 80 then
    return 'Title must be 80 characters or fewer';
  end if;
  if p_description is not null and char_length(p_description) > 2000 then
    return 'Description must be 2000 characters or fewer';
  end if;
  if p_price_type is null or p_price_type not in ('fixed', 'negotiable', 'free', 'on_request') then
    return 'Invalid price type';
  end if;
  if p_price_type in ('fixed', 'negotiable') and (p_price is null or p_price < 0) then
    return 'Enter a valid price';
  end if;
  if p_price is not null and p_price > 9999999999 then
    return 'Price is too large';
  end if;
  if p_category_id is null or not exists (
    select 1 from public.marketplace_categories c
     where c.id = p_category_id
       and c.is_active
       and (c.society_id is null or c.society_id = p_society_id)
  ) then
    return 'Choose a valid category';
  end if;
  if coalesce(array_length(p_image_urls, 1), 0) > 6 then
    return 'You can add up to 6 photos';
  end if;
  return null;
end;
$$;

-- 8.5 Create a listing. Seller + society are taken from the session.
create or replace function public.create_marketplace_listing(
  p_title text,
  p_description text,
  p_price numeric,
  p_price_type text,
  p_category_id uuid,
  p_image_urls text[] default '{}'
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resident_id uuid := public.mkt_my_resident_id();
  v_society_id uuid;
  v_expiry_days int;
  v_error text;
  v_listing_id uuid;
begin
  if v_resident_id is null then
    return jsonb_build_object('success', false, 'error', 'Only residents can post listings');
  end if;

  select r.society_id into v_society_id from public.residents r where r.id = v_resident_id;

  if not public.is_marketplace_enabled(v_society_id) then
    return jsonb_build_object('success', false, 'error', 'Marketplace is turned off for your society');
  end if;
  if exists (select 1 from public.marketplace_blocked_residents br
              where br.society_id = v_society_id and br.resident_id = v_resident_id) then
    return jsonb_build_object('success', false, 'error', 'Your society office has paused your marketplace posting');
  end if;

  v_error := public.mkt_validate_listing(
    v_society_id, p_title, p_description, p_price, p_price_type, p_category_id, p_image_urls);
  if v_error is not null then
    return jsonb_build_object('success', false, 'error', v_error);
  end if;

  select coalesce(s.listing_expiry_days, 30) into v_expiry_days
    from public.marketplace_settings s where s.society_id = v_society_id;
  v_expiry_days := coalesce(v_expiry_days, 30);

  insert into public.marketplace_listings (
    society_id, resident_id, category_id, title, description,
    price, price_type, status, expires_at
  ) values (
    v_society_id, v_resident_id, p_category_id, trim(p_title),
    nullif(trim(coalesce(p_description, '')), ''),
    case when p_price_type in ('fixed', 'negotiable') then p_price else null end,
    p_price_type, 'active', now() + make_interval(days => v_expiry_days)
  ) returning id into v_listing_id;

  insert into public.marketplace_images (listing_id, image_url, sort_order)
  select v_listing_id, u.url, (u.ord - 1)::int
    from unnest(coalesce(p_image_urls, '{}'::text[])) with ordinality as u(url, ord)
   where u.url is not null and trim(u.url) <> '';

  return jsonb_build_object('success', true, 'listing_id', v_listing_id);
end;
$$;

grant execute on function public.create_marketplace_listing(text, text, numeric, text, uuid, text[]) to authenticated;

-- 8.6 Edit a listing (owner only). p_image_urls replaces the photo set.
create or replace function public.update_marketplace_listing(
  p_listing_id uuid,
  p_title text,
  p_description text,
  p_price numeric,
  p_price_type text,
  p_category_id uuid,
  p_image_urls text[] default '{}'
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resident_id uuid := public.mkt_my_resident_id();
  v_l record;
  v_error text;
begin
  select * into v_l from public.marketplace_listings where id = p_listing_id;
  if not found or v_l.resident_id is distinct from v_resident_id then
    return jsonb_build_object('success', false, 'error', 'You can only edit your own listings');
  end if;
  if v_l.status = 'removed' then
    return jsonb_build_object('success', false, 'error', 'This listing was removed by the society office');
  end if;

  v_error := public.mkt_validate_listing(
    v_l.society_id, p_title, p_description, p_price, p_price_type, p_category_id, p_image_urls);
  if v_error is not null then
    return jsonb_build_object('success', false, 'error', v_error);
  end if;

  update public.marketplace_listings
     set title = trim(p_title),
         description = nullif(trim(coalesce(p_description, '')), ''),
         price = case when p_price_type in ('fixed', 'negotiable') then p_price else null end,
         price_type = p_price_type,
         category_id = p_category_id
   where id = p_listing_id;

  delete from public.marketplace_images where listing_id = p_listing_id;
  insert into public.marketplace_images (listing_id, image_url, sort_order)
  select p_listing_id, u.url, (u.ord - 1)::int
    from unnest(coalesce(p_image_urls, '{}'::text[])) with ordinality as u(url, ord)
   where u.url is not null and trim(u.url) <> '';

  return jsonb_build_object('success', true, 'listing_id', p_listing_id);
end;
$$;

grant execute on function public.update_marketplace_listing(uuid, text, text, numeric, text, uuid, text[]) to authenticated;

-- 8.7 Status changes.
--   Owner: 'sold' (from active/expired), 'active' (relist from sold/expired; resets expiry)
--   Admin: 'removed' (any), 'active' (restore from flagged/removed)
create or replace function public.set_marketplace_listing_status(
  p_listing_id uuid,
  p_status text,
  p_reason text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resident_id uuid := public.mkt_my_resident_id();
  v_l record;
  v_is_owner boolean;
  v_is_admin boolean;
  v_expiry_days int;
begin
  select * into v_l from public.marketplace_listings where id = p_listing_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Listing not found');
  end if;

  v_is_owner := v_l.resident_id = v_resident_id;
  v_is_admin := public.is_society_admin(v_l.society_id) or public.is_master_admin();

  select coalesce(s.listing_expiry_days, 30) into v_expiry_days
    from public.marketplace_settings s where s.society_id = v_l.society_id;
  v_expiry_days := coalesce(v_expiry_days, 30);

  if p_status = 'sold' and v_is_owner then
    if v_l.status not in ('active', 'expired') then
      return jsonb_build_object('success', false, 'error', 'Only live listings can be marked sold');
    end if;
    update public.marketplace_listings
       set status = 'sold', sold_at = now()
     where id = p_listing_id;

  elsif p_status = 'active' and v_is_owner and v_l.status in ('sold', 'expired') then
    if exists (select 1 from public.marketplace_blocked_residents br
                where br.society_id = v_l.society_id and br.resident_id = v_l.resident_id) then
      return jsonb_build_object('success', false, 'error', 'Your society office has paused your marketplace posting');
    end if;
    update public.marketplace_listings
       set status = 'active', sold_at = null,
           expires_at = now() + make_interval(days => v_expiry_days)
     where id = p_listing_id;

  elsif p_status = 'removed' and v_is_admin then
    update public.marketplace_listings
       set status = 'removed',
           removed_reason = nullif(trim(coalesce(p_reason, '')), '')
     where id = p_listing_id;
    update public.marketplace_reports
       set status = 'reviewed', action_taken = 'listing_removed',
           reviewed_by = auth.uid(), reviewed_at = now()
     where listing_id = p_listing_id and status = 'pending';
    perform public.mkt_notify_resident(
      v_l.resident_id, 'marketplace_listing_removed',
      'Listing removed: ' || v_l.title,
      coalesce('Reason: ' || nullif(trim(coalesce(p_reason, '')), ''),
               'The society office removed this listing from the marketplace.'),
      p_listing_id);

  elsif p_status = 'active' and v_is_admin and v_l.status in ('flagged', 'removed') then
    update public.marketplace_listings
       set status = 'active', removed_reason = null,
           expires_at = greatest(coalesce(expires_at, now()), now() + interval '7 days')
     where id = p_listing_id;

  else
    return jsonb_build_object('success', false, 'error', 'That status change is not allowed');
  end if;

  return jsonb_build_object('success', true, 'listing_id', p_listing_id, 'status', p_status);
end;
$$;

grant execute on function public.set_marketplace_listing_status(uuid, text, text) to authenticated;

-- 8.8 Report a listing. Auto-flags (hides) it once enough residents report it.
create or replace function public.report_marketplace_listing(
  p_listing_id uuid,
  p_reason text,
  p_details text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_resident_id uuid := public.mkt_my_resident_id();
  v_l record;
  v_threshold int;
  v_pending int;
begin
  if v_resident_id is null then
    return jsonb_build_object('success', false, 'error', 'Only residents can report listings');
  end if;
  if p_reason is null or p_reason not in ('spam', 'inappropriate', 'prohibited', 'fraud', 'other') then
    return jsonb_build_object('success', false, 'error', 'Choose a reason');
  end if;

  select * into v_l from public.marketplace_listings where id = p_listing_id;
  if not found or v_l.society_id is distinct from public.mkt_my_society_id() then
    return jsonb_build_object('success', false, 'error', 'Listing not found');
  end if;
  if v_l.resident_id = v_resident_id then
    return jsonb_build_object('success', false, 'error', 'You cannot report your own listing');
  end if;
  if v_l.status not in ('active', 'flagged') then
    return jsonb_build_object('success', false, 'error', 'This listing is no longer live');
  end if;

  begin
    insert into public.marketplace_reports (society_id, listing_id, reported_by, reason, details)
    values (v_l.society_id, p_listing_id, v_resident_id, p_reason,
            nullif(trim(coalesce(p_details, '')), ''));
  exception when unique_violation then
    return jsonb_build_object('success', false, 'error', 'You have already reported this listing');
  end;

  select coalesce(s.auto_flag_threshold, 3) into v_threshold
    from public.marketplace_settings s where s.society_id = v_l.society_id;
  v_threshold := coalesce(v_threshold, 3);

  select count(*) into v_pending from public.marketplace_reports
   where listing_id = p_listing_id and status = 'pending';

  update public.marketplace_listings
     set report_count = report_count + 1,
         status = case when status = 'active' and v_pending >= v_threshold
                       then 'flagged' else status end
   where id = p_listing_id;

  insert into public.notifications (
    society_id, user_id, target_role, title, body, type, entity_type, entity_id, route
  ) values (
    v_l.society_id, null, 'society_admin',
    'Marketplace listing reported',
    '"' || v_l.title || '" was reported for ' || p_reason
      || case when v_pending >= v_threshold then ' and is hidden pending review' else '' end,
    'marketplace_report_submitted', 'marketplace_listing', p_listing_id::text, '/marketplace'
  );

  perform public.mkt_notify_resident(
    v_l.resident_id, 'marketplace_listing_reported',
    'Your listing was reported',
    '"' || v_l.title || '" was reported by a neighbour. The society office will review it.',
    p_listing_id);

  return jsonb_build_object('success', true, 'flagged', v_pending >= v_threshold);
end;
$$;

grant execute on function public.report_marketplace_listing(uuid, text, text) to authenticated;

-- 8.9 Admin resolves a report.
--   p_action: 'dismiss' | 'warn_seller' | 'remove_listing' | 'block_seller'
create or replace function public.resolve_marketplace_report(
  p_report_id uuid,
  p_action text,
  p_note text default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_rep record;
  v_l record;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  select * into v_rep from public.marketplace_reports where id = p_report_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Report not found');
  end if;
  if not (public.is_society_admin(v_rep.society_id) or public.is_master_admin()) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;
  if v_rep.status <> 'pending' then
    return jsonb_build_object('success', false, 'error', 'This report was already reviewed');
  end if;

  select * into v_l from public.marketplace_listings where id = v_rep.listing_id;

  if p_action = 'dismiss' then
    update public.marketplace_reports
       set status = 'reviewed', action_taken = 'dismissed', admin_note = v_note,
           reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_report_id;
    -- Un-hide an auto-flagged listing once nothing else is pending on it.
    if v_l.status = 'flagged' and not exists (
      select 1 from public.marketplace_reports
       where listing_id = v_l.id and status = 'pending'
    ) then
      update public.marketplace_listings set status = 'active' where id = v_l.id;
    end if;

  elsif p_action = 'warn_seller' then
    update public.marketplace_reports
       set status = 'reviewed', action_taken = 'seller_warned', admin_note = v_note,
           reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_report_id;
    perform public.mkt_notify_resident(
      v_l.resident_id, 'marketplace_seller_warned',
      'A note from the society office',
      coalesce(v_note, 'Please review your listing "' || v_l.title || '" against the marketplace guidelines.'),
      v_l.id);

  elsif p_action in ('remove_listing', 'block_seller') then
    update public.marketplace_listings
       set status = 'removed', removed_reason = coalesce(v_note, 'Removed after a resident report')
     where id = v_l.id;
    update public.marketplace_reports
       set status = 'reviewed',
           action_taken = case when p_action = 'block_seller' then 'seller_blocked' else 'listing_removed' end,
           admin_note = v_note, reviewed_by = auth.uid(), reviewed_at = now()
     where listing_id = v_l.id and status = 'pending';

    if p_action = 'block_seller' then
      insert into public.marketplace_blocked_residents (society_id, resident_id, reason, blocked_by)
      values (v_l.society_id, v_l.resident_id, coalesce(v_note, 'Blocked after a resident report'), auth.uid())
      on conflict (society_id, resident_id) do update
        set reason = excluded.reason, blocked_by = excluded.blocked_by, created_at = now();
      perform public.mkt_notify_resident(
        v_l.resident_id, 'marketplace_seller_blocked',
        'Marketplace posting paused',
        'The society office removed "' || v_l.title || '" and paused your marketplace posting.'
          || coalesce(' Note: ' || v_note, ''),
        v_l.id);
    else
      perform public.mkt_notify_resident(
        v_l.resident_id, 'marketplace_listing_removed',
        'Listing removed: ' || v_l.title,
        coalesce('Reason: ' || v_note, 'The society office removed this listing after a resident report.'),
        v_l.id);
    end if;

  else
    return jsonb_build_object('success', false, 'error', 'Unknown action');
  end if;

  return jsonb_build_object('success', true, 'report_id', p_report_id, 'action', p_action);
end;
$$;

grant execute on function public.resolve_marketplace_report(uuid, text, text) to authenticated;

-- 8.10 Module toggle — writes the existing module_flags row for this society.
create or replace function public.set_marketplace_enabled(p_enabled boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_society_id uuid := public.mkt_my_society_id();
begin
  if v_society_id is null or not public.is_society_admin(v_society_id) then
    return jsonb_build_object('success', false, 'error', 'Only society admins can change this');
  end if;

  update public.module_flags
     set enabled = p_enabled
   where society_id = v_society_id and module_key = 'marketplace';

  if not found then
    insert into public.module_flags (society_id, module_key, enabled)
    values (v_society_id, 'marketplace', p_enabled);
  end if;

  return jsonb_build_object('success', true, 'enabled', p_enabled);
end;
$$;

grant execute on function public.set_marketplace_enabled(boolean) to authenticated;

-- 8.11 Society policy (expiry window, auto-flag threshold).
create or replace function public.update_marketplace_settings(
  p_listing_expiry_days int,
  p_auto_flag_threshold int
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_society_id uuid := public.mkt_my_society_id();
begin
  if v_society_id is null or not public.is_society_admin(v_society_id) then
    return jsonb_build_object('success', false, 'error', 'Only society admins can change this');
  end if;
  if p_listing_expiry_days not between 7 and 180 then
    return jsonb_build_object('success', false, 'error', 'Expiry must be between 7 and 180 days');
  end if;
  if p_auto_flag_threshold not between 1 and 20 then
    return jsonb_build_object('success', false, 'error', 'Auto-hide threshold must be between 1 and 20');
  end if;

  insert into public.marketplace_settings (society_id, listing_expiry_days, auto_flag_threshold)
  values (v_society_id, p_listing_expiry_days, p_auto_flag_threshold)
  on conflict (society_id) do update
    set listing_expiry_days = excluded.listing_expiry_days,
        auto_flag_threshold = excluded.auto_flag_threshold;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.update_marketplace_settings(int, int) to authenticated;

-- 8.12 Auto-expiry. Idempotent; safe for any authenticated caller.
create or replace function public.expire_marketplace_listings()
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_count int;
begin
  update public.marketplace_listings
     set status = 'expired'
   where status = 'active'
     and expires_at is not null
     and expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.expire_marketplace_listings() to authenticated;

-- Schedule hourly if pg_cron is enabled. The feed already filters out
-- stale rows by expires_at, and the app calls the function on load, so
-- expiry stays correct even without pg_cron.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'expire-marketplace-listings',
      '15 * * * *',
      'select public.expire_marketplace_listings()'
    );
  end if;
exception when others then
  raise notice 'Could not schedule marketplace expiry job: %', sqlerrm;
end $$;

-- ------------------------------------------------------------
-- 9) ROW LEVEL SECURITY
-- Writes to listings, images and reports go through the RPCs above;
-- only deletes (owner/admin) and admin config use direct table access.
-- ------------------------------------------------------------
alter table public.marketplace_categories enable row level security;
alter table public.marketplace_listings enable row level security;
alter table public.marketplace_images enable row level security;
alter table public.marketplace_reports enable row level security;
alter table public.marketplace_blocked_residents enable row level security;
alter table public.marketplace_settings enable row level security;

-- 9.1 categories
drop policy if exists "marketplace_categories_select" on public.marketplace_categories;
create policy "marketplace_categories_select" on public.marketplace_categories
for select to authenticated
using (society_id is null or public.is_society_member(society_id) or public.is_master_admin());

drop policy if exists "marketplace_categories_admin_write" on public.marketplace_categories;
create policy "marketplace_categories_admin_write" on public.marketplace_categories
for all to authenticated
using (
  (society_id is not null and public.is_society_admin(society_id))
  or public.is_master_admin()
)
with check (
  (society_id is not null and public.is_society_admin(society_id))
  or public.is_master_admin()
);

-- 9.2 listings
drop policy if exists "marketplace_listings_select" on public.marketplace_listings;
create policy "marketplace_listings_select" on public.marketplace_listings
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or exists (
    select 1 from public.residents r
     where r.id = marketplace_listings.resident_id and r.user_id = auth.uid()
  )
  or (status = 'active' and public.is_society_member(society_id))
);

drop policy if exists "marketplace_listings_delete" on public.marketplace_listings;
create policy "marketplace_listings_delete" on public.marketplace_listings
for delete to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or exists (
    select 1 from public.residents r
     where r.id = marketplace_listings.resident_id and r.user_id = auth.uid()
  )
);

-- 9.3 images (visible whenever the parent listing is visible)
drop policy if exists "marketplace_images_select" on public.marketplace_images;
create policy "marketplace_images_select" on public.marketplace_images
for select to authenticated
using (
  exists (select 1 from public.marketplace_listings l where l.id = marketplace_images.listing_id)
);

-- 9.4 reports
drop policy if exists "marketplace_reports_select" on public.marketplace_reports;
create policy "marketplace_reports_select" on public.marketplace_reports
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or exists (
    select 1 from public.residents r
     where r.id = marketplace_reports.reported_by and r.user_id = auth.uid()
  )
);

-- 9.5 blocked residents
drop policy if exists "marketplace_blocked_select" on public.marketplace_blocked_residents;
create policy "marketplace_blocked_select" on public.marketplace_blocked_residents
for select to authenticated
using (
  public.is_society_admin(society_id)
  or public.is_master_admin()
  or exists (
    select 1 from public.residents r
     where r.id = marketplace_blocked_residents.resident_id and r.user_id = auth.uid()
  )
);

drop policy if exists "marketplace_blocked_admin_write" on public.marketplace_blocked_residents;
create policy "marketplace_blocked_admin_write" on public.marketplace_blocked_residents
for all to authenticated
using (public.is_society_admin(society_id) or public.is_master_admin())
with check (public.is_society_admin(society_id) or public.is_master_admin());

-- 9.6 settings
drop policy if exists "marketplace_settings_select" on public.marketplace_settings;
create policy "marketplace_settings_select" on public.marketplace_settings
for select to authenticated
using (public.is_society_member(society_id) or public.is_master_admin());

drop policy if exists "marketplace_settings_admin_write" on public.marketplace_settings;
create policy "marketplace_settings_admin_write" on public.marketplace_settings
for all to authenticated
using (public.is_society_admin(society_id) or public.is_master_admin())
with check (public.is_society_admin(society_id) or public.is_master_admin());

-- ------------------------------------------------------------
-- 10) STORAGE: marketplace-images
-- Each user uploads into their own "<auth.uid()>/" folder.
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('marketplace-images', 'marketplace-images', true)
on conflict (id) do nothing;

drop policy if exists "Marketplace images are publicly readable" on storage.objects;
create policy "Marketplace images are publicly readable"
on storage.objects for select to public
using (bucket_id = 'marketplace-images');

drop policy if exists "Users upload marketplace images to own folder" on storage.objects;
create policy "Users upload marketplace images to own folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'marketplace-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users delete own marketplace images" on storage.objects;
create policy "Users delete own marketplace images"
on storage.objects for delete to authenticated
using (
  bucket_id = 'marketplace-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
