-- ============================================================
-- Which migrations has this database actually had?
--
-- Read-only. Paste into the Supabase SQL editor and run. Each row checks
-- one object that only that migration creates. Run any "missing" ones in
-- number order, then re-run 17 and 18 last (both are safe to re-run) so
-- their guard policies win over the older ones from 14.
-- ============================================================
select migration, checks_for,
       case when ok then 'applied' else 'MISSING' end as status
from (values
  ('09_visitors_module',        'table visitors',
     to_regclass('public.visitors') is not null),
  ('10_security_emergency',     'table sos_alerts',
     to_regclass('public.sos_alerts') is not null),
  ('11_vehicles_parking',       'table vehicle_entry_logs',
     to_regclass('public.vehicle_entry_logs') is not null),
  ('12_parking_bay_requests',   'table parking_bay_requests',
     to_regclass('public.parking_bay_requests') is not null),
  ('13_realtime_approvals',     'visitors on the realtime publication',
     exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and tablename = 'visitors')),
  ('14_guard_gate_access',      'policy "guard read visitor_status_history"',
     exists (select 1 from pg_policies
              where policyname = 'guard read visitor_status_history')),
  ('15_security_hardening',     'table pre_approval_verify_attempts',
     to_regclass('public.pre_approval_verify_attempts') is not null),
  ('16_notification_read_state','table notification_reads',
     to_regclass('public.notification_reads') is not null),
  ('17_guard_identity',         'table society_guards',
     to_regclass('public.society_guards') is not null),
  ('17_guard_identity',         'function caller_gate_role(uuid)',
     to_regprocedure('public.caller_gate_role(uuid)') is not null),
  ('18_guard_panel',            'function guard_call_flat(uuid,text,uuid)',
     to_regprocedure('public.guard_call_flat(uuid,text,uuid)') is not null)
) as m(migration, checks_for, ok)
order by migration;
