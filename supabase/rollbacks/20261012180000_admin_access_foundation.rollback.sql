-- =============================================================================
-- UniExam Admin - ROLLBACK for 20261012180000_admin_access_foundation.sql
-- File: supabase/rollbacks/20261012180000_admin_access_foundation.rollback.sql
-- (kept OUT of supabase/migrations so the CLI never applies it by accident)
--
-- WHAT THIS DESTROYS
--   * every admin access record (admin_users): ALL admins, including the
--     Super Admin, lose access at once; nothing can grant access again until
--     the migration is re-applied and a Super Admin is bootstrapped again;
--   * the entire audit log (admin_audit_log), unless you archive it first.
-- It does NOT touch any student table, policy, function or grant.
--
-- HOW IT PROTECTS YOU
--   If either table holds rows, the script refuses to run until you confirm on
--   purpose. Two opt-in switches, both set with SET LOCAL inside this
--   transaction (see the commented lines right after BEGIN):
--     uniexam.rollback_archive = 'yes'
--         first copies both tables into archive_* tables inside the database
--         (RLS on, no API privileges). The copy is NOT append-only and NOT
--         hash-chain-protected; treat it as a retention copy, not evidence.
--     uniexam.rollback_confirm = 'destroy-admin-access-and-audit-data'
--         required whenever any rows exist.
--   Best practice: export both tables to CSV first (see the verification
--   script) and store the audit export and the head hash outside Supabase.
-- =============================================================================
begin;

-- Uncomment deliberately, after exporting. Archive is optional; confirm is not.
-- set local uniexam.rollback_archive = 'yes';
-- set local uniexam.rollback_confirm = 'destroy-admin-access-and-audit-data';

do $$
declare
  v_audit  bigint := 0;
  v_admins bigint := 0;
  v_copied bigint := 0;
  v_stamp  text   := to_char(now(), 'YYYYMMDD_HH24MISS');
begin
  if to_regclass('public.admin_audit_log') is not null then
    select count(*) into v_audit from public.admin_audit_log;
  end if;
  if to_regclass('public.admin_users') is not null then
    select count(*) into v_admins from public.admin_users;
  end if;

  if (v_audit > 0 or v_admins > 0)
     and coalesce(current_setting('uniexam.rollback_confirm', true), '') <> 'destroy-admin-access-and-audit-data' then
    raise exception 'Refusing to roll back: % admin record(s) and % audit row(s) would be destroyed. Export them first, then set uniexam.rollback_confirm (see the top of this file).', v_admins, v_audit;
  end if;

  if coalesce(current_setting('uniexam.rollback_archive', true), '') = 'yes' then
    if to_regclass('public.admin_audit_log') is not null then
      execute format('create table public.%I as table public.admin_audit_log', 'archive_admin_audit_log_' || v_stamp);
      execute format('alter table public.%I enable row level security', 'archive_admin_audit_log_' || v_stamp);
      execute format('revoke all on table public.%I from public, anon, authenticated, service_role', 'archive_admin_audit_log_' || v_stamp);
    end if;
    if to_regclass('public.admin_users') is not null then
      -- role/status are copied as text so the archive does not depend on (and
      -- block the removal of) the enum types.
      execute format(
        'create table public.%I as select user_id, role::text as role, status::text as status, created_at, created_by, updated_at, updated_by from public.admin_users',
        'archive_admin_users_' || v_stamp);
      execute format('alter table public.%I enable row level security', 'archive_admin_users_' || v_stamp);
      execute format('revoke all on table public.%I from public, anon, authenticated, service_role', 'archive_admin_users_' || v_stamp);
    end if;
    -- Never drop the originals unless the copies are complete.
    if to_regclass('public.admin_audit_log') is not null then
      execute format('select count(*) from public.%I', 'archive_admin_audit_log_' || v_stamp) into v_copied;
      if v_copied <> v_audit then
        raise exception 'Archive of the audit log is incomplete (% of % rows). Nothing was changed.', v_copied, v_audit;
      end if;
    end if;
    if to_regclass('public.admin_users') is not null then
      execute format('select count(*) from public.%I', 'archive_admin_users_' || v_stamp) into v_copied;
      if v_copied <> v_admins then
        raise exception 'Archive of the admin records is incomplete (% of % rows). Nothing was changed.', v_copied, v_admins;
      end if;
    end if;
    raise notice 'Archived to public.archive_admin_audit_log_% and public.archive_admin_users_%', v_stamp, v_stamp;
  end if;
end
$$;

-- admin_internal_audit_hash takes the audit table's row type as a parameter, so
-- it must go before the table. Nothing here uses CASCADE on purpose: if anything
-- outside this migration (a view, a policy, another function, a foreign key)
-- came to depend on these tables or types, the DROP fails, the whole transaction
-- rolls back, and PostgreSQL lists the dependents, instead of silently removing them.
drop function if exists public.admin_internal_audit_hash(public.admin_audit_log);

-- Tables (this also removes their triggers and indexes).
drop table if exists public.admin_audit_log;
drop table if exists public.admin_users;

-- Functions.
drop function if exists public.admin_get_my_access();
drop function if exists public.admin_grant_role(uuid, public.admin_role, text);
drop function if exists public.admin_change_role(uuid, public.admin_role, text);
drop function if exists public.admin_suspend(uuid, text);
drop function if exists public.admin_reactivate(uuid, text);
drop function if exists public.admin_revoke(uuid, text);
drop function if exists public.admin_list_admins();
drop function if exists public.admin_list_audit(integer, bigint);
drop function if exists public.admin_bootstrap_super_admin(uuid, text, boolean);
drop function if exists public.admin_verify_audit_chain();
drop function if exists public.admin_internal_require_actor(public.admin_role);
drop function if exists public.admin_internal_session_state();
drop function if exists public.admin_internal_audit(uuid, text, uuid, jsonb, jsonb, text);
drop function if exists public.admin_internal_check_reason(text);
drop function if exists public.admin_internal_lock();
drop function if exists public.admin_block_trg();
drop function if exists public.admin_audit_chain_trg();
drop function if exists public.admin_users_guard_trg();
drop function if exists public.admin_users_require_audit_trg();

-- Types.
drop type if exists public.admin_status;
drop type if exists public.admin_role;

notify pgrst, 'reload schema';

commit;