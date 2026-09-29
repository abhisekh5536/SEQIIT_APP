import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the security properties migration 20 exists for.
///
/// Like guard_panel_sql_test.dart these read the migrations as text: they
/// prove each check is present, not that Postgres runs it. The live check
/// is supabase/check_resident_documents_access.sql, run on staging.
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

  /// The text of one `create policy "<name>" ... ;`.
  String policy(String sql, String name) {
    final p = sql.substring(sql.indexOf('create policy "$name"'));
    return p.substring(0, p.indexOf(');') + 2);
  }

  final numbered = RegExp(r'^(\d\d)_.*\.sql$');
  String fileName(File f) => f.uri.pathSegments.last;
  List<File> migrations() => Directory('supabase')
      .listSync()
      .whereType<File>()
      .where((f) => numbered.hasMatch(fileName(f)))
      .toList();

  const path = 'supabase/20_resident_documents.sql';
  late String sql;
  setUpAll(() => sql = read(path));

  group('P0 fixes', () {
    test('every definition of is_society_admin requires an active admin', () {
      // Re-running an older migration must not bring the hole back.
      final defs = <String>[];
      for (final f in migrations()) {
        final text = f.readAsStringSync();
        if (!text.contains('function public.is_society_admin(')) continue;
        defs.add(fileName(f));
        expect(
          fnBody(text, 'is_society_admin'),
          contains("a.status = 'active'"),
          reason:
              '${fileName(f)} defines is_society_admin without the status check',
        );
      }
      expect(
        defs,
        containsAll([
          '01_residents_migration.sql',
          '20_resident_documents.sql',
        ]),
      );
    });

    test('an API caller cannot re-point a resident row at someone else', () {
      final body = fnBody(sql, 'residents_before_write');
      expect(body, contains('request.jwt.claims'));
      for (final col in [
        'user_id',
        'flat_id',
        'society_id',
        'created_by',
        'resident_type',
        'is_primary',
      ]) {
        expect(
          RegExp('new\\.$col\\s+:= old\\.$col;').hasMatch(body),
          isTrue,
          reason: col,
        );
      }
      // On insert user_id is resolved by email, never taken from the client.
      expect(body, contains('new.user_id := null'));
      expect(body, contains('new.created_by := auth.uid()'));
      expect(
        'trg_residents_before_write'.compareTo('trg_residents_link_on_insert'),
        lessThan(0),
        reason: 'must fire before the email-linking trigger',
      );
    });

    test('household edit rights end when the creator leaves the flat', () {
      for (final file in [path, 'supabase/04_profile_self_service.sql']) {
        final text = read(file);
        for (final name in [
          'residents_update_household',
          'residents_delete_household',
        ]) {
          expect(
            policy(text, name),
            contains('public.lives_in_flat(flat_id)'),
            reason: '$name in $file',
          );
        }
      }
    });
  });

  group('storage', () {
    test('the bucket is private with type and size limits', () {
      final insert = sql.substring(sql.indexOf('insert into storage.buckets'));
      final stmt = insert.substring(0, insert.indexOf(';'));
      expect(
        stmt,
        contains("'resident-documents', 'resident-documents', false"),
      );
      expect(stmt, contains('10485760'));
      expect(stmt, contains("'application/pdf'"));
      expect(stmt, contains('set public = false'));
    });

    test(
      'only insert and select policies — files are never updated or deleted by users',
      () {
        final storagePolicies = RegExp(
          r'create policy "([^"]+)"\s+on storage\.objects for (\w+)',
        ).allMatches(sql).map((m) => m.group(2)).toList();
        expect(storagePolicies, unorderedEquals(['insert', 'select']));
      },
    );

    test('no storage policy in any migration forgets bucket_id', () {
      // Policies are OR'd: one without bucket_id would open this bucket.
      final re = RegExp(
        r'create policy "[^"]+"\s+on storage\.objects[\s\S]*?;',
      );
      for (final f in migrations()) {
        for (final m in re.allMatches(f.readAsStringSync())) {
          expect(m.group(0), contains('bucket_id'), reason: fileName(f));
        }
      }
    });

    test(
      'a file can only be read after a logged open, and never signed or copied',
      () {
        final body = fnBody(sql, 'can_read_document_file');
        expect(body, contains("l.action = 'view'"));
        expect(body, contains('l.actor_id = auth.uid()'));
        expect(body, contains("interval '10 minutes'"));
        expect(body, contains("'open'"));
        expect(body, contains('storage.operation'));
        expect(body, contains('sign|copy|move'));
      },
    );

    test('uploads only go to a path the caller reserved', () {
      final body = fnBody(sql, 'can_upload_document_file');
      expect(body, contains('f.storage_path = p_name'));
      expect(body, contains("d.status = 'uploading'"));
      expect(body, contains('d.uploaded_by = auth.uid()'));
    });

    test('submit checks the pages really arrived with the declared type', () {
      final body = fnBody(sql, 'submit_resident_document');
      expect(body, contains('storage.objects'));
      expect(body, contains("metadata ->> 'mimetype'"));
    });
  });

  group('who can see what', () {
    test('landlords see a tenant\'s identity documents only as a list', () {
      final body = fnBody(sql, 'document_permission');
      expect(
        body,
        contains(
          "r.resident_type = 'tenant' and public.is_owner_of_flat(r.flat_id)",
        ),
      );
      expect(
        body,
        contains("return p_category = 'identity' and p_action = 'list'"),
      );
      // Master admins are deliberately not a way in.
      expect(body, isNot(contains('is_master_admin')));
    });

    test(
      'household-head access needs a family row they created and still live with',
      () {
        final body = fnBody(sql, 'document_permission');
        expect(body, contains("r.resident_type = 'family'"));
        expect(body, contains('r.created_by = v_uid'));
        expect(body, contains('public.lives_in_flat(r.flat_id)'));
      },
    );

    test('resident_identity is reachable only through RPCs', () {
      expect(
        RegExp(
          r'create policy "[^"]+" on public\.resident_identity',
        ).hasMatch(sql),
        isFalse,
      );
      expect(
        sql,
        contains(
          'revoke all on table public.resident_identity from anon, authenticated',
        ),
      );
      expect(
        sql,
        isNot(contains('grant select on table public.resident_identity')),
      );
    });

    test(
      'the access log cannot be written, edited or deleted through the API',
      () {
        final logPolicies = RegExp(
          r'create policy "[^"]+" on public\.document_access_log\s+for (\w+)',
        ).allMatches(sql).map((m) => m.group(1)).toList();
        expect(logPolicies, ['select']);
        expect(
          sql,
          contains(
            'revoke all on table public.document_access_log from anon, authenticated',
          ),
        );
      },
    );

    test('no table has a write policy — every write goes through an RPC', () {
      for (final table in [
        'resident_documents',
        'resident_document_files',
        'resident_document_consents',
      ]) {
        final kinds = RegExp(
          'create policy "[^"]+" on public\\.$table\\s+for (\\w+)',
        ).allMatches(sql).map((m) => m.group(1)).toList();
        expect(kinds, everyElement('select'), reason: table);
      }
    });
  });

  group('Aadhaar and PAN', () {
    test('no column can hold a full Aadhaar number', () {
      for (final f in migrations()) {
        expect(
          RegExp(
            r'aadha?r_(number|full|no)\b',
            caseSensitive: false,
          ).hasMatch(f.readAsStringSync()),
          isFalse,
          reason: fileName(f),
        );
      }
    });

    test('PAN is encrypted, validated and never echoed', () {
      final body = fnBody(sql, 'set_resident_pan');
      expect(body, contains('extensions.pgp_sym_encrypt('));
      expect(body, contains("'cipher-algo=aes256'"));
      expect(body, contains(r"'^[A-Z]{5}[0-9]{4}[A-Z]$'"));
      // pgp_sym_encrypt is STRICT: a missing key would silently store NULL.
      expect(body, contains('if v_key is null'));
      // Nothing that could copy the PAN into an error or a logged statement.
      expect(body, isNot(contains('format(')));
      expect(body, isNot(contains('execute ')));
      expect(RegExp(r"'error',[^)]*v_pan").hasMatch(body), isFalse);
      expect(RegExp(r"'error',[^)]*p_pan").hasMatch(body), isFalse);
    });

    test(
      'revealing a PAN is limited to the person or an admin with a reason, and logged',
      () {
        final body = fnBody(sql, 'reveal_resident_pan');
        expect(body, contains('v_is_self'));
        expect(body, contains('public.is_society_admin(v_res.society_id)'));
        expect(body, contains('Say why you need the full PAN'));
        expect(body, contains("interval '10 minutes'"));
        expect(body, contains("'reveal_pan'"));
      },
    );

    test('the Vault key helper is not callable by API roles', () {
      expect(
        sql,
        contains(
          'revoke all on function public.resident_pii_key(smallint) from public, anon, authenticated',
        ),
      );
    });
  });

  group('retention', () {
    test(
      'the retention trigger runs with owner rights and never pushes a date later',
      () {
        final fn = sql.substring(
          sql.indexOf(
            'create or replace function public.residents_document_retention()',
          ),
        );
        final body = fn.substring(0, fn.indexOf(r'$$;'));
        expect(body, contains('security definer'));
        expect(body, contains('coalesce(retention_until, v_until)'));
        expect(body, contains('old.status is not distinct from new.status'));
        expect(sql, contains('before delete on public.residents'));
      },
    );

    test('a document cannot lose its resident without a deletion date', () {
      expect(sql, contains('constraint resident_documents_not_lost'));
      expect(
        sql,
        contains(
          "society_id       uuid not null references public.societies(id) on delete restrict",
        ),
      );
    });

    test('purge functions are for the service role only', () {
      for (final sig in [
        'documents_due_for_purge(int)',
        'mark_documents_purged(uuid[])',
        'purge_expired_identities()',
        'prune_document_access_log()',
        'document_orphan_objects(int)',
      ]) {
        expect(
          sql,
          contains(
            'revoke all on function public.$sig from public, anon, authenticated',
          ),
          reason: sig,
        );
        expect(
          sql,
          contains('grant execute on function public.$sig to service_role'),
        );
        expect(
          sql,
          isNot(
            contains('grant execute on function public.$sig to authenticated'),
          ),
        );
      }
    });

    test('a document is only marked purged once its files are gone', () {
      final body = fnBody(sql, 'mark_documents_purged');
      expect(body, contains('storage.objects'));
      expect(body, contains('v_skipped := v_skipped + 1'));
    });
  });

  test('notification types keep every type any migration allowed', () {
    final lists = RegExp(
      r'notifications_type_check\s+check \(type in \(([\s\S]*?)\)\)',
    );
    final earlier = <String>{};
    for (final f in migrations()) {
      if (fileName(f) == '20_resident_documents.sql') continue;
      for (final m in lists.allMatches(f.readAsStringSync())) {
        earlier.addAll(
          RegExp(r"'(\w+)'").allMatches(m.group(1)!).map((x) => x.group(1)!),
        );
      }
    }
    final ours = RegExp(r"'(\w+)'")
        .allMatches(lists.firstMatch(sql)!.group(1)!)
        .map((x) => x.group(1)!)
        .toSet();
    expect(earlier, isNotEmpty);
    expect(
      ours.containsAll(earlier),
      isTrue,
      reason: 'missing: ${earlier.difference(ours)}',
    );
    expect(
      ours,
      containsAll([
        'document_submitted',
        'document_verified',
        'document_rejected',
      ]),
    );
  });

  test('notification bodies carry no names or numbers', () {
    for (final fn in ['submit_resident_document', 'review_resident_document']) {
      final body = fnBody(sql, fn);
      expect(body, isNot(contains('full_name')), reason: fn);
      expect(body, isNot(contains('pan')), reason: fn);
    }
  });

  group('every security-definer RPC checks its caller', () {
    test(path, () {
      final fns = RegExp(
        r'create (?:or replace )?function public\.(\w+)\(([\s\S]*?)\$\$;',
      ).allMatches(sql);
      expect(fns, isNotEmpty);
      final serviceOnly = RegExp(
        r'revoke all on function public\.(\w+)\([^)]*\) from public, anon, authenticated',
      ).allMatches(sql).map((m) => m.group(1)).toSet();
      for (final m in fns) {
        final name = m.group(1)!;
        final text = m.group(0)!;
        if (!text.contains('security definer')) continue;
        if (text.contains('returns trigger')) continue;
        if (serviceOnly.contains(name)) continue;
        if (text.contains('returns boolean') || text.contains('returns text')) {
          continue; // predicates/helpers: they only ever describe the caller
        }
        expect(
          RegExp(r'(auth\.uid\(\)|v_uid) is (not )?null').hasMatch(text),
          isTrue,
          reason: '$name is security definer but never checks who is calling',
        );
      }
    });

    test('$path grants name their argument lists', () {
      final grants = RegExp(
        r'grant execute on function public\.(\w+)([^;]*);',
      ).allMatches(sql);
      expect(grants, isNotEmpty);
      for (final g in grants) {
        expect(g.group(2), contains('('), reason: g.group(1));
      }
    });
  });

  test('the migration checker knows about 20', () {
    expect(
      read('supabase/check_applied_migrations.sql'),
      contains('20_resident_documents'),
    );
  });

  group('app side', () {
    test('documents are never turned into URLs', () {
      final src = read('lib/services/resident_documents_service.dart');
      expect(src, isNot(contains('getPublicUrl')));
      expect(src, isNot(contains('createSignedUrl')));
      expect(src, contains("'open_resident_document'"));
      expect(src, contains('.download('));
      expect(src, contains('upsert: false'));
    });

    test('AppSession only treats active admin rows as admin', () {
      expect(
        read('lib/services/app_session.dart'),
        contains("(r['status'] ?? 'active') == 'active'"),
      );
    });

    test('guards cannot open the documents route', () {
      expect(
        RegExp(
          r"'/documents': \(context\) =>\s+"
          r'const _NotForGuards\(child: DocumentsRootScreen\(\)\)',
        ).hasMatch(read('lib/main.dart')),
        isTrue,
      );
    });
  });
}
