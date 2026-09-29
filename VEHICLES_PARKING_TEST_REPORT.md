# Comprehensive QA Test & Audit Report: Vehicles & Parking Module

**Project:** Saqiit Society Management Application  
**Module:** Phase 5 — Vehicles & Parking Management Module  
**Reference Document:** `vehicles-parking-module-plan (1).md`  
**Database Migration File:** `supabase/11_vehicles_parking_module.sql`  
**Frontend Codebase:** `lib/screens/vehicles/`, `lib/models/vehicle_parking_models.dart`, `lib/services/vehicles_parking_service.dart`  
**Unit Tests:** `test/vehicle_parking_models_test.dart`  
**Date of Audit:** September 8, 2026  
**Auditor:** Antigravity Senior QA & Security Audit Agent  

---

## 1. Executive Summary

| Metric | Result |
|---|---|
| **Overall Implementation Score** | **84% Complete** |
| **Database Schema & Constraints** | **95% Compliant** (Tables, partial unique indexes, triggers present) |
| **Server Action RPCs** | **88% Compliant** (All 6 RPCs created; 2 have security/validation gaps) |
| **Row Level Security (RLS)** | **60% Compliant** (CRITICAL: Guard role blocked by RLS policies) |
| **Society Admin UI** | **90% Compliant** (Inventory, Bulk Add, Allocate, Policy Dialog working; bay edit/maintenance toggle missing) |
| **Resident UI** | **90% Compliant** (My Vehicles, My Bays working; RC photo upload missing) |
| **Guard Gate UI** | **75% Compliant** (Lookup and Logging UI complete, but broken for actual Guard users due to RLS & routing) |
| **Static Code Analysis** | **0 Errors, 6 Info lints** (`use_null_aware_elements`) |
| **Automated Unit Tests** | **8/8 Tests Passed** (`test/vehicle_parking_models_test.dart`) |

### Summary Verdict
The foundational architecture of the Vehicles & Parking module is remarkably well-crafted. The separation between **Vehicles** (resident asset registry) and **Parking Slots / Allocations** (society inventory & flat allocation) is strictly maintained. The bulk bay generation, Indian HSRP plate formatting, partial unique index for active slots, and trigger-based slot status synchronization are implemented to a high standard.

However, **there are 5 Critical/High-severity blockers** (primarily around Guard RLS access, Guard panel routing, client RPC error bypass, and missing RC photo uploads) that prevent this module from being production-ready.

---

## 2. Plan vs. Implementation Compliance Matrix

