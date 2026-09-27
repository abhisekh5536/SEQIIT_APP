# Vehicles & Parking Module — Implementation Plan

Part of Saqiit's Phase 5 (🟠 secondary) feature set. Follows the same architectural patterns already established: `society_id` denormalized onto every table for cheap RLS, status-transition rules enforced in Server Action code (not just UI), and the existing 4-panel model (Master Admin / Society Admin / Guard / Resident).

---

## 1. Scope & Decisions

Two separate concerns get conflated in most "parking module" specs — keep them as two features that link to each other, not one:

1. **Vehicles** — a registry of what vehicles a resident owns.
2. **Parking allocation** — which physical slot(s) a flat/resident has been assigned.

A resident can register a vehicle without having an allocated slot (waitlisted), and a slot can be allocated to a flat without a specific vehicle attached (many societies allocate "1 covered slot per flat," not "1 slot per vehicle"). Don't force a 1:1 vehicle↔slot relationship in the schema.

**Decisions to lock in before building (recommend defaults, confirm with you):**
- Allocation is **per-flat**, not per-vehicle, with an optional `vehicle_id` link when the society wants to bind a slot to one specific vehicle. (Default: per-flat.)
- A flat can register **multiple vehicles** but the number of **allocated slots** is capped by `module_flags`/plan config (e.g., "2 slots per flat max") — enforce in Server Action, not RLS.
- Visitor vehicle parking (temp parking for guests) is **out of scope for this module's v1** — it already partially lives in Visitor Management (visitor's vehicle number field, if present). Flag as a future integration point rather than build now.
- Fee collection for parking (some societies charge per slot) is **out of scope for v1** — reuse the Maintenance Billing module later if needed, don't build a parallel billing path.

---

## 2. Database Schema

```sql
-- Vehicle registry (resident-owned)
vehicles (
  id, society_id, flat_id, resident_id [→ residents],
  type: two_wheeler | four_wheeler | other,
  vehicle_number,              -- normalized uppercase, no spaces, unique per society
  make_model,
  color,
  rc_photo_url,
  status: active | inactive,   -- inactive = resident removed it but keep history
  created_at, updated_at
)

-- Physical slot inventory (society admin defines these)
parking_slots (
  id, society_id, block_id [nullable → blocks],
  slot_number,
  vehicle_type: two_wheeler | four_wheeler | other,
  category: covered | open,
  status: vacant | allocated | reserved | maintenance,
  created_at
)

-- Who currently holds which slot
parking_allocations (
  id, society_id, slot_id [→ parking_slots], flat_id [→ flats],
  resident_id [→ residents],
  vehicle_id [nullable → vehicles],   -- optional binding to a specific vehicle
  allocated_from, allocated_until [nullable],
  status: active | ended,
  allocated_by [→ society_admin_users],
  notes,
  created_at
)

-- Gate log for guard verification (optional but high-value for MVP)
vehicle_entry_logs (
  id, society_id,
  vehicle_id [nullable → vehicles],   -- null if unregistered vehicle
  vehicle_number_entered,             -- raw manual entry, always stored even if matched
  match_status: registered | unregistered,
  entry_at, exit_at [nullable],
  logged_by [→ guard],
  notes
)
```

**Constraints worth adding at the DB level, not just app logic:**
- `unique (society_id, vehicle_number)` on `vehicles` — prevents duplicate registration across flats within a society.
- `unique (slot_id) where status = 'active'` on `parking_allocations` (partial unique index) — a slot can only have one active allocation at a time.
- A trigger (or Server Action check) that flips `parking_slots.status` to `allocated`/`vacant` whenever an allocation is created/ended, so the slot list stays a reliable source of truth without a join every time.

---

## 3. RLS Policies

