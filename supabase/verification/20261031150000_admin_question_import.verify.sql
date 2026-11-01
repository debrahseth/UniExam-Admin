-- =============================================================================
-- UniExam Admin - verify for 20261031150000_admin_question_import.sql
--
-- Read-only. Every row of the result should show ok = true.
-- Run as the project owner role (postgres), DEVELOPMENT project only.
--
-- Not included here: the student schema fingerprint (parts 304,
-- md5 73f52f9b5e38786ddd69fee26a7af4d6). Run your existing fingerprint query
-- before and after the migration; this migration touches no student object.
-- =============================================================================
select 'the function exists' as check_name,
       to_regprocedure('public.admin_question_import_batch(jsonb)') is not null as ok
union all
select 'anon cannot execute it',
       not coalesce(has_function_privilege('anon', to_regprocedure('public.admin_question_import_batch(jsonb)')::oid, 'execute'), true)
union all
select 'service_role cannot execute it',
       not coalesce(has_function_privilege('service_role', to_regprocedure('public.admin_question_import_batch(jsonb)')::oid, 'execute'), true)
union all
select 'signed-in users can execute it',
       coalesce(has_function_privilege('authenticated', to_regprocedure('public.admin_question_import_batch(jsonb)')::oid, 'execute'), false)
union all
select 'it is SECURITY DEFINER',
       coalesce((select p.prosecdef from pg_proc p
                 where p.oid = to_regprocedure('public.admin_question_import_batch(jsonb)')::oid), false)
union all
select 'it has a fixed search_path',
       exists (select 1
               from pg_proc p, unnest(p.proconfig) c
               where p.oid = to_regprocedure('public.admin_question_import_batch(jsonb)')::oid
                 and c like 'search_path=%')
union all
select 'there are 47 admin functions in total',
       (select count(*) from pg_proc
        where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\') = 47
union all
select 'signed-in users can call exactly 28 of them',
       (select count(*) from pg_proc p
        where p.pronamespace = 'public'::regnamespace and p.proname like 'admin\_%' escape '\'
          and has_function_privilege('authenticated', p.oid, 'execute')) = 28;