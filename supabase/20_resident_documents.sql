-- ============================================================
-- 20) RESIDENT DOCUMENTS (tenant & owner KYC)
--
-- Proof of who lives in each flat:
--   identity   masked Aadhaar card (never the full 12 digits), PAN number
--   tenancy    rent agreement, police verification receipt, owner NOC
--   ownership  sale deed, conveyance deed, allotment / possession letter,
--              share certificate, Index II
--
-- Design (saqiit-resident-documents-implementation-plan.md):
--   * Files live in a PRIVATE bucket at server-chosen paths. A file can
--     only be read after open_resident_document() has written an access
--     log row for that caller, so every view is logged.
--   * The full Aadhaar number is never stored — only residents.aadhar_last4
--     (migration 01) and, optionally, the UIDAI "masked Aadhaar" image.
--   * PAN is stored encrypted (pgcrypto, key in Supabase Vault) and only the
--     person themselves or an admin (with a reason, rate limited, logged)
--     can see it in full.
--   * 12 months after a resident moves out their files and PAN are purged
--     by the purge-resident-documents Edge Function (nightly, pg_cron).
--
-- Also fixes two holes the documents rules would otherwise inherit:
--   P0-1  is_society_admin() lost its `status = 'active'` check in
--         migration 11, so a deactivated admin still passed every policy.
--   P0-2  whoever added a household member could rewrite ANY column of
--         that row — including user_id — and so become "that person".
--
-- Prerequisites: migrations 01, 03, 04, 07, 17_push_notifications (pg_net,
-- Vault). pg_cron is only needed for the nightly schedule (SETUP below).
-- Idempotent: safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1) P0-1: DEACTIVATED ADMINS ARE NOT ADMINS
--
-- Migration 11 re-created this without the status check. Also patched in
-- 11 itself, so re-running 11 later cannot bring the hole back.
-- ------------------------------------------------------------
create or replace function public.is_society_admin(p_society_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.society_admin_users a
     where a.id = auth.uid()
       and a.society_id = p_society_id
       and a.status = 'active'
  );
$$;

grant execute on function public.is_society_admin(uuid) to authenticated;

-- ------------------------------------------------------------
-- 2) P0-2: WHO A RESIDENT ROW BELONGS TO IS NOT THE CLIENT'S CHOICE
--
-- Migration 04 lets a primary resident add family members / tenants and
-- edit the rows they added — but never limited WHICH columns. So the
-- creator could set user_id to themselves (and read that person's
-- documents as "self"), or move the row into any flat of any society.
--
-- For API callers who are not an admin of the society:
--   INSERT  created_by is the caller, user_id is resolved by email only
--           (link_resident_on_insert runs next), society_id follows the flat
--   UPDATE  user_id, flat_id, society_id, created_by, resident_type and
--           is_primary keep their stored values
--
-- Recognised by the JWT role claim, like society_guards_before_write
-- (migration 17): the signup trigger runs without a JWT and may link.
-- Named so it sorts — and so fires — before trg_residents_link_on_insert.
-- ------------------------------------------------------------
create or replace function public.residents_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_api_role text :=
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  v_flat_society uuid;
begin
  if v_api_role is distinct from 'authenticated'
     and v_api_role is distinct from 'anon' then
    return new;
  end if;

  if tg_op = 'UPDATE' and not public.is_society_admin(old.society_id) then
    new.user_id       := old.user_id;
    new.flat_id       := old.flat_id;
    new.society_id    := old.society_id;
    new.created_by    := old.created_by;
    new.resident_type := old.resident_type;
    new.is_primary    := old.is_primary;
    return new;
  end if;

  select b.society_id into v_flat_society
    from public.flats f
    join public.blocks b on b.id = f.block_id
   where f.id = new.flat_id;

  if v_flat_society is null then
    raise exception 'Unknown flat';
  end if;

  if tg_op = 'INSERT' and not public.is_society_admin(v_flat_society) then
    new.created_by := auth.uid();
    new.user_id := null;
  end if;

  -- An admin may move a resident between flats, but only within a society
  -- they administer.
  if tg_op = 'UPDATE' and not public.is_society_admin(v_flat_society) then
    raise exception 'That flat belongs to a different society';
  end if;

  new.society_id := v_flat_society;
  return new;
end $$;

drop trigger if exists trg_residents_before_write on public.residents;
create trigger trg_residents_before_write
before insert or update on public.residents
for each row execute function public.residents_before_write();

-- The creator's rights over a household member now also end when the
-- creator no longer lives in that flat.
drop policy if exists "residents_update_household" on public.residents;
create policy "residents_update_household" on public.residents
for update to authenticated
using (
  public.is_society_admin(society_id)
  or (resident_type in ('family', 'tenant')
      and created_by = auth.uid()
      and public.lives_in_flat(flat_id))
)
with check (
  public.is_society_admin(society_id)
  or (resident_type in ('family', 'tenant')
      and created_by = auth.uid()
      and public.lives_in_flat(flat_id))
);

drop policy if exists "residents_delete_household" on public.residents;
create policy "residents_delete_household" on public.residents
for delete to authenticated
using (
  public.is_society_admin(society_id)
  or (resident_type in ('family', 'tenant')
      and created_by = auth.uid()
      and public.lives_in_flat(flat_id))
);

-- ------------------------------------------------------------
-- 3) EXTENSIONS AND HELPERS
-- ------------------------------------------------------------
create extension if not exists pgcrypto with schema extensions;

create or replace function public.is_owner_of_flat(p_flat_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.residents me
     where me.flat_id = p_flat_id
       and me.user_id = auth.uid()
       and me.resident_type = 'owner'
       and me.status = 'active'
  );
$$;

grant execute on function public.is_owner_of_flat(uuid) to authenticated;

create or replace function public.document_category(p_doc_type text)
returns text
language sql immutable as $$
  select case
    when p_doc_type = 'masked_aadhaar' then 'identity'
    when p_doc_type in ('rent_agreement', 'police_verification', 'owner_noc')
      then 'tenancy'
    when p_doc_type in ('sale_deed', 'conveyance_deed', 'allotment_letter',
                        'possession_letter', 'share_certificate', 'index_ii',
                        'other_ownership')
      then 'ownership'
  end;
$$;

-- Tenancy papers belong to tenants, title papers to owners; anyone can
-- have an ID document.
create or replace function public.document_type_fits(
  p_doc_type text,
  p_resident_type text
)
returns boolean
language sql immutable as $$
  select case public.document_category(p_doc_type)
    when 'identity'  then true
    when 'tenancy'   then p_resident_type = 'tenant'
    when 'ownership' then p_resident_type = 'owner'
    else false
  end;
$$;

create or replace function public.document_type_label(p_doc_type text)
returns text
language sql immutable as $$
  select case p_doc_type
    when 'masked_aadhaar'      then 'masked Aadhaar'
    when 'rent_agreement'      then 'rent agreement'
    when 'police_verification' then 'police verification'
    when 'owner_noc'           then 'owner NOC'
    when 'sale_deed'           then 'sale deed'
    when 'conveyance_deed'     then 'conveyance deed'
    when 'allotment_letter'    then 'allotment letter'
    when 'possession_letter'   then 'possession letter'
    when 'share_certificate'   then 'share certificate'
    when 'index_ii'            then 'Index II'
    else 'document'
  end;
$$;

