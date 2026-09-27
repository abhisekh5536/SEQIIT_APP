-- ============================================================
-- 13) REALTIME FOR APPROVAL FLOWS
--
-- The gate guard used to pull-to-refresh repeatedly waiting for a
-- resident to approve or deny a visitor. This migration puts the
-- relevant tables on the `supabase_realtime` publication so the app
-- receives Postgres change events over the existing WebSocket instead.
--
-- Why Realtime and not an outbound webhook:
--   A webhook is server-to-server. It cannot reach a guard's phone
--   without additionally standing up an endpoint, a push service and
--   device-token plumbing. Realtime rides the connection supabase_flutter
--   already holds, enforces the same RLS as a SELECT, and needs no
--   server component at all. (Database Webhooks remain the right tool
--   if you later want to fan out to SMS or an external system.)
--
--   1) REPLICA IDENTITY FULL — so UPDATE events carry the old row and
--      server-side filters work on UPDATE/DELETE, not just INSERT.
--   2) Publication membership for each approval table.
-- ============================================================

-- ------------------------------------------------------------
-- 1) REPLICA IDENTITY
--
-- Without this, `payload.oldRecord` is just the primary key, so the app
-- cannot tell "pending -> approved" apart from any other update, and a
-- filter like society_id=eq.<id> does not match UPDATE events.
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'visitors',
    'visitor_status_history',
    'resident_join_requests',
    'vehicle_entry_logs',
    'parking_bay_requests',
    'notifications'
  ] loop
    begin
      execute format('alter table public.%I replica identity full', t);
    exception when others then
      raise notice 'Could not set replica identity on %: %', t, sqlerrm;
    end;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 2) PUBLICATION MEMBERSHIP
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'visitors',
    'visitor_status_history',
    'resident_join_requests',
    'vehicle_entry_logs',
    'parking_bay_requests',
    'notifications'
  ] loop
    begin
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    exception when others then
      raise notice 'Could not add % to realtime publication: %', t, sqlerrm;
    end;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 3) VERIFICATION
--
-- After running this, the query below should list every table above.
-- If one is missing, Realtime is likely disabled for the project —
-- turn it on under Database -> Replication in the Supabase dashboard.
-- ------------------------------------------------------------
-- select tablename from pg_publication_tables
--  where pubname = 'supabase_realtime' and schemaname = 'public'
--  order by tablename;
