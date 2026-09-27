# Saqiit — Codebase Audit: Bugs, Glitches & Fix Priority

**Repository:** `seqiit` (Flutter + Supabase society management app)
**Branch audited:** `vechicle_parking`
**Date:** 22 September 2026
**Scope:** Whole codebase — auth, visitors, vehicles & parking, security/SOS, complaints, notices, notifications, flats, profile, plus SQL migrations `01`–`14` and platform manifests.
**Baseline at time of audit:** `flutter analyze` — 0 errors, 32 infos · `flutter test` — 57 passing.
**Status after the fix pass (25 Sep 2026):** `flutter analyze` — **0 issues** · `flutter test` — **78 passing**.

> This report supersedes `VEHICLES_PARKING_TEST_REPORT.md`, which is stale: most of its items were fixed before this audit. Findings below were reproduced against the current tree.

---

## Fix status

**All 26 findings are fixed**, plus three further instances of P1-13 that the
regression tests turned up (see the note under that finding).

Database changes ship as three new migrations, to run in order after `14`:

| Migration | Covers |
|---|---|
| `15_security_hardening.sql` | P0-1, P0-2, P0-3, P1-8, P2-23 |
| `16_notification_read_state.sql` | P1-7 |
| (amended) `11_vehicles_parking_module.sql` | stale-overload drop + qualified grants |

`test/security_hardening_test.dart` (21 tests) pins the fixes that are
configuration rather than logic — manifest entries, plist keys, the presence
of an authorization predicate in each `security definer` function. Those
assertions read files as text: they prove a check is present, not that it
behaves correctly under Postgres. The behavioural fixes are not covered by
tests and have not been run against a live database or a device.

---

## How to read this

Priorities are about **what breaks and for whom**, not effort:

| | Meaning |
|---|---|
| **P0** | Ship-blocker. Data can be forged, PII leaks, or the app crashes / a safety feature silently fails. |
| **P1** | Will cause real incidents or data corruption in normal use. Fix before wider rollout. |
| **P2** | Degrades correctness or UX; grows worse with scale. Schedule deliberately. |
| **P3** | Polish and hygiene. |

**Totals:** 5 × P0 · 8 × P1 · 10 × P2 · 3 × P3 = **26 findings**.

