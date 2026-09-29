import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the security properties migrations 17 and 18 exist for.
///
/// Like security_hardening_test.dart these read the migrations as text:
/// they prove each check is present, not that Postgres runs it. The bugs
/// they pin down were all of the "check missing entirely" kind.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Body of the named function, from its `create` line to the closing `$$;`.
  String fnBody(String sql, String name) {
    final start = RegExp(
      'create (or replace )?function public\\.$name\\(',
    ).firstMatch(sql);
    expect(start, isNotNull, reason: '$name is not defined');
    final rest = sql.substring(start!.start);
    return rest.substring(0, rest.indexOf(r'$$;'));
  }

  group('17 — guard identity comes from a table, not user metadata', () {
    late String sql;
    setUpAll(() => sql = read('supabase/17_guard_identity.sql'));

    test('is_guard_or_admin no longer trusts user_metadata', () {
      final body = fnBody(sql, 'is_guard_or_admin');
      expect(
        body,
        isNot(contains('user_metadata')),
        reason: 'every user can rewrite their own user_metadata',
      );
      expect(body, isNot(contains('auth.jwt()')));
      expect(body, contains('public.is_society_guard(p_society_id)'));
    });

    test('is_society_guard requires an active row for this caller', () {
      final body = fnBody(sql, 'is_society_guard');
      expect(body, contains('g.user_id = auth.uid()'));
      expect(body, contains("g.status = 'active'"));
      expect(body, contains('g.society_id = p_society_id'));
    });

    test('only admins may write society_guards', () {
      final guardsPolicies = RegExp(
        r'create policy "[^"]+" on public\.society_guards\s+for (\w+)',
      ).allMatches(sql).map((m) => m.group(1)).toList();
      // one admin "all" policy, one self-select — nothing else.
      expect(guardsPolicies, unorderedEquals(['all', 'select']));

      final own = sql.substring(
        sql.indexOf('create policy "guards_select_own"'),
      );
      expect(own.substring(0, own.indexOf(';')), contains('for select'));
    });

    test('user_id is never taken from an API client', () {
      final body = fnBody(sql, 'society_guards_before_write');
      // current_user inside a security-definer function is the owner, so
      // it cannot distinguish API callers — the JWT role claim can.
      expect(body, contains('request.jwt.claims'));
      expect(body, isNot(contains('current_user in')));
      expect(body, contains('new.user_id := old.user_id'));
    });

    test('guard linking can never block a signup', () {
      final body = fnBody(sql, 'link_guard_on_signup');
      expect(body, contains('exception when others'));
    });

    test(
      'lookup_vehicle_by_plate authorizes and withholds phones from guards',
      () {
        final body = fnBody(sql, 'lookup_vehicle_by_plate');
        expect(body, contains('public.is_guard_or_admin(p_society_id)'));
        expect(body, contains('Permission denied'));
        expect(
          body,
          contains(
            "'resident_phone', case when v_is_admin then r.phone else null end",
          ),
        );
      },
    );

    test(
      'create_visitor_entry authorizes, scopes the flat and attributes honestly',
      () {
        final body = fnBody(sql, 'create_visitor_entry');
        expect(body, contains('public.is_guard_or_admin(p_society_id)'));
        expect(
          body,
          contains('b.society_id = p_society_id'),
          reason: 'a guard must not ring flats of another society',
        );
        expect(body, contains('public.caller_gate_role(p_society_id)'));
        expect(
          body.contains("'society_admin', v_caller_id"),
          isFalse,
          reason: 'created_by_type must be derived, not hardcoded',
        );
      },
    );

    test('rewritten functions drop their stale overloads first', () {
      final drop = sql.substring(sql.indexOf('6) DROP STALE OVERLOADS'));
      expect(drop, contains("'lookup_vehicle_by_plate'"));
      expect(drop, contains("'create_visitor_entry'"));
      expect(drop, contains('regprocedure'));
    });
  });

  group('18 — guard panel', () {
    late String sql;
    setUpAll(() => sql = read('supabase/18_guard_panel.sql'));

    test('a phone decision needs a call the guard actually logged', () {
      final body = fnBody(sql, 'guard_resolve_gate_request');
      expect(body, contains('public.is_guard_or_admin(v_visitor.society_id)'));
      expect(body, contains('from public.guard_call_logs l'));
      expect(body, contains('l.caller_id = v_caller'));
      expect(body, contains("approved_via = 'guard_call'"));
      expect(body, contains("v_visitor.status <> 'pending_approval'"));
    });

    test('calling a flat is authorized, logged and throttled', () {
      final body = fnBody(sql, 'guard_call_flat');
      expect(body, contains('public.is_guard_or_admin(v_society_id)'));
      expect(body, contains('insert into public.guard_call_logs'));
      expect(body, contains('v_recent >= 20'));
    });

    test('the expected-visitors list carries no pass codes', () {
      final body = fnBody(sql, 'fetch_expected_visitors');
      expect(body, contains('public.is_guard_or_admin(p_society_id)'));
      expect(body, isNot(contains('approval_code')));
      expect(body, isNot(contains('qr_payload')));
    });

    test('the gate SOS feed names the resident without their phone', () {
      final body = fnBody(sql, 'fetch_gate_sos_alerts');
      expect(body, contains('public.is_guard_or_admin(p_society_id)'));
      expect(body, contains("'full_name', r.full_name"));
      expect(body, isNot(contains('phone')));
    });

    test('guards can acknowledge and resolve SOS, with honest roles', () {
      for (final name in ['acknowledge_sos_alert', 'resolve_sos_alert']) {
        final body = fnBody(sql, name);
        expect(
          body,
          contains('public.is_guard_or_admin(v_alert.society_id)'),
          reason: name,
        );
        expect(body, contains('public.caller_gate_role'), reason: name);
      }
    });

    test('raise_sos_alert notifies guards and survives the dedup trigger', () {
      final body = fnBody(sql, 'raise_sos_alert');
      expect(body, contains("'guard'"));
      expect(
        body,
        contains('if v_alert_id is null then'),
        reason: 'fn_sos_dedup_guard returns NULL; the next insert used to fail',
      );
    });

    test('guards lose the direct UPDATE on visitors', () {
      expect(
        sql,
        contains('drop policy if exists "guard check in out visitor"'),
      );
      expect(
        sql,
        isNot(contains('create policy "guard check in out visitor"')),
      );
    });

    test('guards cannot forge someone else\'s role into visitor history', () {
      final p = sql.substring(
        sql.indexOf('create policy "guard append visitor_status_history"'),
      );
      final policy = p.substring(0, p.indexOf(');') + 2);
      expect(policy, contains("changed_by_role = 'guard'"));
      expect(policy, contains('changed_by = auth.uid()'));
    });

    test('guard visitor access is limited to recent and live rows', () {
      final p = sql.substring(
        sql.indexOf('create policy "guard read society visitors"'),
      );
      final policy = p.substring(0, p.indexOf(');') + 2);
      expect(policy, contains("interval '7 days'"));
      expect(policy, contains('public.is_society_guard(society_id)'));
    });
  });

  group('every new security-definer RPC checks its caller', () {
    for (final path in [
      'supabase/17_guard_identity.sql',
      'supabase/18_guard_panel.sql',
    ]) {
      test(path, () {
        final sql = read(path);
        final fns = RegExp(
          r'create (?:or replace )?function public\.(\w+)\(([\s\S]*?)\$\$;',
        ).allMatches(sql);
        expect(fns, isNotEmpty);
        for (final m in fns) {
          final name = m.group(1)!;
          final text = m.group(0)!;
          if (!text.contains('security definer')) continue;
          if (text.contains('returns trigger')) continue;
          if (text.contains('returns boolean') ||
              text.contains('returns text')) {
            continue; // predicates/helpers: they only ever describe the caller
          }
          expect(
            text.contains('is_guard_or_admin') ||
                RegExp(r'(auth\.uid\(\)|v_caller\w*) is null').hasMatch(text),
            isTrue,
            reason: '$name is security definer but never checks who is calling',
          );
        }
      });

      test('$path grants name their argument lists', () {
        final sql = read(path);
        final grants = RegExp(
          r'grant execute on function public\.(\w+)([^;]*);',
        ).allMatches(sql);
        expect(grants, isNotEmpty);
        for (final g in grants) {
          expect(
            g.group(2),
            contains('('),
            reason:
                'bare grant on ${g.group(1)} breaks if it is ever overloaded',
          );
        }
      });
    }
  });

  // Regression: 17/18 called caller_gate_role(), which only migration 15
  // created. A database that skipped 15 failed "Acknowledge" (and logging a
  // walk-in) with 42883 "function ... does not exist".
  test('17 and 18 only call functions that exist without 14–16', () {
    // Match on the file name (from the URI) so the path separator does not
    // matter on Windows.
    final numbered = RegExp(r'^(\d\d)_.*\.sql$');
    String name(File f) => f.uri.pathSegments.last;
    final files = Directory('supabase')
        .listSync()
        .whereType<File>()
        .where((f) => numbered.hasMatch(name(f)))
        .toList();
    expect(files.length, greaterThan(15), reason: 'migrations not found');
    int number(File f) => int.parse(numbered.firstMatch(name(f))!.group(1)!);

    final fnDef = RegExp(r'create (?:or replace )?function public\.(\w+)\(');
    // Tables created by a migration, or pre-existing ones a migration points
    // a foreign key at (societies, flats) — `public.flats(id)` is not a call.
    final tableDef = RegExp(
        r'(?:create table (?:if not exists )?|references )public\.(\w+)');

    final core = <String>{}; // functions from migrations 01–13
    final tables = <String>{};
    for (final f in files) {
      final sql = f.readAsStringSync();
      tables.addAll(tableDef.allMatches(sql).map((m) => m.group(1)!));
      if (number(f) <= 13) core.addAll(fnDef.allMatches(sql).map((m) => m.group(1)!));
    }

    final guardSql = read('supabase/17_guard_identity.sql') +
        read('supabase/18_guard_panel.sql');
    final own = fnDef.allMatches(guardSql).map((m) => m.group(1)!).toSet();
    final called = RegExp(r'public\.(\w+)\(')
        .allMatches(guardSql)
        .map((m) => m.group(1)!)
        .where((name) => !tables.contains(name))
        .toSet();

    final missing = called.difference(own).difference(core);
    expect(missing, isEmpty,
        reason: 'called by 17/18 but only defined in migrations 14–16: $missing');
  });

  group('app side', () {
    test('AppSession no longer reads the guard role from user metadata', () {
      final src = read('lib/services/app_session.dart');
      expect(src, isNot(contains("meta['role']")));
      expect(src, contains("from('society_guards')"));
    });

    test('visitor RPC refusals are not retried as direct writes', () {
      final src = read('lib/services/visitors_service.dart');
      expect(src, contains('_isMissingRpc'));
      expect(
        src,
        isNot(contains("'changed_by_role': 'society_admin'")),
        reason: 'the fallback must record the real gate role',
      );
    });
  });
}
