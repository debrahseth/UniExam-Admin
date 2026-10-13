-- =============================================================================
-- UniExam Admin - Milestone 1B Batch 1: verification queries
-- File: supabase/verification/20261012180000_admin_access_foundation.verify.sql
-- All queries are READ-ONLY. In the Supabase SQL Editor choose "No limit" for the
-- result row limit, and run each numbered block separately.
-- =============================================================================

-- ############################ PART A: BEFORE ################################

-- A1. Which project am I in?  (Also compare the Reference ID in the dashboard:
--     Project Settings -> General -> Reference ID must be yzywcnrjlzqpgshutlxf.)
--     The student schema hardcodes the dev project URL in this constraint, so it
--     doubles as an in-database fingerprint. EXPECT: the definition contains
--     'yzywcnrjlzqpgshutlxf'. If it names a different project, STOP.
select conrelid::regclass as table_name, conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conname = 'profiles_avatar_url_in_bucket';

-- A2. Role running the script. EXPECT: current_user = postgres.
select current_user, session_user, current_database();

-- A3. Supabase Auth objects the access checks depend on exist with these names.
--     EXPECT: 10 rows, all present = true.
select r.t as "table", r.c as "column",
       exists (select 1 from pg_attribute a
               where a.attrelid = to_regclass('auth.' || r.t)
                 and a.attname = r.c and not a.attisdropped) as present
from (values ('users','id'),('users','email'),('users','email_confirmed_at'),
             ('sessions','id'),('sessions','user_id'),('sessions','aal'),('sessions','not_after'),
             ('mfa_factors','user_id'),('mfa_factors','factor_type'),('mfa_factors','status')) as r(t, c);

-- A4. The enum labels the checks compare against.
--     EXPECT: aal_level includes aal2; factor_type includes totp; factor_status includes verified.
select t.typname, string_agg(e.enumlabel, ', ' order by e.enumsortorder) as labels
from pg_type t join pg_enum e on e.enumtypid = t.oid
join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'auth' and t.typname in ('aal_level', 'factor_type', 'factor_status')
group by t.typname;

-- A5. Nothing from this migration exists yet. EXPECT: 0 rows.
select 'table' as kind, relname as name from pg_class
  where relnamespace = 'public'::regnamespace and relname in ('admin_users', 'admin_audit_log')
union all
select 'type', typname from pg_type
  where typnamespace = 'public'::regnamespace and typname in ('admin_role', 'admin_status')
union all
select 'function', proname from pg_proc
  where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\';

-- A6. STUDENT SCHEMA FINGERPRINT. Save both values. Run the identical query
--     again in Part B: parts and fingerprint must be IDENTICAL. It covers
--     public tables, columns, RLS flags, table/sequence ACLs, policies,
--     function definitions and ACLs, triggers, enums and default privileges,
--     excluding only the objects this migration creates.
with new_tables as (select unnest(array['admin_users','admin_audit_log','admin_audit_log_id_seq']) as n),
new_funcs as (select unnest(array[
  'admin_internal_lock','admin_internal_check_reason','admin_internal_session_state',
  'admin_internal_require_actor','admin_internal_audit','admin_internal_audit_hash',
  'admin_block_trg','admin_audit_chain_trg','admin_users_guard_trg','admin_users_require_audit_trg',
  'admin_get_my_access','admin_grant_role','admin_change_role','admin_suspend','admin_reactivate',
  'admin_revoke','admin_list_admins','admin_list_audit','admin_bootstrap_super_admin',
  'admin_verify_audit_chain']) as n),
parts as (
  select 'rel:' || c.relname || ':' || c.relkind::text || ':' || c.relrowsecurity::text || ':' || coalesce(c.relacl::text, '') as s
    from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'S')
      and c.relname not in (select n from new_tables)
  union all
  select 'col:' || c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text || ':' || coalesce(a.attacl::text, '')
    from pg_attribute a join pg_class c on c.oid = a.attrelid
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
      and a.attnum > 0 and not a.attisdropped and c.relname not in (select n from new_tables)
  union all
  select 'policy:' || tablename || '.' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '') || ':' || coalesce(with_check, '')
    from pg_policies where schemaname = 'public' and tablename not in (select n from new_tables)
  union all
  select 'fn:' || p.proname || ':' || pg_get_function_identity_arguments(p.oid) || ':' || pg_get_functiondef(p.oid) || ':' || coalesce(p.proacl::text, '')
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
      and p.proname not in (select n from new_funcs)
  union all
  select 'trg:' || c.relname || ':' || t.tgname || ':' || pg_get_triggerdef(t.oid)
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where not t.tgisinternal and c.relnamespace = 'public'::regnamespace
      and c.relname not in (select n from new_tables)
  union all
  select 'enum:' || t.typname || ':' || string_agg(e.enumlabel, ',' order by e.enumsortorder)
    from pg_type t join pg_enum e on e.enumtypid = t.oid
    where t.typnamespace = 'public'::regnamespace and t.typname not in ('admin_role', 'admin_status')
    group by t.typname
  union all
  select 'defacl:' || d.defaclrole::regrole::text || ':' || d.defaclnamespace::regnamespace::text || ':' || d.defaclobjtype::text || ':' || d.defaclacl::text
    from pg_default_acl d
)
select count(*) as parts, md5(string_agg(s, E'\n' order by s)) as fingerprint from parts;