One P1 (#18) was found and **fixed during this audit** — it was introduced by the bay-request work earlier in this session. It is documented for the record.

---

## P0 — Ship-blockers

### P0-1 · `log_vehicle_entry` accepts forged gate entries from any user  ·  **FIXED**

**Where:** `supabase/11_vehicles_parking_module.sql:495`

The function is `security definer`, `granted to authenticated`, and performs **no authorization check whatsoever** before inserting:

```sql
create or replace function public.log_vehicle_entry(
  p_society_id uuid, p_plate_number text, ...
) returns jsonb language plpgsql security definer as $$
begin
  insert into public.vehicle_entry_logs (...) values (p_society_id, ...);
```

Because `security definer` bypasses RLS, **any authenticated user of any society** can write arbitrary rows into any other society's gate register — planting a false "this car entered at 02:14" record, or flooding the log.

This is the same hole that was closed in `log_vehicle_exit` (which gained an `is_guard_or_admin` check); the entry counterpart was missed.

**Fix:** add the same guard at the top:

```sql
if not public.is_guard_or_admin(p_society_id) then
  return jsonb_build_object('success', false, 'error', 'Permission denied');
end if;
```

**Note:** the gate register is an audit trail. Until this is fixed its entries are not evidence of anything.

---

### P0-2 · `verify_pre_approval` leaks visitor PII and is enumerable  ·  **FIXED**

**Where:** `supabase/09_visitors_module.sql:809`

`security definer`, no auth check, no society scoping, keyed **only** on a 6-digit approval code. It returns `visitor_name`, `visitor_phone`, `visitor_photo_url`, `vehicle_number`, plus the flat and block being visited.

The code space is 10⁶ and there is **no rate limiting**. Any authenticated user — a resident of any unrelated society — can walk the code space and harvest visitor identity data across every society on the deployment.

**Fix (all three):**
1. Require `public.is_guard_or_admin(v_visitor.society_id)` before returning anything.
2. Reject codes whose visitor is outside its validity window or already checked out.
3. Add attempt throttling (a `verify_attempts` table keyed on `auth.uid()`, or pgsodium/pg_cron cleanup) — six digits is thin even with authorization.

---

### P0-3 · `check_in_visitor` / `check_out_visitor` have no society or role check  ·  **FIXED**

**Where:** `supabase/09_visitors_module.sql:663` and `:711`

Both are `security definer` and validate only that the caller is *signed in* and that the visitor is in a permitted status. Any authenticated user can check any visitor in or out given a UUID — corrupting the gate log and the resident's visit history.

Worse, the audit row records a role the caller may not hold:

```sql
insert into public.visitor_status_history (..., changed_by_role, ...)
values (..., 'society_admin', ...);   -- hardcoded, regardless of caller
```

So the history trail actively misattributes the action.

**Fix:** gate both on `public.is_guard_or_admin(v_visitor.society_id)` and derive `changed_by_role` from the caller rather than hardcoding it. Migration `14_guard_gate_access.sql` already establishes the right predicate.

---

### P0-4 · iOS crashes when capturing a photo — missing usage descriptions  ·  **FIXED**

**Where:** `ios/Runner/Info.plist`

`image_picker` is used for visitor photos (`admin_log_visitor_screen.dart`), complaint photos, notice images and vehicle RC photos. `Info.plist` contains **neither** `NSCameraUsageDescription` **nor** `NSPhotoLibraryUsageDescription`.

iOS terminates the app on first access to a protected resource with no usage string. This is a hard crash in a core flow, and an automatic App Store rejection.

**Fix:** add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Saqiit uses the camera to capture visitor and vehicle photos at the gate.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Saqiit lets you attach photos to complaints, notices and visitor records.</string>
```

---

### P0-5 · Phone calls silently fail on Android 11+ — no `tel` in `<queries>`  ·  **FIXED**

**Where:** `android/app/src/main/AndroidManifest.xml`

Android 11 (API 30) package-visibility rules mean `canLaunchUrl(Uri(scheme: 'tel'))` returns **false** unless the app declares the intent. The manifest declares only `PROCESS_TEXT`.

Two call sites, with different failure modes:

| Call site | Behaviour on Android 11+ |
|---|---|
| `vehicle_gate_lookup_screen.dart:169` — guard calls the resident | `if (await canLaunchUrl(uri)) await launchUrl(uri);` → **nothing happens at all**, no error, no feedback |
| `security_service.dart:287` — emergency contacts / SOS | falls through to `LaunchMode.externalApplication`, which usually works but is unreliable |

The guard tapping a resident's number and getting silence is bad. The emergency-contacts path being unreliable is a **safety** issue — this is the screen someone opens during a medical or fire emergency.

**Fix:** add to the manifest's `<queries>` block, and give the guard path the same fallback the service has:

```xml
<intent>
    <action android:name="android.intent.action.DIAL" />
    <data android:scheme="tel" />
</intent>
```

Also add `LSApplicationQueriesSchemes` with `tel` to `Info.plist` for the iOS equivalent.

---

## P1 — Fix before wider rollout

### P1-6 · No deep-link intent-filter: Google sign-in and password reset can't return  ·  **FIXED**

**Where:** `android/app/src/main/AndroidManifest.xml`

`auth_screen.dart:171` calls `signInWithOAuth(OAuthProvider.google)` and `:147` calls `resetPasswordForEmail(email)`. Both hand off to a browser and rely on a redirect back into the app. The manifest has **only** the `MAIN`/`LAUNCHER` intent-filter — no custom scheme, no App Link.

Result: "Continue with Google" opens a browser the user cannot get back from, and the password-reset link lands nowhere. Both features are effectively non-functional on device.

**Fix:** register a scheme (e.g. `io.supabase.saqiit://login-callback/`), add the matching `<intent-filter>` with `BROWSABLE`, pass `redirectTo:` to both calls, and add the URL to Supabase Auth → URL Configuration.

---

### P1-7 · `is_read` is shared across users on broadcast notifications  ·  **FIXED**

**Where:** `supabase/07_notifications.sql:10`, `lib/services/notifications_service.dart:466`

`notifications` is one row per *audience*, not per user — `user_id` is nullable and `null` means "broadcast to `target_role`". But `is_read` is a single boolean **on that shared row**.

`markEntityAsRead` then writes without any user filter:

```dart
await client.from('notifications')
    .update({'is_read': true})
    .eq('entity_type', entityType)
    .eq('entity_id', entityId);      // ← no user_id / auth.uid() filter
```

The RLS policy explicitly permits updating rows where `user_id is null`, so this succeeds. **One admin opening a notification marks it read for every admin in the society.** The `_locallyReadIds` SharedPreferences cache masks this on the acting device while actively corrupting everyone else's.

**Fix:** split read-state into a `notification_reads (notification_id, user_id)` join table, or fan out one row per recipient at insert time. The client-side local cache should then be deleted, not extended.

---

### P1-8 · Approval codes are never released — the space fills permanently  ·  **FIXED**

**Where:** `supabase/09_visitors_module.sql:259`

```sql
loop
  code := lpad(floor(random() * 1000000)::text, 6, '0');
  select exists(select 1 from public.visitors where approval_code = code) into exists_already;
  if not exists_already then return code; end if;
end loop;
```

`approval_code` is `unique` **globally** (not per society), the column is never cleared when a visit expires or checks out, and rows are never purged. So the usable space monotonically shrinks across all societies on the deployment.

The failure curve is nasty: fine at 10k codes, noticeably slow at ~500k (≈2 attempts each), and at ~950k the loop runs ~20 iterations per call. Past 10⁶ it **never terminates** and the RPC hangs a connection.

**Fix:** null out `approval_code` on `checked_out` / `expired` / `cancelled`; scope uniqueness to `(society_id, approval_code)`; widen to 8 characters; and bound the loop with an attempt cap that raises rather than spins.

---

### P1-9 · Unbounded queries — visitor and complaint lists have no `LIMIT`  ·  **FIXED**

**Where:** `lib/services/visitors_service.dart`, `lib/services/complaints_service.dart`

Neither service contains a single `.limit()` call. `fetchSocietyVisitors` issues `select('*')` over **every visitor row the society has ever created**, ordered by date, with no pagination.

For a 300-flat society this is roughly 50–100k rows after two years, fetched in full onto a guard's phone every time the dashboard opens or a filter chip is tapped. Compounded by P1-10 below.

**Fix:** add `.range()` pagination with an explicit page size (50), select only the columns the list renders (**not** `visitor_photo_url` — fetch that in the detail view), and add a date-window default of ~30 days.

---

### P1-10 · Photos are stored as base64 inside Postgres text columns  ·  **FIXED**

**Where:** `lib/services/visitors_service.dart:871`

When both storage buckets fail, the uploader falls back to embedding the image in the row:

```dart
final b64 = base64Encode(bytes);
return 'data:image/$fileExtension;base64,$b64';
```

At the capture settings used (800×800, q80) that is ~80–160 KB per visitor, inflated ~33% by base64. Those bytes then live in `visitors.visitor_photo_url` and are dragged into **every** `select('*')` list query (P1-9).

This is a silent fallback, so it can be the *normal* path for months if bucket policies are misconfigured, with nothing surfacing until the table is bloated and lists take 30 s to load.

**Fix:** treat a failed upload as a failed upload — surface it, let the guard retry or log the visitor without a photo. If an offline queue is wanted, persist bytes to local storage and sync later; never to a text column.

---

### P1-11 · Two code paths write vehicles, and they disagree  ·  **FIXED**

**Where:** `lib/screens/profile_screen.dart:938`

The profile screen inserts into `vehicles` directly rather than going through `VehiclesParkingService.registerVehicle`, and gets two things wrong:

```dart
'vehicle_number': reg,          // only .toUpperCase() — separators NOT stripped
'type': 'four_wheeler',         // hardcoded
```

1. **Every vehicle added from the profile screen is recorded as a car.** A resident registering a scooter gets a `four_wheeler` row, which then drives 2W-vs-4W bay eligibility.
2. **The plate is not normalized.** `"MH 12 AB 1234"` is stored with spaces here, but `normalizePlate()` (used by the gate lookup and the vehicles module) strips them. The gate's `lookup_vehicle_by_plate` does normalize both sides, so lookup survives — but the unique constraint `(society_id, vehicle_number)` does **not**, so the same car can be registered twice in two spellings.

It also skips the duplicate check and validation in the service entirely.

**Fix:** delete the direct insert; call `VehiclesParkingService.registerVehicle` with a real vehicle-type picker.

---

### P1-12 · The guard role is still unreachable from the app shell  ·  **FIXED**

**Where:** `lib/screens/main_shell.dart:29`, `lib/screens/home_screen.dart:54`

`AppSession.isGuard` now exists and both module root screens honour it, but the shell above them does not:

- `MainShell` branches only on `isAdmin`, so a guard gets **Home · Notices · My Flat · Settings** — "My Flat" being meaningless for someone with no flat.
- `_servicesFor(bool isAdmin)` has two tile sets, resident and admin. A guard receives the resident set: "My Flat", "Raise a complaint", "Pre-approve a visitor".

So a guard can reach the gate screens only by landing on the resident Visitors/Vehicles tiles and being redirected. There is no gate-first home.

**Fix:** add a third branch — a guard home whose primary actions are *Gate check (plate)*, *Log visitor*, *Verify pre-approval*, *Emergency contacts* — and a matching `MainShell` nav.

---

### P1-13 · Failed block creation invents a phantom block  ·  **FIXED**

**Where:** `lib/screens/flats_management_screen.dart:505`

If the `blocks` insert fails, the dialog shows the error and then **adds the block to local state anyway**:

```dart
// Fallback local memory
setState(() {
  if (!_blocks.contains(name)) { _blocks.add(name); _blocks.sort(); }
  _selectedBlock = name;
});
```

The admin now sees "Tower C" in the UI, selects it, and adds flats to a block that does not exist in the database. Those flats either fail to save or save with a dangling `block_id`.

**Fix:** on failure, show the error and leave state untouched.

**During the fix pass the regression test found three more instances of this
in the same file, worse than the one recorded above** — flat add, flat edit
and flat delete each showed the error snackbar and *then* fell through to
mutate local state and show a **success** snackbar. So an admin saw "Flat 302
details updated" immediately after "Failed to update flat in database", and a
failed delete removed the flat from their view while it still existed. All
four now return after the error.

*(Same class as the sample-data fallbacks removed from `VehiclesParkingService` earlier in this session. The grep this suggested is what caught the extra three.)*

---

## P2 — Correctness and scale

### P2-14 · Notification read-state resets on every status change  ·  **FIXED**

**Where:** `lib/services/notifications_service.dart:289,371,415`

Synthesized notification IDs embed the entity's **current status**:

```dart
id: 'v_res_${id}_$status',
```

When a visitor moves `pending_approval` → `approved`, the ID changes, so the entry marked read under the old ID reappears as unread. The unread badge therefore re-lights on every transition of every entity.

`_locallyReadIds` also accumulates every ID ever seen, is never pruned, and is JSON-decoded from SharedPreferences on each app start.

**Fix:** key on `entityType:entityId` and carry status as a field; prune the read-set against the retention window.

---

### P2-15 · Notification fetch runs 4–6 queries and is now triggered by realtime  ·  **FIXED**

**Where:** `lib/services/notifications_service.dart:69`

`fetchNotifications()` queries `notifications`, then synthesizes from `complaints`, `resident_join_requests` and `visitors`, then issues a reconciliation query against `visitors` — 4–6 round trips, with client-side dedup.

Since the realtime work added earlier in this session, `main.dart` calls it on **every** visitor approval event. A busy gate now triggers repeated multi-query fetches.

**Fix:** debounce the realtime-triggered refresh (~2 s), and retire the synthesis path now that DB triggers populate `notifications` directly — it was scaffolding for pre-migration installs.

---

### P2-16 · Two `TextEditingController` leaks  ·  **FIXED**

**Where:** `lib/screens/complaints/resident_complaint_detail_screen.dart:110` · `lib/screens/flats_management_screen.dart:457`

Both are created inside a method that shows a dialog and are never disposed. Each invocation leaks a controller and its listeners. Minor per instance, but these are repeatable user actions.

**Fix:** dispose after the `showDialog` future completes (the pattern already used in `admin_vehicles_parking_dashboard._declineRequest`).

---

### P2-17 · `Navigator.pop(context)` followed by `ScaffoldMessenger.of(context)`  ·  **FIXED**

**Where:** ~10 files, including `sos_dialog.dart:77`, `gate_approval_modal.dart:421,463`, `allocate_slot_dialog.dart:288`, `bulk_add_slots_dialog.dart:96`, `parking_policy_dialog.dart:63`, `create_edit_notice_screen.dart:384`, `profile_screen.dart:1126`, `admin_log_visitor_screen.dart:868`

Looking up `ScaffoldMessenger` from a context whose route was just popped. It usually works — the element survives the frame — but it is order-dependent and throws if the widget is disposed first. In `sos_dialog` that means **the emergency confirmation snackbar is the one that can go missing.**

**Fix:** capture `final messenger = ScaffoldMessenger.of(context);` *before* the await/pop, then call `messenger.showSnackBar(...)`.

---

### P2-18 · Bay-request notification violated its check constraint  ·  **FIXED**

**Where:** `lib/screens/vehicles/resident/request_bay_sheet.dart:145`

The insert used `'type': 'alert'`, which is **not** in `notifications_type_check` (last set in `supabase/10_security_emergency_module.sql:307`). Every insert failed. The call was wrapped in `try/catch` so the request itself still saved — the admin's nudge simply never arrived, silently.

Introduced by the bay-request feature earlier in this session; logged here because the same trap applies to any new notification type.

**Fixed:** switched to `'parking_bay_request'`, added that value (plus `parking_bay_approved` / `parking_bay_rejected`) to the constraint in `supabase/12_parking_bay_requests.sql`, and added a `'general'` retry for databases predating that migration.

---

### P2-19 · Auth loading state is cleared on a timer  ·  **FIXED**

**Where:** `lib/screens/auth_screen.dart:88`

```dart
} finally {
  if (mounted && _loading) {
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _loading) setState(() => _loading = false);
    });
  }
}
```

On success the spinner is cleared by a fixed 1.4 s delay rather than by the auth state actually changing. On a slow connection the spinner vanishes while the user is still on the login screen with no indication of what happened; on a fast one it spins 1.4 s longer than needed.

**Fix:** clear `_loading` when `onAuthStateChange` fires, or immediately on the success path.

---

### P2-20 · Google sign-in reports success the moment the browser opens  ·  **FIXED**

**Where:** `lib/screens/auth_screen.dart:168`

`signInWithOAuth` returns as soon as the external browser is launched, but `finally` immediately clears `_loading`. The UI looks idle while the user is still mid-OAuth, and a cancelled flow is indistinguishable from one never started.

**Fix:** keep a pending state until `onAuthStateChange` resolves or the app is resumed without a session.

---

### P2-21 · Block filter fabricates "Tower A / Tower B"  ·  **FIXED**

**Where:** `lib/screens/vehicles/admin/admin_vehicles_parking_dashboard.dart:958`

```dart
if (blocks.isEmpty) ...const [
  DropdownMenuItem(value: 'Tower A', child: Text('Tower A')),
  DropdownMenuItem(value: 'Tower B', child: Text('Tower B')),
],
```

A society with no blocks configured is shown two invented options that match nothing, so selecting one silently empties the bay list.

**Fix:** show "No blocks configured" and disable the control.

---

### P2-22 · PostgREST filter built by string interpolation  ·  **FIXED**

**Where:** `lib/services/security_service.dart:45,137`

```dart
.or('is_global.eq.true,society_id.eq.$societyId')
```

`societyId` is a server-issued UUID today, so this is not currently exploitable — but it is a filter-**injection** shape: a value containing `,` or `.` would alter the predicate. An empty string produces the malformed `society_id.eq.`.

**Fix:** use two chained filters or `.or()` with properly quoted values, and guard against empty input.

---

### P2-23 · SOS has no cooldown or duplicate suppression  ·  **FIXED**

**Where:** `supabase/10_security_emergency_module.sql:326`

`raise_sos_alert` correctly verifies the caller is an active resident of the flat, but nothing prevents a second, third or tenth alert. A panicking resident tapping repeatedly creates a row and an admin notification each time, burying the original.

**Fix:** if the flat already has an `active` alert of the same type within ~5 minutes, return that alert's id instead of inserting.

---

## P3 — Polish

### P3-24 · Android launcher name is the package slug  ·  **FIXED**

`android/app/src/main/AndroidManifest.xml` has `android:label="society_management"`; iOS has `CFBundleDisplayName` = "Society Management". Android users see the raw slug under the icon.

### P3-25 · OTP length check can overcount  ·  **FIXED**

`lib/screens/otp_screen.dart:71` — `_code` joins all six controller texts; paste handling can leave more than one character in a field, so `_code.length == _codeLength` is not strictly "six digits entered". Harmless today because input is digit-filtered and width-capped.

### P3-26 · Analyzer infos (was 32)  ·  **FIXED**

Mostly `deprecated_member_use` (`activeColor`, Radio `groupValue`/`onChanged`, `value` → `initialValue`) and `unnecessary_underscores`. None affect behaviour; they will become errors on a future Flutter major.

---

## Deployment order

The code is committed; the database is not. **Run the migrations in order and
stop on the first error:**

```
11_vehicles_parking_module.sql   (re-run — amended: drops stale overloads,
                                  qualifies grants)
12_parking_bay_requests.sql
13_realtime_approvals.sql
14_guard_gate_access.sql
15_security_hardening.sql        (new — the P0 fixes)
16_notification_read_state.sql   (new)
```

All six are idempotent. `13` needs Realtime enabled on the project
(**Database → Replication**) or it reports success while silently skipping.

Then, in the Supabase dashboard:

1. **Authentication → URL Configuration** — add
   `io.supabase.saqiit://login-callback/` as a redirect URL, or P1-6 stays
   broken regardless of the manifest changes.
2. Confirm the `visitor-photos` storage bucket exists and accepts uploads.
   Now that the base64 fallback is gone (P1-10), a misconfigured bucket means
   visitors save **without** a photo instead of silently bloating the table.

Finally, verify no unguarded `security definer` function remains — this is the
standing check worth adding to review, since P0-1/2/3 all shared that one
shape:

```sql
select p.oid::regprocedure as fn
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef
   and has_function_privilege('authenticated', p.oid, 'EXECUTE')
 order by 1;
```

Every row should be one you can point at an authorization check inside.

---

## Two things worth deciding, not just fixing

**Silent fallbacks are the dominant bug pattern in this codebase.** P0-5, P1-10, P1-13, P2-18, the sample-data fallbacks removed earlier, the phantom blocks, the `catch (_) {}` around notification inserts — all share one shape: *when something fails, invent a plausible substitute and continue.* Each looks defensive in isolation. Collectively they mean a misconfigured deployment looks healthy while writing corrupt data. The `catch (_) {}` count across `lib/services/` is 20+. Worth a team position on when a failure is allowed to be swallowed.

**The guard persona was half-built.** It is now wired end to end — `isGuard`
in `AppSession`, a gate-first home and bottom nav, and RLS in migration 14 —
but the underlying product question stands, so the original note is kept below.

**The guard persona is half-built.** `is_guard_or_admin()` exists in SQL, `AppSession.isGuard` exists in Dart, the gate screens exist — but there is no guard user table, no way to create a guard account in-app, no guard home, and (before migration 14) no guard RLS on `visitors`. Right now gate staff must sign in as society admins, which gives them full administrative access to flats, residents and approvals. That is a larger security exposure than several of the P0s above, but it is a product decision rather than a bug, so it is recorded here rather than ranked.

---

## Verification

Everything above was reproduced by reading the current tree; nothing was carried over from the earlier report unverified.

After the fix pass:

```
flutter analyze  → No issues found!   (was 0 errors, 32 infos)
flutter test     → 78 passing         (was 57)
```

**What that does and does not establish.** The build is clean and the suite is
green, and the tests pin the configuration-shaped fixes. Nothing here has been
run against a live Supabase instance or a physical device, so the three new
migrations are unexecuted SQL and the platform fixes (P0-4, P0-5, P1-6) are
unverified on hardware. Those three in particular want a manual check:

- iOS: take a visitor photo — it should prompt, not terminate.
- Android 11+: tap a resident's number from the gate screen — the dialer
  should open.
- Both: "Continue with Google" and a password-reset link should return to
  the app rather than stranding the user in a browser.