-- ------------------------------------------------------------
-- Who may do what with a resident's documents.
--
--   p_action   'list'   see the row (type, status, dates, last-4 digits)
--              'open'   download the pages
--              'upload' add a document / set the PAN
--
--   active admin of the society      everything (keyed on the document's
--                                    society, so it still works after the
--                                    resident row is gone)
--   the person themselves            everything; list/open only once
--                                    they have moved out
--   head of household                family members they registered,
--                                    while they still live in the flat
--   owner of the tenant's flat       tenancy: everything
--                                    identity: list only (status + last-4;
--                                    the masked card still shows the
--                                    tenant's photo, birth date, address)
--   co-owner                         ownership: list + open
--
-- Master admins, guards and everyone else get nothing.
-- ------------------------------------------------------------
create or replace function public.document_permission(
  p_society_id uuid,
  p_resident_id uuid,
  p_category text,
  p_action text
)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  r record;
begin
  if v_uid is null then
    return false;
  end if;

  if p_society_id is not null and public.is_society_admin(p_society_id) then
    return true;
  end if;

  if p_resident_id is null then
    return false;
  end if;

  select res.user_id, res.flat_id, res.society_id, res.resident_type,
         res.status, res.created_by
    into r
    from public.residents res
   where res.id = p_resident_id;

  if not found then
    return false;
  end if;

  if p_society_id is not null and r.society_id is distinct from p_society_id then
    return false;
  end if;

  if r.user_id = v_uid then
    return p_action in ('list', 'open') or r.status = 'active';
  end if;

  if r.status is distinct from 'active' then
    return false;
  end if;

  if r.resident_type = 'family'
     and r.created_by = v_uid
     and public.lives_in_flat(r.flat_id) then
    return true;
  end if;

  if r.resident_type = 'tenant' and public.is_owner_of_flat(r.flat_id) then
    if p_category = 'tenancy' then
      return true;
    end if;
    return p_category = 'identity' and p_action = 'list';
  end if;

  if r.resident_type = 'owner'
     and p_category = 'ownership'
     and public.is_owner_of_flat(r.flat_id) then
    return p_action in ('list', 'open');
  end if;

  return false;
end $$;

grant execute on function public.document_permission(uuid, uuid, text, text) to authenticated;

-- How the caller relates to a resident, for the access log.
create or replace function public.document_actor_role(
  p_society_id uuid,
  p_resident_id uuid
)
returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.is_society_admin(p_society_id) then 'admin'
    when exists (select 1 from public.residents r
                  where r.id = p_resident_id and r.user_id = auth.uid())
      then 'self'
    when exists (select 1 from public.residents r
                  where r.id = p_resident_id
                    and r.resident_type = 'tenant'
                    and public.is_owner_of_flat(r.flat_id))
      then 'owner'
    else 'household'
  end;
$$;

-- ------------------------------------------------------------
-- 4) TABLES
-- ------------------------------------------------------------

-- One logical document (e.g. "rent agreement, 3 pages").
create table if not exists public.resident_documents (
  id               uuid primary key default gen_random_uuid(),
  -- restrict: deleting a society must not orphan files in the bucket.
  society_id       uuid not null references public.societies(id) on delete restrict,
  -- set null: the row must outlive a deleted flat / resident until purged.
  flat_id          uuid references public.flats(id) on delete set null,
  resident_id      uuid references public.residents(id) on delete set null,
  doc_type         text not null check (doc_type in (
                     'masked_aadhaar',
                     'rent_agreement', 'police_verification', 'owner_noc',
                     'sale_deed', 'conveyance_deed', 'allotment_letter',
                     'possession_letter', 'share_certificate', 'index_ii',
                     'other_ownership'
                   )),
  category         text generated always as (public.document_category(doc_type)) stored,
  valid_from       date,
  valid_until      date,
  reference_number text check (reference_number is null or length(reference_number) <= 80),
  note             text check (note is null or length(note) <= 500),
  status           text not null default 'uploading' check (status in (
                     'uploading', 'pending', 'verified', 'rejected', 'withdrawn',
                     'superseded', 'abandoned', 'purged'
                   )),
  review_note      text check (review_note is null or length(review_note) <= 500),
  uploaded_by      uuid references auth.users(id) on delete set null,
  reviewed_by      uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  submitted_at     timestamptz,
  reviewed_at      timestamptz,
  -- The move-out clock only (section 8). Rejected / withdrawn / abandoned
  -- files are purged on the next run regardless.
  retention_until  date,
  files_purged_at  timestamptz,
  constraint resident_documents_validity
    check (valid_from is null or valid_until is null or valid_until >= valid_from),
  constraint resident_documents_rent_dates
    check (doc_type <> 'rent_agreement'
           or status in ('purged', 'abandoned')
           or (valid_from is not null and valid_until is not null)),
  -- A document whose resident is gone must be on a deletion clock. If the
  -- retention trigger ever fails to set one, the delete errors instead of
  -- silently leaving files nobody will ever purge.
  constraint resident_documents_not_lost
    check (resident_id is not null
           or retention_until is not null
           or status in ('purged', 'abandoned', 'rejected', 'withdrawn'))
);

create index if not exists idx_resident_documents_resident
  on public.resident_documents(resident_id, doc_type, status);
create index if not exists idx_resident_documents_society_status
  on public.resident_documents(society_id, status);
create index if not exists idx_resident_documents_flat
  on public.resident_documents(flat_id);
create index if not exists idx_resident_documents_due
  on public.resident_documents(retention_until)
  where files_purged_at is null;

-- Pages. Either one PDF or up to 10 images per document.
create table if not exists public.resident_document_files (
  id           uuid primary key default gen_random_uuid(),
  document_id  uuid not null references public.resident_documents(id) on delete cascade,
  page_no      smallint not null check (page_no between 1 and 10),
  storage_path text not null unique,
  mime_type    text not null check (mime_type in ('image/jpeg', 'image/png', 'application/pdf')),
  size_bytes   int not null check (size_bytes between 1 and 10485760),
  created_at   timestamptz not null default now(),
  constraint uq_resident_document_page unique (document_id, page_no)
);

-- Encrypted PAN, one row per resident. Cascade: removing a member from
-- the register erases their PAN at once.
create table if not exists public.resident_identity (
  resident_id     uuid primary key references public.residents(id) on delete cascade,
  society_id      uuid not null references public.societies(id) on delete cascade,
  pan_enc         bytea not null,
  pan_last4       text not null check (pan_last4 ~ '^[0-9]{3}[A-Z]$'),
  key_version     smallint not null default 1,
  updated_by      uuid references auth.users(id) on delete set null,
  updated_at      timestamptz not null default now(),
  retention_until date
);

-- Every upload, view, PAN reveal, review and purge. No foreign keys: the
-- log must outlive the people and documents it describes (DPDP Rule 6
-- asks for at least a year; rows are pruned after two).
create table if not exists public.document_access_log (
  id           uuid primary key default gen_random_uuid(),
  society_id   uuid not null,
  actor_id     uuid,
  actor_role   text not null check (actor_role in ('self', 'household', 'owner', 'admin', 'system')),
  resident_id  uuid,
  document_id  uuid,
  action       text not null check (action in (
                 'upload', 'view', 'reveal_pan', 'set_pan', 'verify',
                 'reject', 'withdraw', 'purge'
               )),
  reason       text check (reason is null or length(reason) <= 300),
  accessed_at  timestamptz not null default now()
);

