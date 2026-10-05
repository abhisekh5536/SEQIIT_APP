-- ============================================================
-- 21) HOME CAROUSEL SUMMARY
--
-- The home screen's always-on cards (My Flat / Society, Security desk)
-- need a few society-wide counts that residents are not allowed to read
-- row by row: society_guards and society_gates are admin/guard-only.
--
-- get_home_summary() returns COUNTS ONLY (no names, no phone numbers),
-- after checking the caller belongs to the society, plus the caller's own
-- parking bays. One round trip instead of six.
--
-- Prerequisite: migrations 01, 10, 11, 17 (society_guards / gates).
-- Idempotent: safe to re-run.
-- ============================================================

create or replace function public.get_home_summary(p_society_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  v_is_staff  boolean;
  v_my_flats  uuid[];
begin
  if v_uid is null or p_society_id is null then
    return null;
  end if;

  v_is_admin := public.is_society_admin(p_society_id) or public.is_master_admin();
  v_is_staff := v_is_admin or public.is_guard_or_admin(p_society_id);

  if not (v_is_staff or public.is_society_member(p_society_id)) then
    return null;
  end if;

  select coalesce(array_agg(r.flat_id), '{}')
    into v_my_flats
    from public.residents r
   where r.user_id = v_uid
     and r.society_id = p_society_id
     and r.status = 'active';

  return json_build_object(
    -- Security desk (same for everyone)
    'gates_active', (
      select count(*) from public.society_gates g
       where g.society_id = p_society_id and g.is_active),
    'guards_active', (
      select count(*) from public.society_guards g
       where g.society_id = p_society_id and g.status = 'active'),
    'emergency_contacts', (
      select count(*) from public.emergency_contacts e
       where e.is_active
         and (e.is_global or e.society_id = p_society_id)),
    -- Staff see every open SOS in the society; residents only their own flat's.
    'open_sos', (
      select count(*) from public.sos_alerts s
       where s.society_id = p_society_id
         and s.status in ('active', 'acknowledged')
         and (v_is_staff or s.flat_id = any (v_my_flats))),

    -- Society overview (admins and guards only)
    'total_flats', case when v_is_staff then (
      select count(*) from public.flats f
        join public.blocks b on b.id = f.block_id
       where b.society_id = p_society_id) end,
    'occupied_flats', case when v_is_staff then (
      select count(*) from public.flats f
        join public.blocks b on b.id = f.block_id
       where b.society_id = p_society_id and f.status = 'occupied') end,
    'active_residents', case when v_is_staff then (
      select count(*) from public.residents r
       where r.society_id = p_society_id and r.status = 'active') end,
    'blocks', case when v_is_staff then (
      select count(*) from public.blocks b where b.society_id = p_society_id) end,

    -- The caller's own flat(s)
    'my_block', (
      select b.name from public.flats f
        join public.blocks b on b.id = f.block_id
       where f.id = any (v_my_flats)
       limit 1),
    'my_parking_slots', (
      select coalesce(json_agg(s.slot_number order by s.slot_number), '[]'::json)
        from public.parking_allocations a
        join public.parking_slots s on s.id = a.slot_id
       where a.flat_id = any (v_my_flats)
         and a.status = 'active')
  );
end;
$$;

revoke all on function public.get_home_summary(uuid) from public, anon;
grant execute on function public.get_home_summary(uuid) to authenticated;