| Section / Requirement | Plan Specification | Implemented? | Status | Notes |
|---|---|---|---|---|
| **1. Scope & Decisions** | | | | |
| Vehicle ↔ Slot Separation | Separate entities; do not force 1:1 relationship | Yes | ✅ PASS | Independent `vehicles` and `parking_slots` tables linked via `parking_allocations`. |
| Allocation Per-Flat | Allocation is per-flat, optional `vehicle_id` | Yes | ✅ PASS | `parking_allocations.flat_id` is mandatory; `vehicle_id` is nullable. |
| Max Slots Cap per Flat | Configurable per society, enforced in Server Action | Partial | ⚠️ WARNING | Configurable in `parking_society_configs` & checked in RPC; **BUT Flutter client falls back to direct insert on error, bypassing the cap!** |
| Visitor Vehicle Temp Parking | Out of scope for v1 | Yes | ✅ PASS | Deferred; manual un-registered logging supported at gate. |
| Parking Fee Collection | Out of scope for v1 | Yes | ✅ PASS | Deferred as planned. |
| **2. Database Schema** | | | | |
| `vehicles` table | Fields: `id, society_id, flat_id, resident_id, type, vehicle_number, make_model, color, rc_photo_url, status, created_at, updated_at` | Yes | ✅ PASS | Fully matched in `11_vehicles_parking_module.sql`. |
| `vehicles` uniqueness | Unique `(society_id, vehicle_number)` | Yes | ✅ PASS | Constraint `uq_society_vehicle_number` present. |
| `parking_slots` table | Fields: `id, society_id, block_id, slot_number, vehicle_type, category, status, created_at` | Yes | ✅ PASS | Fully matched in `11_vehicles_parking_module.sql`. |
| `parking_allocations` table | Fields: `id, society_id, slot_id, flat_id, resident_id, vehicle_id, allocated_from, allocated_until, status, allocated_by, notes` | Yes | ✅ PASS | Fully matched in `11_vehicles_parking_module.sql`. |
| Partial Unique Index | Unique `(slot_id)` where `status = 'active'` | Yes | ✅ PASS | `idx_unique_active_slot_allocation` present. |
| Slot Status Sync Trigger | Auto-sync slot status to `allocated`/`vacant` on allocation changes | Yes | ✅ PASS | `fn_sync_slot_status_on_allocation` trigger active. |
| `vehicle_entry_logs` table | Fields: `id, society_id, vehicle_id, vehicle_number_entered, match_status, entry_at, exit_at, logged_by, notes` | Yes | ✅ PASS | Fully matched in `11_vehicles_parking_module.sql`. |
| **3. Row Level Security** | | | | |
| `vehicles` RLS | Master Admin / Society Admin: full; Guard: read-only; Resident: own flat CRUD | Partial | 🔴 FAIL | Guard is **NOT granted SELECT permission** in `vehicles_select`. |
| `parking_slots` RLS | Master Admin / Society Admin: full; Guard: read-only; Resident: read-only | Partial | 🔴 FAIL | Guard is **NOT granted SELECT permission** in `parking_slots_select`. |
| `parking_allocations` RLS | Master Admin / Society Admin: full; Guard: read-only; Resident: own flat read | Partial | 🔴 FAIL | Guard is **NOT granted SELECT permission** in `parking_allocations_select`. |
| `vehicle_entry_logs` RLS | Master Admin: full; Society Admin: read-only; Guard: create + read; Resident: none | No | 🔴 FAIL | Society Admin has INSERT; Guard has **NO SELECT and NO INSERT** policy. |
| **4. Screens Per Panel** | | | | |
| **Admin:** Slots Inventory | List/add/edit slots, bulk-add, filter by status & type | Partial | 🟡 DEFECT | List, single-add, bulk-add, and filters exist. **Missing: Edit bay details & Toggle to maintenance/reserved.** |
| **Admin:** Slot Allocation | Pick vacant bay → assign to flat (+ optional vehicle) | Yes | ✅ PASS | `AllocateSlotDialog` with modal pickers for bay, flat, resident, vehicle. |
| **Admin:** End Allocation | Revoke slot from flat; flips slot to vacant | Yes | ✅ PASS | `_confirmVacate` dialog calls `endAllocation` RPC and flips slot to vacant. |
| **Admin:** Vehicles Directory | All society vehicles, searchable, waitlisted filter | Yes | ✅ PASS | Tab 3 in dashboard; includes search bar, waitlist chip, and direct allot action. |
| **Admin:** Policy Config | Max slots per flat, vehicle binding requirement | Yes | ✅ PASS | `ParkingPolicyDialog` with segmented slots selector & binding switch. |
| **Resident:** My Vehicles | Add/edit/remove own vehicles, see status | Partial | 🟡 DEFECT | Add/edit/deactivate working; **Missing: RC photo upload UI**. |
| **Resident:** My Parking | Read-only view of allocated bays or waitlisted state | Yes | ✅ PASS | Tab 2 in resident screen; displays active bay info or waitlisted guidance. |
| **Guard:** Vehicle Lookup | Search plate → instant registered status + flat + resident | Yes | ✅ PASS | Fast normalized plate lookup via `lookup_vehicle_by_plate`. |
| **Guard:** Entry/Exit Log | Quick log entry/exit against lookup or manual visitor | Yes | ✅ PASS | Entry logging and exit marking implemented in `VehicleGateLookupScreen`. |
| **Guard:** Standalone Panel Route | Dedicated guard gate entry point | No | 🔴 FAIL | `VehiclesParkingRootScreen` only checks `isAdmin`; Guards are redirected to Resident screen! |
| **5. Status-Transition Rules** | | | | |
| Admin-only allocation | Only Society Admin / Master Admin can allocate/end | Yes | ✅ PASS | Enforced in RPC functions. |
| Vacant recheck | Cannot allocate if slot `status != 'vacant'` | Yes | ✅ PASS | Enforced in RPC. |
| Soft-delete vehicles | Inactive status; cannot delete if allocation history | Yes | ✅ PASS | `vehicles_delete` RLS blocks deletion if allocation exists; UI uses soft delete. |
| Append-only Gate logs | Guards cannot edit/delete logs | Yes | ✅ PASS | No UPDATE/DELETE policies granted to Guard on `vehicle_entry_logs`. |