create index if not exists idx_document_access_log_actor
  on public.document_access_log(actor_id, document_id, accessed_at desc);
create index if not exists idx_document_access_log_society
  on public.document_access_log(society_id, accessed_at desc);
create index if not exists idx_document_access_log_resident
  on public.document_access_log(resident_id, accessed_at desc);

-- What the person agreed to, and when (DPDP notice + consent).
create table if not exists public.resident_document_consents (
  id             uuid primary key default gen_random_uuid(),
  resident_id    uuid references public.residents(id) on delete set null,
  society_id     uuid not null references public.societies(id) on delete cascade,
  user_id        uuid references auth.users(id) on delete set null,
  on_behalf      boolean not null default false,
  notice_version text not null check (length(notice_version) between 1 and 20),
  given_at       timestamptz not null default now(),
  withdrawn_at   timestamptz,
  constraint uq_resident_document_consent unique (resident_id, user_id, notice_version)
);

-- ------------------------------------------------------------
-- 5) ROW LEVEL SECURITY
--
-- Reads only. Every write goes through the RPCs below, so there are no
-- insert / update / delete policies and the API roles hold no write grants.
-- ------------------------------------------------------------
alter table public.resident_documents enable row level security;
alter table public.resident_document_files enable row level security;
alter table public.resident_identity enable row level security;
alter table public.document_access_log enable row level security;
alter table public.resident_document_consents enable row level security;

revoke all on table public.resident_documents from anon, authenticated;
revoke all on table public.resident_document_files from anon, authenticated;
revoke all on table public.resident_identity from anon, authenticated;
revoke all on table public.document_access_log from anon, authenticated;
revoke all on table public.resident_document_consents from anon, authenticated;

grant select on table public.resident_documents to authenticated;
grant select on table public.resident_document_files to authenticated;
grant select on table public.document_access_log to authenticated;
grant select on table public.resident_document_consents to authenticated;
-- resident_identity: no grant and no policy. Reached only through
-- get_document_subjects (last 4 characters) and reveal_resident_pan.

drop policy if exists "resident_documents_list" on public.resident_documents;
create policy "resident_documents_list" on public.resident_documents
for select to authenticated
using (public.document_permission(society_id, resident_id, category, 'list'));

drop policy if exists "resident_document_files_open" on public.resident_document_files;
create policy "resident_document_files_open" on public.resident_document_files
for select to authenticated
using (
  exists (
    select 1 from public.resident_documents d
     where d.id = document_id
       and public.document_permission(d.society_id, d.resident_id, d.category, 'open')
  )
);

drop policy if exists "document_access_log_read" on public.document_access_log;
create policy "document_access_log_read" on public.document_access_log
for select to authenticated
using (
  public.is_society_admin(society_id)
  or actor_id = auth.uid()
  or resident_id in (select r.id from public.residents r where r.user_id = auth.uid())
);

drop policy if exists "resident_document_consents_read" on public.resident_document_consents;
create policy "resident_document_consents_read" on public.resident_document_consents
for select to authenticated
using (public.is_society_admin(society_id) or user_id = auth.uid());

-- ------------------------------------------------------------
-- 6) PRIVATE BUCKET: resident-documents
--
-- Path: {society_id}/{flat_id}/{document_id}/{page}-{uuid}.{ext}, chosen
-- by create_resident_document, never by the client.
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'resident-documents', 'resident-documents', false, 10485760,
  array['image/jpeg', 'image/png', 'application/pdf']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Upload: only to a path this caller reserved in the last hour, for a
-- document still being uploaded.
create or replace function public.can_upload_document_file(p_name text)
returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (
    select 1
      from public.resident_document_files f
      join public.resident_documents d on d.id = f.document_id
     where f.storage_path = p_name
       and d.status = 'uploading'
       and d.uploaded_by = auth.uid()
       and d.created_at > now() - interval '1 hour'
  );
$$;

-- Read: only after open_resident_document() logged a view by this caller
-- in the last 10 minutes, and while they still may open it.
--
-- Signing a URL, copying or moving the object would hand out an unlogged
-- copy, so those storage operations are refused outright. Plain
-- authenticated downloads (what the app does) are not affected.
create or replace function public.can_read_document_file(p_name text)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  v_op text := coalesce(current_setting('storage.operation', true), '');
begin
  if auth.uid() is null then
    return false;
  end if;

  if v_op ~* 'object\.(sign|copy|move|upload_sign)' then
    return false;
  end if;

  -- The uploader, while still uploading: Postgres checks SELECT policies
  -- on INSERT ... RETURNING, and they hold these bytes already.
  if exists (
    select 1
      from public.resident_document_files f
      join public.resident_documents d on d.id = f.document_id
     where f.storage_path = p_name
       and d.status = 'uploading'
       and d.uploaded_by = auth.uid()
  ) then
    return true;
  end if;

  return exists (
    select 1
      from public.resident_document_files f
      join public.resident_documents d on d.id = f.document_id
     where f.storage_path = p_name
       and d.files_purged_at is null
       and exists (
         select 1 from public.document_access_log l
          where l.document_id = d.id
            and l.actor_id = auth.uid()
            and l.action = 'view'
            and l.accessed_at > now() - interval '10 minutes'
       )
       and public.document_permission(d.society_id, d.resident_id, d.category, 'open')
  );
end $$;

grant execute on function public.can_upload_document_file(text) to authenticated;
grant execute on function public.can_read_document_file(text) to authenticated;

drop policy if exists "resident documents upload to reserved path" on storage.objects;
create policy "resident documents upload to reserved path"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'resident-documents'
  and public.can_upload_document_file(name)
);

drop policy if exists "resident documents read after logged open" on storage.objects;
create policy "resident documents read after logged open"
on storage.objects for select to authenticated
using (
  bucket_id = 'resident-documents'
  and public.can_read_document_file(name)
);
-- No update or delete policy: files are replaced by new documents, and
-- deleted only by the purge Edge Function with the service role.

-- ------------------------------------------------------------
-- 7) RPCs
-- ------------------------------------------------------------

-- Vault key for PAN encryption. Only callable by the functions below
-- (they run as the owner); no API role may execute it.
create or replace function public.resident_pii_key(p_version smallint)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare
  v_key text;
begin
  select decrypted_secret into v_key
    from vault.decrypted_secrets
   where name = 'resident_pii_key_v' || p_version::text;
  return nullif(v_key, '');
exception when others then
  return null;
end $$;

revoke all on function public.resident_pii_key(smallint) from public, anon, authenticated;

