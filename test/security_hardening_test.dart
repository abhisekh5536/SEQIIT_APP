import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against the shapes of bug this audit round fixed.
///
/// These read the migration and manifest files as text rather than talking to
/// Postgres or a device. That is a real limit — they prove the statement is
/// present, not that it behaves — but the defects here were all "the check is
/// missing entirely", which is exactly what a text assertion catches.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('SECURITY DEFINER functions carry an authorization check', () {
    late String sql;

    setUpAll(() => sql = read('supabase/15_security_hardening.sql'));

    test('log_vehicle_entry checks is_guard_or_admin', () {
      final fn = sql.substring(sql.indexOf('create function public.log_vehicle_entry'));
      final body = fn.substring(0, fn.indexOf(r'$$;'));
      expect(body, contains('public.is_guard_or_admin(p_society_id)'));
      expect(body, contains('Permission denied'));
    });

    test('verify_pre_approval authorizes, scopes and throttles', () {
      final fn = sql.substring(sql.indexOf('create function public.verify_pre_approval'));
      final body = fn.substring(0, fn.indexOf(r'$$;'));
      expect(body, contains('public.is_guard_or_admin(v_visitor.society_id)'));
      expect(body, contains('pre_approval_verify_attempts'),
          reason: 'failed attempts must be recorded for rate limiting');
      expect(body, contains('v_recent_failures >= 10'));
    });

    test('check_in_visitor and check_out_visitor authorize by society', () {
      for (final name in ['check_in_visitor', 'check_out_visitor']) {
        final fn = sql.substring(sql.indexOf('create function public.$name'));
        final body = fn.substring(0, fn.indexOf(r'$$;'));
        expect(body, contains('public.is_guard_or_admin(v_visitor.society_id)'),
            reason: '$name must not accept any signed-in caller');
      }
    });

    test('gate history records the caller\'s real role, not a hardcoded one',
        () {
      final fn = sql.substring(sql.indexOf('create function public.check_in_visitor'));
      final body = fn.substring(0, fn.indexOf(r'$$;'));
      expect(body, contains('public.caller_gate_role'));
      expect(
        body.contains("'society_admin',\n    'Checked in'"),
        isFalse,
        reason: 'changed_by_role must be derived, not asserted',
      );
    });

    test('signature changes drop stale overloads first', () {
      // A `create or replace` with a changed signature adds a second
      // function instead of replacing — which is how an unguarded
      // log_vehicle_exit(uuid) once survived its own fix.
      expect(sql, contains('drop function if exists'));
      expect(sql, contains('regprocedure'));
    });

    test('grants name their argument lists', () {
      final grants = RegExp(r'grant execute on function public\.(\w+)([^;]*);')
          .allMatches(sql);
      expect(grants, isNotEmpty);
      for (final g in grants) {
        expect(g.group(2), contains('('),
            reason: 'bare grant on ${g.group(1)} breaks if it is ever overloaded');
      }
    });
  });

  group('approval codes are not exhaustible', () {
    late String sql;
    setUpAll(() => sql = read('supabase/15_security_hardening.sql'));

    test('codes are released on terminal statuses', () {
      expect(sql, contains('set approval_code = null'));
      expect(sql, contains("status in ('checked_out', 'expired', 'cancelled', 'denied')"));
    });

    test('the generator loop is bounded rather than spinning forever', () {
      expect(sql, contains('v_attempts >= 50'));
      expect(sql, contains('raise exception'));
    });

    test('the alphabet omits easily-misread characters', () {
      final m = RegExp(r"v_alphabet text := '([^']+)'").firstMatch(sql);
      expect(m, isNotNull);
      final alphabet = m!.group(1)!;
      for (final c in ['I', 'L', 'O', 'U']) {
        expect(alphabet.contains(c), isFalse,
            reason: '$c is misread when a guard keys in a code');
      }
      expect(alphabet.length, greaterThan(30));
    });
  });

  group('per-user notification read state', () {
    late String sql;
    setUpAll(() => sql = read('supabase/16_notification_read_state.sql'));

    test('read markers live in their own table keyed by user', () {
      expect(sql, contains('create table if not exists public.notification_reads'));
      expect(sql, contains('primary key (notification_id, user_id)'));
    });

    test('a marker is private to the user who made it', () {
      expect(sql, contains('using (user_id = auth.uid())'));
    });

    test('nobody can flip is_read on a broadcast row any more', () {
      // The old UPDATE policies allowed `user_id is null`, which is what let
      // one admin mark a notification read for the whole society. Scope the
      // check to the policy block — `user_id is null` is still legitimate
      // further down, where mark_all picks which rows to mark.
      final start = sql.indexOf('3) STOP THE BLEEDING');
      final end = sql.indexOf('4) RPCs');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final policies = sql.substring(start, end);

      expect(policies.contains('user_id is null'), isFalse);
      expect(
        'user_id = auth.uid()'.allMatches(policies).length,
        greaterThanOrEqualTo(4),
        reason: 'both admin and resident update policies must be scoped',
      );
    });
  });

  group('platform configuration', () {
    test('iOS declares camera and photo usage, or image_picker crashes', () {
      final plist = read('ios/Runner/Info.plist');
      expect(plist, contains('NSCameraUsageDescription'));
      expect(plist, contains('NSPhotoLibraryUsageDescription'));
    });

    test('iOS can query the tel scheme', () {
      final plist = read('ios/Runner/Info.plist');
      expect(plist, contains('LSApplicationQueriesSchemes'));
      expect(plist, contains('<string>tel</string>'));
    });

    test('Android declares the tel intent for package visibility', () {
      // Without this, canLaunchUrl('tel:') returns false on API 30+ and the
      // guard's call button silently does nothing.
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final queries = manifest.substring(manifest.indexOf('<queries>'));
      expect(queries, contains('android.intent.action.DIAL'));
      expect(queries, contains('android:scheme="tel"'));
    });

    test('both platforms register the same auth callback scheme', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final plist = read('ios/Runner/Info.plist');
      const scheme = 'io.supabase.saqiit';

      expect(manifest, contains('android:scheme="$scheme"'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
      expect(plist, contains('<string>$scheme</string>'));

      final dart = read('lib/screens/auth_screen.dart');
      expect(dart, contains("'$scheme://login-callback/'"));
      expect(dart, contains('emailRedirectTo:'));
      expect(dart, contains('redirectTo:'));
    });

    test('the launcher shows a product name, not the package slug', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest.contains('android:label="society_management"'), isFalse);
    });
  });

  group('no fabricated data stands in for a failed call', () {
    test('visitor photos are never base64-encoded into a text column', () {
      final src = read('lib/services/visitors_service.dart');
      expect(src.contains('base64Encode'), isFalse,
          reason: 'images in visitor_photo_url bloat every list query');
    });

    test('list queries are bounded', () {
      for (final f in [
        'lib/services/visitors_service.dart',
        'lib/services/complaints_service.dart',
      ]) {
        expect(read(f), contains('.range(offset, offset + limit - 1)'),
            reason: '$f fetched every row the society had ever created');
      }
    });

    test('a failed flat or block write does not invent local state', () {
      final src = read('lib/screens/flats_management_screen.dart');

      // Keying only on the old comment text made this pass as soon as the
      // comment was reworded. Assert on the control flow instead: each DB
      // catch block must stop, because falling through used to mutate local
      // state AND show a success snackbar right after the error.
      expect(src.contains('// Fallback local memory'), isFalse);

      const catches = [
        "debugPrint('Error updating flat in DB",
        "debugPrint('Error deleting flat from DB",
        "debugPrint('Error creating flat in DB",
      ];
      for (final marker in catches) {
        final at = src.indexOf(marker);
        expect(at, greaterThan(-1), reason: 'missing handler: $marker');

        // The handler shows an error then must return before any setState.
        final tail = src.substring(at, at + 700);
        final returnAt = tail.indexOf('return;');
        final setStateAt = tail.indexOf('setState(');
        expect(returnAt, greaterThan(-1),
            reason: '$marker must return after reporting the failure');
        expect(returnAt, lessThan(setStateAt == -1 ? 1 << 30 : setStateAt),
            reason: '$marker reached setState after a failed write');
      }

      // Block creation has no local path at all, so there is nothing to
      // return past — assert the fallback body is genuinely gone.
      final blockCatch = src.indexOf("debugPrint('Error creating block in DB");
      expect(blockCatch, greaterThan(-1));
      expect(src.substring(blockCatch, blockCatch + 900),
          contains('No local fallback on purpose'));
    });

    test('the block filter offers exactly one item valued All', () {
      // Two DropdownMenuItems sharing the current value throws
      // "There should be exactly one item with [DropdownButton]'s value".
      final src =
          read('lib/screens/vehicles/admin/admin_vehicles_parking_dashboard.dart');
      expect("value: 'All'".allMatches(src).length, 1);
      expect(src.contains("value: 'Tower A'"), isFalse,
          reason: 'invented blocks matched nothing and emptied the bay list');
    });

    test('OAuth clears its pending state when the user comes back', () {
      // Clearing the spinner as soon as signInWithOAuth returned made a
      // cancelled sign-in look idle; clearing it never left the spinner
      // turning forever. The lifecycle callback is what resolves it.
      final src = read('lib/screens/auth_screen.dart');
      expect(src, contains('WidgetsBindingObserver'));
      expect(src, contains('didChangeAppLifecycleState'));
      expect(src, contains('AppLifecycleState.resumed'));
      expect(src, contains('WidgetsBinding.instance.addObserver(this)'));
      expect(src, contains('WidgetsBinding.instance.removeObserver(this)'),
          reason: 'an unremoved observer outlives the route');

      final cb = src.substring(src.indexOf('didChangeAppLifecycleState'));
      final body = cb.substring(0, cb.indexOf('@override'));
      expect(body, contains('currentSession'),
          reason: 'must distinguish a completed sign-in from a cancelled one');
      expect(body, contains('_loading = false'));
    });

    test('the profile screen registers vehicles through the service', () {
      final src = read('lib/screens/profile_screen.dart');
      expect(src, contains('VehiclesParkingService.instance.registerVehicle'));
      expect(src.contains("'type': 'four_wheeler'"), isFalse,
          reason: 'every vehicle added here used to be recorded as a car');
    });
  });
}