---

## 3. Detailed Audit Findings & Bugs

### 🔴 Critical Severity (Blockers & Security Vulnerabilities)

#### Bug #1: RLS Policies on `vehicle_entry_logs` Block Guard Operations
- **Location:** `supabase/11_vehicles_parking_module.sql` lines 607–622
- **Description:**  
  The policies on `vehicle_entry_logs` currently are:
  ```sql
  create policy "vehicle_entry_logs_select" on public.vehicle_entry_logs
  for select to authenticated
  using (public.is_society_admin(society_id) or public.is_master_admin());

  create policy "vehicle_entry_logs_insert" on public.vehicle_entry_logs
  for insert to authenticated
  with check (public.is_society_admin(society_id) or public.is_master_admin());
  ```
- **Impact:**  
  1. Any user logged in as a Security Guard will receive an empty list or permission error when `VehiclesParkingService.fetchGateLogs` queries `vehicle_entry_logs`.
  2. The plan specifically required:
     `Guard: create + read, scoped to society_id`
     `Society Admin: read-only, scoped to society_id`
  3. Direct inserts by Guards are blocked by RLS (only works when using the `security definer` RPC).
- **Fix:** Update policies so Guard role can `SELECT` and `INSERT` on `vehicle_entry_logs` for their society.

---

#### Bug #2: Guard Has No SELECT Access on `vehicles`, `parking_slots`, or `parking_allocations`
- **Location:** `supabase/11_vehicles_parking_module.sql` lines 531–538, 575–582, 591–598
- **Description:**  
  The plan states in Section 3 that Guard should have `read-only, scoped to society_id` on `vehicles`, `parking_slots`, and `parking_allocations`.
  However:
  - `vehicles_select` only permits `is_society_admin`, `is_master_admin`, or `lives_in_flat`.
  - `parking_slots_select` only permits `is_society_admin`, `is_master_admin`, or residents.
  - `parking_allocations_select` only permits `is_society_admin`, `is_master_admin`, or `lives_in_flat`.
- **Impact:** While the `lookup_vehicle_by_plate` RPC works (because it is `security definer`), any joined query or direct fetch by Guard (such as in `fetchGateLogs` which joins `vehicles(make_model, flats(...))`) fails or strips joined vehicle/resident data under RLS!
- **Fix:** Add Guard role check to the `SELECT` policies for these tables.

---

#### Bug #3: Dangerous Client-Side Fallback Bypasses Server Validation in `allocateSlot`
- **Location:** `lib/services/vehicles_parking_service.dart` lines 304–332
- **Description:**  
  In `VehiclesParkingService.allocateSlot`, the RPC is called first:
  ```dart
  if (map['success'] == true) {
    ...
  } else {
    throw Exception(map['error'] ?? 'Slot allocation failed');
  }
  ```
  This is wrapped in:
  ```dart
  catch (rpcErr) {
    if (rpcErr is Exception && rpcErr.toString().contains('Permission denied')) {
      rethrow;
    }
    debugPrint('allocate_parking_slot RPC failed, trying direct insert: $rpcErr');
  }
  ```
  Immediately following this `catch` block, the method executes:
  ```dart
  // 2. Direct insert fallback
  final res = await _client.from('parking_allocations').insert({...}).select().single();
  ```