-- 7a) Start an upload: reserve the pages and return where to put them.
create or replace function public.create_resident_document(
  p_resident_id uuid,
  p_doc_type text,
  p_mime_types text[],
  p_sizes int[],
  p_valid_from date default null,
  p_valid_until date default null,
  p_reference_number text default null,
  p_note text default null,
  p_consent_version text default null
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_res record;
  v_category text := public.document_category(p_doc_type);
  v_count int := coalesce(array_length(p_mime_types, 1), 0);
  v_doc_id uuid;
  v_paths text[] := '{}';
  v_path text;
  v_ext text;
  v_recent int;
  i int;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select r.id, r.society_id, r.flat_id, r.resident_type, r.status, r.user_id
    into v_res
    from public.residents r
   where r.id = p_resident_id;

  if not found then
    return jsonb_build_object('success', false, 'error', 'Resident not found');
  end if;

  if v_category is null then
    return jsonb_build_object('success', false, 'error', 'Unknown document type');
  end if;

  if not public.document_permission(v_res.society_id, v_res.id, v_category, 'upload') then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_res.status is distinct from 'active' then
    return jsonb_build_object('success', false, 'error', 'This resident has moved out');
  end if;

  if not public.document_type_fits(p_doc_type, v_res.resident_type) then
    return jsonb_build_object('success', false,
      'error', 'A ' || public.document_type_label(p_doc_type)
               || ' does not apply to a ' || v_res.resident_type);
  end if;

  if nullif(trim(coalesce(p_consent_version, '')), '') is null then
    return jsonb_build_object('success', false,
      'error', 'Please agree to the document notice before uploading');
  end if;

  if v_count < 1 or v_count <> coalesce(array_length(p_sizes, 1), 0) then
    return jsonb_build_object('success', false, 'error', 'Add at least one page');
  end if;

  if v_count > 10 or (v_count > 1 and 'application/pdf' = any(p_mime_types)) then
    return jsonb_build_object('success', false,
      'error', 'Upload either one PDF or up to 10 photos');
  end if;

  for i in 1..v_count loop
    if p_mime_types[i] is null
       or p_mime_types[i] not in ('image/jpeg', 'image/png', 'application/pdf') then
      return jsonb_build_object('success', false, 'error', 'Only JPG, PNG or PDF files');
    end if;
    if p_sizes[i] is null or p_sizes[i] < 1 or p_sizes[i] > 10485760 then
      return jsonb_build_object('success', false, 'error', 'Each file must be under 10 MB');
    end if;
  end loop;

  if p_doc_type = 'rent_agreement' and (p_valid_from is null or p_valid_until is null) then
    return jsonb_build_object('success', false,
      'error', 'Enter the agreement start and end dates');
  end if;

  if p_valid_from is not null and p_valid_until is not null
     and p_valid_until < p_valid_from then
    return jsonb_build_object('success', false, 'error', 'The end date is before the start date');
  end if;

  select count(*) into v_recent
    from public.resident_documents d
   where d.uploaded_by = v_uid
     and d.created_at > now() - interval '1 hour';

  if v_recent >= 30 then
    return jsonb_build_object('success', false,
      'error', 'Too many uploads in a short time. Try again later.');
  end if;

  insert into public.resident_document_consents (
    resident_id, society_id, user_id, on_behalf, notice_version
  ) values (
    v_res.id, v_res.society_id, v_uid,
    v_res.user_id is distinct from v_uid,
    left(trim(p_consent_version), 20)
  )
  on conflict (resident_id, user_id, notice_version) do nothing;

  insert into public.resident_documents (
    society_id, flat_id, resident_id, doc_type, valid_from, valid_until,
    reference_number, note, status, uploaded_by
  ) values (
    v_res.society_id, v_res.flat_id, v_res.id, p_doc_type, p_valid_from, p_valid_until,
    left(nullif(trim(coalesce(p_reference_number, '')), ''), 80),
    left(nullif(trim(coalesce(p_note, '')), ''), 500),
    'uploading', v_uid
  )
  returning id into v_doc_id;

  for i in 1..v_count loop
    v_ext := case p_mime_types[i]
               when 'image/jpeg' then 'jpg'
               when 'image/png'  then 'png'
               else 'pdf'
             end;
    v_path := v_res.society_id::text || '/' || v_res.flat_id::text || '/'
              || v_doc_id::text || '/' || i::text || '-'
              || gen_random_uuid()::text || '.' || v_ext;

    insert into public.resident_document_files (
      document_id, page_no, storage_path, mime_type, size_bytes
    ) values (
      v_doc_id, i, v_path, p_mime_types[i], p_sizes[i]
    );
    v_paths := v_paths || v_path;
  end loop;

  return jsonb_build_object(
    'success', true,
    'document_id', v_doc_id,
    'paths', to_jsonb(v_paths)
  );
end $$;

-- 7b) Finish an upload: every page must really be in the bucket, with the
-- type that was declared. Then it goes to the admins for review.
create or replace function public.submit_resident_document(p_document_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_doc record;
  v_subject_user uuid;
  v_missing int;
  v_mismatch int;
  v_label text;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_doc
    from public.resident_documents d
   where d.id = p_document_id
   for update;

  if not found or v_doc.uploaded_by is distinct from v_uid then
    return jsonb_build_object('success', false, 'error', 'Document not found');
  end if;

  if v_doc.status <> 'uploading' then
    return jsonb_build_object('success', false, 'error', 'This document was already submitted');
  end if;

  select count(*) into v_missing
    from public.resident_document_files f
   where f.document_id = v_doc.id
     and not exists (
       select 1 from storage.objects o
        where o.bucket_id = 'resident-documents'
          and o.name = f.storage_path
     );

  if v_missing > 0 then
    return jsonb_build_object('success', false,
      'error', 'Some pages did not finish uploading. Try again.');
  end if;

  select count(*) into v_mismatch
    from public.resident_document_files f
    join storage.objects o
      on o.bucket_id = 'resident-documents' and o.name = f.storage_path
   where f.document_id = v_doc.id
     and coalesce(o.metadata ->> 'mimetype', '') <> f.mime_type;

  if v_mismatch > 0 then
    return jsonb_build_object('success', false,
      'error', 'A page is not the file type that was declared');
  end if;

  update public.resident_documents
     set status = 'pending',
         submitted_at = now()
   where id = v_doc.id;

  insert into public.document_access_log (
    society_id, actor_id, actor_role, resident_id, document_id, action
  ) values (
    v_doc.society_id, v_uid,
    public.document_actor_role(v_doc.society_id, v_doc.resident_id),
    v_doc.resident_id, v_doc.id, 'upload'
  );

  v_label := public.document_type_label(v_doc.doc_type);
  select r.user_id into v_subject_user
    from public.residents r where r.id = v_doc.resident_id;

  -- Bodies carry no personal data: they are pushed through FCM and the
  -- master admin can read every notification.
  begin
    insert into public.notifications (
      society_id, user_id, target_role, title, body, type,
      entity_type, entity_id, route
    ) values (
      v_doc.society_id, null, 'society_admin',
      'Document to verify',
      'A ' || v_label || ' was uploaded and is waiting for review.',
      'document_submitted', 'resident_document', v_doc.id::text, '/documents'
    );

    if v_subject_user is not null and v_subject_user <> v_uid then
      insert into public.notifications (
        society_id, user_id, target_role, title, body, type,
        entity_type, entity_id, route
      ) values (
        v_doc.society_id, v_subject_user, 'resident',
        'Document added for you',
        'A ' || v_label || ' was uploaded on your behalf.',
        'document_submitted', 'resident_document', v_doc.id::text, '/documents'
      );
    end if;
  exception when others then
    raise warning 'submit_resident_document notify: %', sqlerrm;
  end;

  return jsonb_build_object('success', true, 'document_id', v_doc.id);
end $$;

-- 7c) Abandon an upload that failed half-way.
create or replace function public.cancel_resident_document(p_document_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  update public.resident_documents
     set status = 'abandoned'
   where id = p_document_id
     and uploaded_by = v_uid
     and status = 'uploading';

  return jsonb_build_object('success', true);
end $$;

-- 7d) Take back a document uploaded by mistake, before it is reviewed.
create or replace function public.withdraw_resident_document(p_document_id uuid)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_doc record;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_doc
    from public.resident_documents d
   where d.id = p_document_id
   for update;

  if not found
     or not (v_doc.uploaded_by = v_uid
             or public.document_permission(v_doc.society_id, v_doc.resident_id,
                                           v_doc.category, 'upload')) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_doc.status <> 'pending' then
    return jsonb_build_object('success', false,
      'error', 'Only a document waiting for review can be withdrawn');
  end if;

  update public.resident_documents set status = 'withdrawn' where id = v_doc.id;

  insert into public.document_access_log (
    society_id, actor_id, actor_role, resident_id, document_id, action
  ) values (
    v_doc.society_id, v_uid,
    public.document_actor_role(v_doc.society_id, v_doc.resident_id),
    v_doc.resident_id, v_doc.id, 'withdraw'
  );

  return jsonb_build_object('success', true);