| Table | Master Admin | Society Admin | Guard | Resident |
|---|---|---|---|---|
| `vehicles` | full | full, scoped to `society_id` | read-only, scoped to `society_id` | CRUD own rows (`resident_id = auth.uid()`'s resident row) only |
| `parking_slots` | full | full, scoped to `society_id` | read-only, scoped to `society_id` | read-only, scoped to `society_id` |
| `parking_allocations` | full | full, scoped to `society_id` | read-only, scoped to `society_id` | read-only, own flat's rows only |
| `vehicle_entry_logs` | full | read-only, scoped to `society_id` | create + read, scoped to `society_id` | none |

Same pattern as the rest of the app: Resident write access is narrow (their own vehicles only), Guard is read-heavy plus one write surface (entry logs), Society Admin owns slot inventory and allocation.

---

## 4. Screens Per Panel

**Society Admin**
- Parking Slots Inventory — list/add/edit slots (bulk-add by block + count, like the existing blocks/flats bulk-add pattern), filter by vacant/allocated/maintenance
- Slot Allocation — pick a vacant slot → assign to a flat (+ optional vehicle) → sets `allocated_from`
- End Allocation — revoke a slot from a flat (move-out parity with the existing flat move-out flow), flips slot back to vacant
- Vehicles Directory — all registered vehicles across the society, searchable by number/flat, flag any vehicle with no active allocation (waitlisted)
- Parking Policy Config — max slots per flat, whether allocation requires a bound vehicle (reuses `module_flags`-style per-society config)

**Resident**
- My Vehicles — add/edit/remove own vehicles (RC photo upload optional), see registration status
- My Parking — read-only view of currently allocated slot(s), or "waitlisted" state if none

**Guard**
- Vehicle Lookup — search by plate number → instantly shows registered/unregistered + flat + resident name (this is the actual gate-use screen, needs to be fast, minimal taps)
- Log Entry/Exit — quick log against a lookup result or a manual unregistered entry, mirrors the existing Visitor entry-log UX so guards aren't learning two different patterns

---

## 5. Status-Transition Rules (enforce in Server Action, not just UI)

- Only Society Admin can create/end a `parking_allocations` row.
- A slot can't be allocated if `status != 'vacant'` — recheck in the Server Action even though the UI won't show it as selectable (race condition between two admins).
- A resident can deactivate their own vehicle (`status → inactive`) but can't delete a vehicle row that has allocation history — soft-delete only, same principle as `flat_occupancy_history` preserving move-out records.
- Guard entry logs are append-only from the Guard side — no edit/delete, matching the audit-trail intent of `audit_logs` elsewhere in the app.

---

## 6. Build Order

1. Migration: `vehicles`, `parking_slots`, `parking_allocations`, `vehicle_entry_logs` + RLS policies + the partial-unique-index/trigger for slot status sync.
2. Society Admin: Parking Slots Inventory (add/bulk-add/edit) — no dependencies, build first.
3. Resident: My Vehicles (add/edit/remove) — no dependencies, can build in parallel with (2).
4. Society Admin: Slot Allocation screen — depends on (2) and (3) existing so there's real data to allocate against.
5. Resident: My Parking (read-only) — trivial once (4) exists.
6. Guard: Vehicle Lookup + Entry/Exit log — depends on (3); reuse Visitor Management's entry-log component/pattern rather than building a new one from scratch.
7. Society Admin: Parking Policy Config + Vehicles Directory — polish pass once the core flow works end-to-end.

---

## 7. Definition of Done

Admin bulk-adds parking slots for a block → resident registers a vehicle for their flat → admin allocates a vacant slot to that flat (optionally bound to the vehicle) → slot flips to `allocated` and disappears from the vacant pool → resident sees their allocated slot in My Parking → guard looks up the vehicle number at the gate and sees it as registered with correct flat info → guard logs entry/exit → admin ends the allocation on move-out and the slot correctly reverts to `vacant` and becomes assignable again → an unregistered vehicle looked up by guard correctly shows as unregistered and still gets logged.

---

## 8. Explicitly Deferred

- Visitor vehicle temp parking (link to Visitor Management)
- Parking fee billing (link to Maintenance Billing when needed)
- Multiple vehicles bound to one slot / one vehicle across multiple slots (not a real-world case worth the complexity)
- Automated plate recognition (ANPR) at the gate — Guard Lookup is manual entry for now, same MVP philosophy as the Recharge Generator's manual switch-flip