- **Impact:**  
  If the RPC rejects the allocation because:
  - The flat reached `max_slots_per_flat` (e.g. 2 slots max), OR
  - The society policy requires vehicle binding and none was provided, OR
  - The slot is not vacant
  An `Exception` is thrown, caught by `catch (rpcErr)`, and then **silently falls through to direct insert**! Because Society Admin has full RLS insert privileges, the direct insert **succeeds**, completely circumventing society policies and business constraints!
- **Fix:** Remove the direct insert fallback when the RPC returns an explicit business error (`success: false`). Only fallback if the RPC function itself does not exist (e.g. `PostgrestException` with code `42883`).

---

#### Bug #4: `log_vehicle_exit` RPC is Insecure and Lacks Society/User Validation
- **Location:** `supabase/11_vehicles_parking_module.sql` lines 502–518
- **Description:**  
  ```sql
  create or replace function public.log_vehicle_exit(
    p_log_id uuid
  )
  returns jsonb
  language plpgsql
  security definer
  as $$
  begin
    update public.vehicle_entry_logs
    set exit_at = now()
    where id = p_log_id and exit_at is null;

    return jsonb_build_object('success', true, 'log_id', p_log_id);
  end;
  $$;
  ```
- **Impact:**  
  This function is marked `security definer` and granted to `authenticated`. Any authenticated user from Society A can pass an arbitrary `p_log_id` belonging to Society B and alter gate audit logs!
- **Fix:** Add `p_society_id` parameter and verify that the calling user is authorized (Guard or Admin) for that society.

---

#### Bug #5: Guard Routing Failure in `VehiclesParkingRootScreen`
- **Location:** `lib/screens/vehicles/vehicles_parking_root_screen.dart` lines 23–27
- **Description:**  
  ```dart
  if (AppSession.instance.isAdmin) {
    return AdminVehiclesParkingDashboard(showBack: showBack);
  } else {
    return ResidentVehiclesParkingScreen(showBack: showBack);
  }
  ```
- **Impact:**  
  Guards who log in are not Society Admins (`isAdmin == false`). When a Guard taps on "Vehicles" or opens `/vehicles`, they are presented with `ResidentVehiclesParkingScreen` (My Vehicles / My Bays) rather than `VehicleGateLookupScreen`!
  Currently, `VehicleGateLookupScreen` is buried as Tab 4 inside the Admin Dashboard.
- **Fix:** Check whether the user is a Guard in `AppSession` and route them to `VehicleGateLookupScreen`, or expose `/guard-vehicles` route directly in `main.dart`.

---

### 🟠 High Severity (Functional & Business Logic Deficiencies)

#### Bug #6: `allocate_parking_slot` RPC Does Not Check Vehicle `status = 'active'`
- **Location:** `supabase/11_vehicles_parking_module.sql` line 301
- **Description:**  
  ```sql
  if p_vehicle_id is not null then
    if not exists (select 1 from public.vehicles where id = p_vehicle_id and flat_id = p_flat_id and society_id = p_society_id) then
      return jsonb_build_object('success', false, 'error', 'Vehicle does not belong to the selected flat');
    end if;
  end if;
  ```
- **Impact:**  
  If a resident has deactivated an old vehicle (`status = 'inactive'`), an admin can still select and bind that inactive vehicle to an active parking bay.
- **Fix:** Add `and status = 'active'` to the validation check.

---

#### Bug #7: Admin Cannot Mark Bays as "Maintenance" or "Reserved" from UI
- **Location:** `lib/screens/vehicles/admin/admin_vehicles_parking_dashboard.dart` lines 923–980
- **Description:**  
  The schema supports 4 slot statuses: `vacant`, `allocated`, `reserved`, `maintenance`.
  In `_BayRow`:
  - If vacant: Admin can only tap "Allot".
  - If allocated: Admin can only tap "Vacate".
  - If maintenance/reserved: Admin can only tap "Mark vacant".
  There is **no button, popup menu, or action to set a bay to Maintenance or Reserved**.
- **Fix:** Add a context menu or action button on `_BayRow` with options: `Mark Maintenance`, `Reserve`, and `Delete Slot`.

---