end $$;

-- 7e) Open a document. Logs the view; the log row is what lets the
-- storage policy serve the pages for the next 10 minutes.
create or replace function public.open_resident_document(
  p_document_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_doc record;
  v_recent int;
  v_pages jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_doc from public.resident_documents d where d.id = p_document_id;

  if not found
     or not public.document_permission(v_doc.society_id, v_doc.resident_id,
                                       v_doc.category, 'open') then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_doc.files_purged_at is not null or v_doc.status in ('purged', 'abandoned', 'uploading') then
    return jsonb_build_object('success', false,
      'error', 'The files for this document are no longer stored');
  end if;

  -- Paging through the society's files one by one is harvesting, not
  -- reviewing.
  select count(*) into v_recent
    from public.document_access_log l
   where l.actor_id = v_uid
     and l.action = 'view'
     and l.accessed_at > now() - interval '10 minutes';

  if v_recent >= 60 then
    return jsonb_build_object('success', false,
      'error', 'Too many documents opened in a short time. Try again later.');
  end if;

  insert into public.document_access_log (
    society_id, actor_id, actor_role, resident_id, document_id, action, reason
  ) values (
    v_doc.society_id, v_uid,
    public.document_actor_role(v_doc.society_id, v_doc.resident_id),
    v_doc.resident_id, v_doc.id, 'view',
    left(nullif(trim(coalesce(p_reason, '')), ''), 300)
  );

  select coalesce(jsonb_agg(jsonb_build_object(
           'path', f.storage_path,
           'mime_type', f.mime_type,
           'page_no', f.page_no
         ) order by f.page_no), '[]'::jsonb)
    into v_pages
    from public.resident_document_files f
   where f.document_id = v_doc.id;

  return jsonb_build_object('success', true, 'pages', v_pages);
end $$;

-- 7f) Admin decision.
create or replace function public.review_resident_document(
  p_document_id uuid,
  p_decision text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_doc record;
  v_note text := left(nullif(trim(coalesce(p_note, '')), ''), 500);
  v_subject_user uuid;
  v_label text;
  v_title text;
  v_body text;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select * into v_doc
    from public.resident_documents d
   where d.id = p_document_id
   for update;

  if not found or not public.is_society_admin(v_doc.society_id) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if p_decision not in ('verified', 'rejected') then
    return jsonb_build_object('success', false, 'error', 'Unknown decision');
  end if;

  if v_doc.status <> 'pending' then
    return jsonb_build_object('success', false,
      'error', 'Only documents waiting for review can be verified or rejected');
  end if;

  if p_decision = 'rejected' and coalesce(length(v_note), 0) < 3 then
    return jsonb_build_object('success', false, 'error', 'Say why the document is rejected');
  end if;

  if p_decision = 'verified' and v_doc.doc_type <> 'other_ownership' then
    update public.resident_documents
       set status = 'superseded'
     where resident_id = v_doc.resident_id
       and doc_type = v_doc.doc_type
       and status = 'verified'
       and id <> v_doc.id;
  end if;

  update public.resident_documents
     set status = p_decision,
         review_note = v_note,
         reviewed_by = v_uid,
         reviewed_at = now()
   where id = v_doc.id;

  insert into public.document_access_log (
    society_id, actor_id, actor_role, resident_id, document_id, action, reason
  ) values (
    v_doc.society_id, v_uid, 'admin', v_doc.resident_id, v_doc.id,
    case when p_decision = 'verified' then 'verify' else 'reject' end,
    left(v_note, 300)
  );

  v_label := public.document_type_label(v_doc.doc_type);
  if p_decision = 'verified' then
    v_title := 'Document verified';
    v_body := 'Your ' || v_label || ' was verified by the society office.';
  else
    v_title := 'Document needs attention';
    v_body := 'Your ' || v_label || ' was not accepted. Open Documents to see why and upload it again.';
  end if;

  select r.user_id into v_subject_user
    from public.residents r where r.id = v_doc.resident_id;

  begin
    insert into public.notifications (
      society_id, user_id, target_role, title, body, type,
      entity_type, entity_id, route
    )
    select v_doc.society_id, u.uid, 'resident', v_title, v_body,
           case when p_decision = 'verified' then 'document_verified' else 'document_rejected' end,
           'resident_document', v_doc.id::text, '/documents'
      from (select distinct x.uid
              from unnest(array[v_doc.uploaded_by, v_subject_user]) as x(uid)
             where x.uid is not null and x.uid <> v_uid) u;
  exception when others then
    raise warning 'review_resident_document notify: %', sqlerrm;
  end;

  return jsonb_build_object('success', true, 'status', p_decision);
end $$;

-- 7g) Save a PAN (encrypted). Never echoes the PAN, never builds SQL
-- from it: statement logs must not be able to capture it.
create or replace function public.set_resident_pan(
  p_resident_id uuid,
  p_pan text
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_res record;
  v_pan text := upper(regexp_replace(coalesce(p_pan, ''), '\s', '', 'g'));
  v_key text;
  v_version smallint := 1;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  if v_pan !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' then
    return jsonb_build_object('success', false, 'error', 'Enter a valid PAN, like ABCDE1234F');
  end if;

  select r.id, r.society_id, r.status into v_res
    from public.residents r where r.id = p_resident_id;

  if not found
     or not public.document_permission(v_res.society_id, v_res.id, 'identity', 'upload') then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if v_res.status is distinct from 'active' then
    return jsonb_build_object('success', false, 'error', 'This resident has moved out');
  end if;

  -- pgp_sym_encrypt is STRICT: with no key it would quietly store NULL.
  v_key := public.resident_pii_key(v_version);
  if v_key is null then
    return jsonb_build_object('success', false,
      'error', 'PAN storage is not set up yet. Ask the society office.');
  end if;

  insert into public.resident_identity (
    resident_id, society_id, pan_enc, pan_last4, key_version, updated_by, updated_at
  ) values (
    v_res.id, v_res.society_id,
    extensions.pgp_sym_encrypt(v_pan, v_key, 'cipher-algo=aes256'),
    right(v_pan, 4), v_version, v_uid, now()
  )
  on conflict (resident_id) do update
    set pan_enc = excluded.pan_enc,
        pan_last4 = excluded.pan_last4,
        key_version = excluded.key_version,
        updated_by = excluded.updated_by,
        updated_at = now(),
        retention_until = null;

  insert into public.document_access_log (
    society_id, actor_id, actor_role, resident_id, action
  ) values (
    v_res.society_id, v_uid,
    public.document_actor_role(v_res.society_id, v_res.id),
    v_res.id, 'set_pan'
  );

  return jsonb_build_object('success', true, 'pan_last4', right(v_pan, 4));
end $$;

-- 7h) Show a full PAN: the person themselves, or an admin who says why.
create or replace function public.reveal_resident_pan(
  p_resident_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_res record;
  v_is_self boolean;
  v_is_admin boolean;
  v_reason text := left(nullif(trim(coalesce(p_reason, '')), ''), 300);
  v_row record;
  v_key text;
  v_pan text;
  v_recent int;
  v_today int;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  select r.id, r.society_id, r.user_id into v_res
    from public.residents r where r.id = p_resident_id;

  if not found then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  v_is_self := v_res.user_id = v_uid;
  v_is_admin := public.is_society_admin(v_res.society_id);

  if not (coalesce(v_is_self, false) or v_is_admin) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  if not coalesce(v_is_self, false) and coalesce(length(v_reason), 0) < 5 then
    return jsonb_build_object('success', false, 'error', 'Say why you need the full PAN');
  end if;

  select count(*) filter (where l.accessed_at > now() - interval '10 minutes'),
         count(*)
    into v_recent, v_today
    from public.document_access_log l
   where l.actor_id = v_uid
     and l.action = 'reveal_pan'
     and l.accessed_at > now() - interval '24 hours';

  if v_recent >= 10 or v_today >= 50 then
    return jsonb_build_object('success', false,
      'error', 'Too many PANs viewed. Try again later.');
  end if;

  select i.pan_enc, i.key_version into v_row
    from public.resident_identity i
   where i.resident_id = v_res.id;

  if not found then
    return jsonb_build_object('success', false, 'error', 'No PAN on file');
  end if;

  v_key := public.resident_pii_key(v_row.key_version);
  if v_key is null then
    return jsonb_build_object('success', false, 'error', 'PAN storage is not set up');
  end if;

  begin
    v_pan := extensions.pgp_sym_decrypt(v_row.pan_enc, v_key);
  exception when others then
    return jsonb_build_object('success', false, 'error', 'Could not read the stored PAN');
  end;

  insert into public.document_access_log (
    society_id, actor_id, actor_role, resident_id, action, reason
  ) values (
    v_res.society_id, v_uid,
    case when v_is_self then 'self' else 'admin' end,
    v_res.id, 'reveal_pan', v_reason
  );

  return jsonb_build_object('success', true, 'pan', v_pan);
end $$;

-- 7i) The people whose documents the caller may see, with what they may
-- do. p_flat_id: one flat (admin, from the directory). null: the caller's
-- own flats.
create or replace function public.get_document_subjects(p_flat_id uuid default null)
returns table (
  resident_id          uuid,
  society_id           uuid,
  flat_id              uuid,
  flat_label           text,
  full_name            text,
  resident_type        text,
  relation             text,
  status               text,
  is_self              boolean,
  aadhar_last4         text,
  has_pan              boolean,
  pan_last4            text,
  can_upload_identity  boolean,
  can_open_identity    boolean,
  can_upload_tenancy   boolean,
  can_open_tenancy     boolean,
  can_upload_ownership boolean,
  can_open_ownership   boolean,
  can_reveal_pan       boolean
)
language sql
stable
security definer set search_path = public
as $$
  with candidates as (
    select r.*
      from public.residents r
     where auth.uid() is not null
       and (
         (p_flat_id is not null and r.flat_id = p_flat_id)
         or (p_flat_id is null and (
               r.user_id = auth.uid()
               or r.flat_id in (
                 select me.flat_id from public.residents me
                  where me.user_id = auth.uid() and me.status = 'active'
               )))
       )
  )
  select
    c.id,
    c.society_id,
    c.flat_id,
    coalesce(b.name || '-', '') || coalesce(f.flat_number, ''),
    c.full_name,
    c.resident_type,
    c.relation,
    c.status,
    coalesce(c.user_id = auth.uid(), false),
    c.aadhar_last4,
    ri.resident_id is not null,
    ri.pan_last4,
    c.status = 'active' and public.document_permission(c.society_id, c.id, 'identity', 'upload'),
    public.document_permission(c.society_id, c.id, 'identity', 'open'),
    c.status = 'active'
      and public.document_type_fits('rent_agreement', c.resident_type)
      and public.document_permission(c.society_id, c.id, 'tenancy', 'upload'),
    public.document_permission(c.society_id, c.id, 'tenancy', 'open'),
    c.status = 'active'
      and public.document_type_fits('sale_deed', c.resident_type)
      and public.document_permission(c.society_id, c.id, 'ownership', 'upload'),
    public.document_permission(c.society_id, c.id, 'ownership', 'open'),
    coalesce(c.user_id = auth.uid(), false) or public.is_society_admin(c.society_id)
  from candidates c
  left join public.flats f on f.id = c.flat_id
  left join public.blocks b on b.id = f.block_id
  left join public.resident_identity ri on ri.resident_id = c.id
  where (c.status = 'active'
         or c.user_id = auth.uid()
         or public.is_society_admin(c.society_id))
    and (public.document_permission(c.society_id, c.id, 'identity', 'list')
         or public.document_permission(c.society_id, c.id, 'tenancy', 'list')
         or public.document_permission(c.society_id, c.id, 'ownership', 'list'))
  order by 4, (c.user_id = auth.uid()) desc nulls last, c.is_primary desc, c.full_name;