-- A7. Baseline counts (informational; the fingerprint above is the real check).
select
  (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r') as public_tables,
  (select count(*) from pg_proc  where pronamespace = 'public'::regnamespace and prokind = 'f') as public_functions,
  (select count(*) from pg_policies where schemaname = 'public') as public_policies;

-- ############################ PART B: AFTER #################################

-- B1. Run A6 again. parts and fingerprint must equal the Part A values.

-- B2. Objects created. EXPECT: new_tables 2, new_types 2, new_functions 20, super_admin_index 1.
select
  (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('admin_users', 'admin_audit_log')) as new_tables,
  (select count(*) from pg_type  where typnamespace = 'public'::regnamespace and typname in ('admin_role', 'admin_status')) as new_types,
  (select count(*) from pg_proc  where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\') as new_functions,
  (select count(*) from pg_indexes where schemaname = 'public' and indexname = 'admin_users_single_active_super_admin') as super_admin_index;

-- B3. Function configuration. EXPECT: owner = postgres on every row, a fixed
--     search_path on every row, security_definer = true on every row except
--     admin_internal_check_reason, admin_internal_audit_hash, admin_block_trg,
--     admin_users_guard_trg (deliberately SECURITY INVOKER; they touch no
--     privileged data).
select p.proname,
       pg_get_userbyid(p.proowner) as owner,
       p.prosecdef as security_definer,
       (select c from unnest(p.proconfig) c where c like 'search_path=%') as search_path
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname like 'admin\_%' escape '\'
order by p.proname;

-- B4. EXECUTE matrix. EXPECT: anon = false and service_role = false on EVERY row;
--     authenticated = true ONLY for the 8 rows marked app_callable = true.
select p.proname,
       has_function_privilege('anon', p.oid, 'execute')          as anon,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated,
       has_function_privilege('service_role', p.oid, 'execute')  as service_role,
       p.proname in ('admin_get_my_access','admin_grant_role','admin_change_role','admin_suspend',
                     'admin_reactivate','admin_revoke','admin_list_admins','admin_list_audit') as app_callable
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname like 'admin\_%' escape '\'
order by app_callable desc, p.proname;

-- B5. Tables. EXPECT: rls_enabled = true, policy_count = 0, and false in every
--     privilege column for all three API roles.
select c.relname,
       c.relrowsecurity as rls_enabled,
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as policy_count,
       has_table_privilege('anon', c.oid, 'select, insert, update, delete, truncate, references, trigger')          as anon_any,
       has_table_privilege('authenticated', c.oid, 'select, insert, update, delete, truncate, references, trigger') as authenticated_any,
       has_table_privilege('service_role', c.oid, 'select, insert, update, delete, truncate, references, trigger')  as service_role_any,
       has_sequence_privilege('authenticated', 'public.admin_audit_log_id_seq', 'usage, select, update')            as seq_authenticated_any
from pg_class c
where c.relnamespace = 'public'::regnamespace and c.relname in ('admin_users', 'admin_audit_log');

-- B6. Triggers on the new tables. EXPECT exactly 6 rows, all tgenabled = 'O':
--     admin_audit_log: admin_audit_log_chain, admin_audit_log_no_truncate, admin_audit_log_no_update_delete
--     admin_users:     admin_users_guard, admin_users_no_truncate, admin_users_require_audit (constraint trigger)
select c.relname as "table", t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) as definition
from pg_trigger t join pg_class c on c.oid = t.tgrelid
where not t.tgisinternal and c.relnamespace = 'public'::regnamespace
  and c.relname in ('admin_users', 'admin_audit_log')
order by c.relname, t.tgname;

-- B7. Starting state. EXPECT: 0 and 0 and no active Super Admin.
select (select count(*) from public.admin_users) as admin_rows,
       (select count(*) from public.admin_audit_log) as audit_rows,
       (select count(*) from public.admin_users where role = 'super_admin' and status = 'active') as active_super_admins;

-- B8. Behaviour of the API roles. EXPECT, in order: permission denied (anon);
--     one row ('none', null) for authenticated with no identity; permission denied on
--     both table reads; permission denied on the operator function.
--     Run each statement separately; "reset role" after each.
--   set role anon;          select * from public.admin_get_my_access();          reset role;
--   set role authenticated; select * from public.admin_get_my_access();          reset role;
--   set role authenticated; select * from public.admin_users;                    reset role;
--   set role authenticated; select * from public.admin_audit_log;                reset role;
--   set role authenticated; select public.admin_bootstrap_super_admin(gen_random_uuid(), 'permission probe only'); reset role;

-- B9. Audit chain. EXPECT (empty log): ok = true, rows_checked = 0.
--     After any events, store head_hash OUTSIDE Supabase (see notes on privileged operators).
select * from public.admin_verify_audit_chain();

-- ############################ PART C: BEFORE ROLLBACK #########################
-- Export these two before any rollback. In the SQL Editor use "No limit" and the
-- CSV export button, and keep the CSVs and the head_hash outside Supabase.
--   select * from public.admin_audit_log order by id;
--   select * from public.admin_users order by created_at;
--   select head_hash from public.admin_verify_audit_chain();