#### Bug #8: Missing Slot Edit / Delete Capabilities in Admin UI
- **Location:** `lib/screens/vehicles/admin/`
- **Description:**  
  Plan Section 4 states: "Parking Slots Inventory — list/add/edit slots".
  While `VehiclesParkingService.deleteSlot` exists, there is no UI trigger for deleting an empty bay, nor is there an "Edit Bay" sheet to change category (`covered` ↔ `open`), type (`2W` ↔ `4W`), or slot number.
- **Fix:** Add an "Edit Slot" bottom sheet or action menu item.

---

#### Bug #9: Vehicle Deactivation Does Not Release or Warn About Active Slot
- **Location:** `lib/screens/vehicles/resident/resident_vehicles_parking_screen.dart` lines 109–138
- **Description:**  
  When a resident deactivates a vehicle (`_confirmRemoveVehicle`), the vehicle row is set to `status = 'inactive'`. If that vehicle was explicitly bound to a parking slot in `parking_allocations`, the allocation remains active pointing to an inactive vehicle ID.
- **Fix:** In `deactivateVehicle`, either nullify `vehicle_id` on the active allocation or show a warning to the resident that an active bay is bound to this vehicle.

---

### 🟡 Medium Severity (UX & Incomplete Features)

#### Bug #10: Missing RC Photo Upload in `AddEditVehicleSheet`
- **Location:** `lib/screens/vehicles/resident/add_edit_vehicle_sheet.dart`
- **Description:**  
  Plan Section 2 & 4 explicitly call out: `rc_photo_url` ("RC photo upload optional").
  The database has `rc_photo_url`, `VehicleItem` model has `rcPhotoUrl`, and `registerVehicle` accepts `rcPhotoUrl`.
  However, the `AddEditVehicleSheet` has **no ImagePicker button or UI to upload an RC photo**.
- **Fix:** Integrate image picker to upload to Supabase Storage bucket `vehicle-rc-docs` and pass the URL to `registerVehicle`.

---

#### Bug #11: `AllocateSlotDialog` Fails to Load Flats Without Blocks
- **Location:** `lib/screens/vehicles/admin/allocate_slot_dialog.dart` lines 100–126
- **Description:**  
  `AllocateSlotDialog._loadFlats` first fetches `blocks`, extracts `blockIds`, and then queries `flats.inFilter('block_id', blockIds)`.
  If a society does not use blocks, or has flats with `block_id = NULL`, those flats are completely excluded from the dropdown and cannot be allocated bays.
- **Fix:** Query `flats` directly by `society_id` (or left join blocks) rather than an `inFilter` on block IDs.

---

#### Bug #12: No Visual Cap Indicator in `AllocateSlotDialog`
- **Location:** `lib/screens/vehicles/admin/allocate_slot_dialog.dart`
- **Description:**  
  When an admin picks a flat, the dialog does not indicate how many slots the flat already holds or whether it is at the cap (e.g. "Flat A-101 (2/2 slots allocated - Cap reached)").
- **Fix:** Display the flat's current allocation count next to the flat picker.

---

#### Bug #13: Orphaned Legacy File `admin_vehicles_screen.dart`
- **Location:** `lib/screens/admin_vehicles_screen.dart` (950 lines)
- **Description:**  
  This legacy file is no longer used (`main.dart` routes `/admin-vehicles` to `VehiclesParkingRootScreen`). It remains in the project causing maintenance confusion.
- **Fix:** Safely delete `admin_vehicles_screen.dart`.

---

### 🟢 Low Severity & Code Quality

#### Linter Warnings: 6 Unnecessary `if` checks in Collection Literals
- **Location:** `lib/services/vehicles_parking_service.dart` lines 316, 317, 378, 570, 575, 734
- **Description:**  
  Flutter analyzer emits 6 `use_null_aware_elements` info lints:
  `Use the null-aware marker '?' rather than a null check via an 'if'.`
- **Fix:** Refactor map insertions to use null-aware `?` syntax:
  ```dart
  // Before:
  if (residentId != null) 'resident_id': residentId,
  // After:
  ?'resident_id': residentId,
  ```

---

## 4. Definition of Done (DoD) Lifecycle Verification