$$;

-- 7j) The office's queue.
create or replace function public.admin_documents_overview(p_society_id uuid)
returns jsonb
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_to_verify jsonb;
  v_expiring jsonb;
  v_expired jsonb;
  v_missing_rent jsonb;
  v_missing_owner jsonb;
begin
  if auth.uid() is null or not public.is_society_admin(p_society_id) then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  select coalesce(jsonb_agg(x order by x.submitted_at), '[]'::jsonb) into v_to_verify
    from (
      select d.id as document_id, d.doc_type, d.submitted_at, d.resident_id,
             d.flat_id, r.full_name, r.resident_type,
             coalesce(b.name || '-', '') || coalesce(f.flat_number, '') as flat_label
        from public.resident_documents d
        left join public.residents r on r.id = d.resident_id
        left join public.flats f on f.id = d.flat_id
        left join public.blocks b on b.id = f.block_id
       where d.society_id = p_society_id and d.status = 'pending'
       order by d.submitted_at
       limit 200
    ) x;

  select coalesce(jsonb_agg(x order by x.valid_until), '[]'::jsonb) into v_expiring
    from (
      select d.id as document_id, d.doc_type, d.valid_until, d.resident_id,
             d.flat_id, r.full_name,
             coalesce(b.name || '-', '') || coalesce(f.flat_number, '') as flat_label,
             exists (select 1 from public.resident_documents p
                      where p.resident_id = d.resident_id
                        and p.doc_type = 'rent_agreement'
                        and p.status = 'pending') as renewal_pending
        from public.resident_documents d
        join public.residents r on r.id = d.resident_id and r.status = 'active'
        left join public.flats f on f.id = d.flat_id
        left join public.blocks b on b.id = f.block_id
       where d.society_id = p_society_id
         and d.doc_type = 'rent_agreement'
         and d.status = 'verified'
         and d.valid_until between current_date and current_date + 30
       order by d.valid_until
       limit 200
    ) x;

  select coalesce(jsonb_agg(x order by x.valid_until), '[]'::jsonb) into v_expired
    from (
      select d.id as document_id, d.doc_type, d.valid_until, d.resident_id,
             d.flat_id, r.full_name,
             coalesce(b.name || '-', '') || coalesce(f.flat_number, '') as flat_label,
             exists (select 1 from public.resident_documents p
                      where p.resident_id = d.resident_id
                        and p.doc_type = 'rent_agreement'
                        and p.status = 'pending') as renewal_pending
        from public.resident_documents d
        join public.residents r on r.id = d.resident_id and r.status = 'active'
        left join public.flats f on f.id = d.flat_id
        left join public.blocks b on b.id = f.block_id
       where d.society_id = p_society_id
         and d.doc_type = 'rent_agreement'
         and d.status = 'verified'
         and d.valid_until < current_date
       order by d.valid_until
       limit 200
    ) x;

  -- Flats with an active tenant but no rent agreement verified or waiting.
  select coalesce(jsonb_agg(x order by x.flat_label), '[]'::jsonb) into v_missing_rent
    from (
      select distinct on (t.flat_id)
             t.flat_id, t.id as resident_id, t.full_name,
             coalesce(b.name || '-', '') || coalesce(f.flat_number, '') as flat_label
        from public.residents t
        left join public.flats f on f.id = t.flat_id
        left join public.blocks b on b.id = f.block_id
       where t.society_id = p_society_id
         and t.status = 'active'
         and t.resident_type = 'tenant'
         and not exists (
           select 1 from public.resident_documents d
             join public.residents dr on dr.id = d.resident_id
            where dr.flat_id = t.flat_id
              and dr.status = 'active'
              and d.doc_type = 'rent_agreement'
              and d.status in ('pending', 'verified')
         )
       order by t.flat_id, t.is_primary desc, t.created_at
       limit 300
    ) x;

  -- Flats with an active owner but no ownership proof verified or waiting.
  select coalesce(jsonb_agg(x order by x.flat_label), '[]'::jsonb) into v_missing_owner
    from (
      select distinct on (o.flat_id)
             o.flat_id, o.id as resident_id, o.full_name,
             coalesce(b.name || '-', '') || coalesce(f.flat_number, '') as flat_label
        from public.residents o
        left join public.flats f on f.id = o.flat_id
        left join public.blocks b on b.id = f.block_id
       where o.society_id = p_society_id
         and o.status = 'active'
         and o.resident_type = 'owner'
         and not exists (
           select 1 from public.resident_documents d
             join public.residents dr on dr.id = d.resident_id
            where dr.flat_id = o.flat_id
              and dr.status = 'active'
              and d.category = 'ownership'
              and d.status in ('pending', 'verified')
         )
       order by o.flat_id, o.is_primary desc, o.created_at
       limit 300
    ) x;

  return jsonb_build_object(
    'success', true,
    'to_verify', v_to_verify,
    'expiring', v_expiring,
    'expired', v_expired,
    'missing_rent_agreement', v_missing_rent,
    'missing_ownership', v_missing_owner
  );
