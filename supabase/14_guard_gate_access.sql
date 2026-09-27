-- ============================================================
-- 14) GUARD ACCESS TO THE VISITOR GATE FLOW
--
-- The visitor module was written with the gate operator signed in as a
-- society admin ("admin gate stand-in"). Migration 11 introduced
-- `public.is_guard_or_admin()` for the parking gate, but `visitors` has
-- no guard policy at all — so a real guard account sees nothing.
--
-- This grants a guard exactly what the gate job needs and nothing more:
--
--   read   the society's visitors, group members and status history
--   create gate requests (Flow A: someone turns up unannounced)
--   move   an already-approved visitor to checked_in / checked_out
--
-- Deliberately NOT granted: approving or denying. That decision belongs
-- to the resident, and a guard must not be able to wave someone in on
-- their behalf. The UPDATE policy below enforces that as a transition
-- rule, not just a convention.
--
-- Guards are identified by the `role` claim on the auth user, which is
-- what is_guard_or_admin() already reads:
--   auth.admin.updateUserById(id, { user_metadata: {
--     role: 'guard', society_id: '<society uuid>' } })
-- ============================================================

-- ------------------------------------------------------------
-- 1) visitors
-- ------------------------------------------------------------
drop policy if exists "guard read society visitors" on public.visitors;
create policy "guard read society visitors"
on public.visitors for select to authenticated
using (public.is_guard_or_admin(society_id));

drop policy if exists "guard log gate request" on public.visitors;
create policy "guard log gate request"
on public.visitors for insert to authenticated
with check (
  public.is_guard_or_admin(society_id)
  and entry_type = 'gate_request'
  and status = 'pending_approval'
);

-- Check-in / check-out only. `using` limits which rows a guard may touch
-- (already approved or already inside); `with check` limits what those
-- rows may become. A pending row is therefore untouchable, so a guard
-- cannot self-approve a visitor.
drop policy if exists "guard check in out visitor" on public.visitors;
create policy "guard check in out visitor"
on public.visitors for update to authenticated
using (
  public.is_guard_or_admin(society_id)
  and status in ('approved', 'checked_in')
)
with check (
  public.is_guard_or_admin(society_id)
  and status in ('approved', 'checked_in', 'checked_out')
);

-- ------------------------------------------------------------
-- 2) visitor_group_members
-- ------------------------------------------------------------
drop policy if exists "guard read visitor_group_members" on public.visitor_group_members;
create policy "guard read visitor_group_members"
on public.visitor_group_members for select to authenticated
using (
  exists (
    select 1 from public.visitors v
    where v.id = visitor_group_members.visitor_id
      and public.is_guard_or_admin(v.society_id)
  )
);

-- ------------------------------------------------------------
-- 3) visitor_status_history
-- ------------------------------------------------------------
drop policy if exists "guard read visitor_status_history" on public.visitor_status_history;
create policy "guard read visitor_status_history"
on public.visitor_status_history for select to authenticated
using (
  exists (
    select 1 from public.visitors v
    where v.id = visitor_status_history.visitor_id
      and public.is_guard_or_admin(v.society_id)
  )
);

drop policy if exists "guard append visitor_status_history" on public.visitor_status_history;
create policy "guard append visitor_status_history"
on public.visitor_status_history for insert to authenticated
with check (
  exists (
    select 1 from public.visitors v
    where v.id = visitor_status_history.visitor_id
      and public.is_guard_or_admin(v.society_id)
  )
);

-- ------------------------------------------------------------
-- 4) parking_bay_requests — guards do not review these
--
-- Nothing granted here on purpose: bay allotment is an office decision,
-- not a gate one. Listed so the omission reads as deliberate.
-- ------------------------------------------------------------