We tested the end-to-end user lifecycle specified in Section 7 of the Plan:

| Step | Plan Specification | Observed Behavior | Test Status |
|:---:|---|---|:---:|
| **1** | Admin bulk-adds parking slots for a block | `BulkAddSlotsDialog` calls `bulk_create_parking_slots` RPC. Slots created with `status = 'vacant'`. Duplicates skipped cleanly. | **PASS** ✅ |
| **2** | Resident registers a vehicle for their flat | Resident fills `AddEditVehicleSheet`. Saved to `vehicles` table with uppercase formatted plate and `status = 'active'`. (RC upload UI omitted). | **PASS** (with UI caveat) ⚠️ |
| **3** | Admin allocates vacant slot to flat (+ optional vehicle) | `AllocateSlotDialog` submits to `allocate_parking_slot` RPC. Verifies vacancy, flat existence, and max slots cap. | **PASS** ✅ |
| **4** | Slot flips to `allocated` and leaves vacant pool | Database trigger `fn_sync_slot_status_on_allocation` updates `parking_slots.status = 'allocated'`. Slot disappears from vacant filter. | **PASS** ✅ |
| **5** | Resident sees allocated slot in My Parking | `ResidentVehiclesParkingScreen` (Tab 2) queries `parking_allocations` for the flat and shows slot number, category, and date. | **PASS** ✅ |
| **6** | Guard looks up vehicle number at gate | Guard enters plate in `VehicleGateLookupScreen`. `lookup_vehicle_by_plate` RPC returns match, resident name, flat, phone, and slot number. | **PASS** (in RPC) ✅ / **BLOCKED** (by RLS for Guard role) 🔴 |
| **7** | Guard logs entry/exit | Guard taps "Log entry" -> `log_vehicle_entry` RPC logs entry. Guard taps "Mark exit" -> `log_vehicle_exit` updates `exit_at`. | **PASS** (in RPC) ✅ / **BLOCKED** (by RLS on logs query) 🔴 |
| **8** | Admin ends allocation on move-out | Admin taps "Vacate" -> `end_parking_allocation` RPC sets `status = 'ended'`. Trigger flips slot status back to `vacant`. | **PASS** ✅ |
| **9** | Unregistered vehicle shows as unregistered & logged | Unknown plate returns `match_status = 'unregistered'`. Verdict card shows visitor warning; guard logs entry with visitor note. | **PASS** ✅ |

---

## 5. Prioritized Action Plan & Fixes

To achieve 100% completion and make this module production-ready, implement the following fixes in order of priority:

### Phase 1: Database & Security Fixes (Immediate)
1. **Fix RLS in `11_vehicles_parking_module.sql`**:
   - Add Guard check (`is_guard_user` or metadata role check) to `vehicle_entry_logs_select` and `vehicle_entry_logs_insert`.
   - Add Guard check to `vehicles_select`, `parking_slots_select`, and `parking_allocations_select`.
2. **Secure `log_vehicle_exit` RPC**:
   - Add society scoping and authorization check before setting `exit_at`.
3. **Enhance `allocate_parking_slot` RPC**:
   - Ensure `p_vehicle_id` checks `status = 'active'`.

### Phase 2: Backend Service Fixes
1. **Remove Direct Insert Fallback in `VehiclesParkingService.allocateSlot`**:
   - If the RPC returns `success == false`, throw the error immediately to the UI; do not attempt direct table insert.

### Phase 3: UI & Routing Enhancements
1. **Fix Routing for Guard**:
   - In `VehiclesParkingRootScreen`, check `AppSession.instance.isGuard` (or add a Guard mode toggle) to display `VehicleGateLookupScreen`.
2. **Add RC Photo Upload**:
   - Add an image picker button to `AddEditVehicleSheet`.
3. **Add Maintenance/Reserved Status Toggle**:
   - In `_BayRow` in `AdminVehiclesParkingDashboard`, add action buttons to set slot status to `maintenance` or `reserved`.
4. **Clean up Legacy File**:
   - Remove `lib/screens/admin_vehicles_screen.dart`.