end $$;

-- 7k) Home-screen badge counts.
--   to_verify  admin: documents waiting for review
--   attention  resident: my tenancy has no current rent agreement (or it
--              ends within 30 days), or something I uploaded was rejected
--              in the last 14 days and not uploaded again
create or replace function public.document_action_counts(p_society_id uuid)
returns jsonb
language plpgsql
stable
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_to_verify int := 0;
  v_attention int := 0;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Not authenticated');
  end if;

  if p_society_id is not null and public.is_society_admin(p_society_id) then
    select count(*) into v_to_verify
      from public.resident_documents d
     where d.society_id = p_society_id and d.status = 'pending';
  end if;

  select count(*) into v_attention
    from public.residents me
   where me.user_id = v_uid
     and me.status = 'active'
     and me.resident_type = 'tenant'
     and not exists (
       select 1 from public.resident_documents d
        where d.resident_id = me.id
          and d.doc_type = 'rent_agreement'
          and (d.status = 'pending'
               or (d.status = 'verified' and d.valid_until > current_date + 30))
     );

  v_attention := v_attention + (
    select count(*)
      from public.resident_documents d
     where d.uploaded_by = v_uid
       and d.status = 'rejected'
       and d.reviewed_at > now() - interval '14 days'
       and not exists (
         select 1 from public.resident_documents n
          where n.resident_id = d.resident_id
            and n.doc_type = d.doc_type
            and n.created_at > d.created_at
            and n.status in ('pending', 'verified')
       )
  );

  return jsonb_build_object(
    'success', true,
    'to_verify', v_to_verify,
    'attention', v_attention
  );
end $$;

grant execute on function public.create_resident_document(uuid, text, text[], int[], date, date, text, text, text) to authenticated;
grant execute on function public.submit_resident_document(uuid) to authenticated;
grant execute on function public.cancel_resident_document(uuid) to authenticated;
grant execute on function public.withdraw_resident_document(uuid) to authenticated;
grant execute on function public.open_resident_document(uuid, text) to authenticated;
grant execute on function public.review_resident_document(uuid, text, text) to authenticated;
grant execute on function public.set_resident_pan(uuid, text) to authenticated;
grant execute on function public.reveal_resident_pan(uuid, text) to authenticated;
grant execute on function public.get_document_subjects(uuid) to authenticated;
grant execute on function public.admin_documents_overview(uuid) to authenticated;
grant execute on function public.document_action_counts(uuid) to authenticated;

revoke execute on function public.create_resident_document(uuid, text, text[], int[], date, date, text, text, text) from anon;
revoke execute on function public.open_resident_document(uuid, text) from anon;
revoke execute on function public.reveal_resident_pan(uuid, text) from anon;
revoke execute on function public.set_resident_pan(uuid, text) from anon;

-- ------------------------------------------------------------
-- 8) RETENTION CLOCK
--
-- Moving out starts a 12-month clock on the resident's documents and PAN;
-- moving back in stops it. Deleting the resident row (primary residents
-- hard-delete household members) starts it for the documents — the PAN
-- row cascades away immediately.
--
-- security definer: the caller (e.g. a primary resident removing a member)
-- has no write access to resident_documents, and an invoker-rights trigger
-- would update nothing without raising an error.
-- ------------------------------------------------------------
create or replace function public.residents_document_retention()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_until date := (current_date + interval '12 months')::date;
begin
  if tg_op = 'DELETE' then
    update public.resident_documents
       set retention_until = coalesce(retention_until, v_until)
     where resident_id = old.id
       and status <> 'purged';
    return old;
  end if;

  if old.status is not distinct from new.status then
    return new;
  end if;

  if new.status = 'moved_out' then
    update public.resident_documents
       set retention_until = coalesce(retention_until, v_until)
     where resident_id = new.id
       and status <> 'purged';
    update public.resident_identity
       set retention_until = coalesce(retention_until, v_until)
     where resident_id = new.id;
  elsif new.status = 'active' then
    update public.resident_documents
       set retention_until = null
     where resident_id = new.id
       and files_purged_at is null;
    update public.resident_identity
       set retention_until = null
     where resident_id = new.id;
  end if;

  return new;
end $$;

drop trigger if exists trg_residents_document_retention on public.residents;
create trigger trg_residents_document_retention
after update of status on public.residents
for each row execute function public.residents_document_retention();

drop trigger if exists trg_residents_document_retention_delete on public.residents;
create trigger trg_residents_document_retention_delete
before delete on public.residents
for each row execute function public.residents_document_retention();

-- ------------------------------------------------------------
-- 9) NOTIFICATION TYPES
--
-- Every type any earlier migration allows, plus the document ones. The
-- lists in 12_marketplace and 19_facilities each miss the other's types;
-- this one is the union, so running 20 last repairs that.
-- ------------------------------------------------------------
do $$
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
      'parking_bay_request', 'parking_bay_approved', 'parking_bay_rejected',
      'marketplace_report_submitted', 'marketplace_listing_reported',
      'marketplace_listing_removed', 'marketplace_seller_warned', 'marketplace_seller_blocked',
      'facility_status_changed',
      'document_submitted', 'document_verified', 'document_rejected', 'document_expiring'
    ));
exception when others then
  raise notice 'Could not update notifications type check constraint: %', sqlerrm;
end $$;

-- ------------------------------------------------------------
-- 10) PURGE (service role only — called by the Edge Function)
-- ------------------------------------------------------------

-- Documents whose files should go now, with their paths.
create or replace function public.documents_due_for_purge(p_limit int default 200)
returns table (document_id uuid, storage_path text)
language sql
stable
security definer set search_path = public
as $$
  with due as (
    select d.id
      from public.resident_documents d
     where d.files_purged_at is null
       and (
         (d.retention_until is not null and d.retention_until < current_date)
         or d.status in ('rejected', 'withdrawn', 'abandoned')
         or (d.status = 'uploading' and d.created_at < now() - interval '24 hours')
       )
     order by d.created_at
     limit greatest(1, least(coalesce(p_limit, 200), 1000))
  )
  select due.id, f.storage_path
    from due
    left join public.resident_document_files f on f.document_id = due.id;
$$;

-- Marks documents purged once their files are really gone from the
-- bucket (Storage's remove() silently skips paths it cannot delete).
create or replace function public.mark_documents_purged(p_ids uuid[])
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_id uuid;
  v_doc record;
  v_expired boolean;
  v_done int := 0;
  v_skipped int := 0;
begin
  foreach v_id in array coalesce(p_ids, '{}'::uuid[]) loop
    select * into v_doc
      from public.resident_documents d
     where d.id = v_id
     for update;

    continue when not found or v_doc.files_purged_at is not null;

    if exists (
      select 1
        from public.resident_document_files f
        join storage.objects o
          on o.bucket_id = 'resident-documents' and o.name = f.storage_path
       where f.document_id = v_id
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_expired := v_doc.retention_until is not null and v_doc.retention_until < current_date;

    delete from public.resident_document_files where document_id = v_id;

    -- What stays after a retention purge is the minimal tenancy record:
    -- type, dates, reference number and who reviewed it.
    update public.resident_documents
       set files_purged_at = now(),
           status = case
                      when v_expired then 'purged'
                      when status = 'uploading' then 'abandoned'
                      else status
                    end,
           note = case when v_expired then null else note end,
           review_note = case when v_expired then null else review_note end
     where id = v_id;

    insert into public.document_access_log (
      society_id, actor_id, actor_role, resident_id, document_id, action
    ) values (
      v_doc.society_id, null, 'system', v_doc.resident_id, v_id, 'purge'
    );

    v_done := v_done + 1;
  end loop;

  return jsonb_build_object('success', true, 'purged', v_done, 'skipped', v_skipped);
end $$;

create or replace function public.purge_expired_identities()
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_count int;
begin
  with gone as (
    delete from public.resident_identity
     where retention_until is not null and retention_until < current_date
    returning resident_id, society_id
  ),
  logged as (
    insert into public.document_access_log (
      society_id, actor_id, actor_role, resident_id, action, reason
    )
    select society_id, null, 'system', resident_id, 'purge', 'PAN deleted'
      from gone
    returning 1
  )
  select count(*) into v_count from logged;
  return v_count;
end $$;

create or replace function public.prune_document_access_log()
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_count int;
begin
  delete from public.document_access_log
   where accessed_at < now() - interval '2 years';
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- Files in the bucket that no document points at (an upload that never
-- reserved its path cannot happen, but a crash between remove() and
-- mark_documents_purged, or a manual cleanup, can leave strays).
create or replace function public.document_orphan_objects(p_limit int default 500)
returns table (storage_path text)
language sql
stable
security definer set search_path = public
as $$
  select o.name
    from storage.objects o
   where o.bucket_id = 'resident-documents'
     and o.created_at < now() - interval '24 hours'
     and not exists (
       select 1 from public.resident_document_files f where f.storage_path = o.name
     )
   limit greatest(1, least(coalesce(p_limit, 500), 1000));
$$;

-- Postgres grants EXECUTE to PUBLIC by default and Supabase to anon and
-- authenticated as well; all three must be revoked.
revoke all on function public.documents_due_for_purge(int) from public, anon, authenticated;
revoke all on function public.mark_documents_purged(uuid[]) from public, anon, authenticated;
revoke all on function public.purge_expired_identities() from public, anon, authenticated;
revoke all on function public.prune_document_access_log() from public, anon, authenticated;
revoke all on function public.document_orphan_objects(int) from public, anon, authenticated;
grant execute on function public.documents_due_for_purge(int) to service_role;
grant execute on function public.mark_documents_purged(uuid[]) to service_role;
grant execute on function public.purge_expired_identities() to service_role;
grant execute on function public.prune_document_access_log() to service_role;
grant execute on function public.document_orphan_objects(int) to service_role;

-- Nightly trigger for the Edge Function, scheduled with pg_cron (SETUP).
create or replace function public.invoke_document_purge()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'documents_purge_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'documents_purge_secret';

  if v_url is null or v_secret is null then
    raise warning 'invoke_document_purge: documents_purge_url / documents_purge_secret not set';
    return;
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', v_secret
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end $$;

revoke all on function public.invoke_document_purge() from public, anon, authenticated;

-- ------------------------------------------------------------
-- SETUP (run once, by hand, with your own values — do not commit them)
--
-- 1. Before running this migration, check who stays an admin:
--      select status, count(*) from public.society_admin_users group by 1;
--    Only rows with status = 'active' keep admin access after section 1.
--
-- 2. PAN encryption key. Keep an offline copy: losing it makes every
--    stored PAN unreadable.
--      select vault.create_secret(
--        encode(extensions.gen_random_bytes(32), 'base64'),
--        'resident_pii_key_v1');
--
-- 3. Deploy the purge function and give it a shared secret:
--      supabase functions deploy purge-resident-documents --no-verify-jwt
--      supabase secrets set PURGE_WEBHOOK_SECRET=<long random string>
--      select vault.create_secret(
--        'https://<project-ref>.supabase.co/functions/v1/purge-resident-documents',
--        'documents_purge_url');
--      select vault.create_secret('<same long random string>', 'documents_purge_secret');
--
-- 4. Enable pg_cron (Dashboard -> Database -> Extensions), then schedule
--    it nightly at 03:00 IST:
--      select cron.schedule('purge-resident-documents', '30 21 * * *',
--        $cron$ select public.invoke_document_purge() $cron$);
--
-- 5. Never turn on statement or parameter logging (log_min_duration_statement,
--    pgaudit with parameter logging): RPC arguments — including a PAN being
--    saved — would be written to the logs.
-- ------------------------------------------------------------
