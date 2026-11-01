-- =============================================================================
-- UniExam Admin - rollback for 20261031150000_admin_question_import.sql
--
-- Drops admin_question_import_batch(jsonb) and nothing else. Questions that were
-- already imported through it stay exactly as they are (drafts with their
-- external_key and source); remove them through the app (discard) if needed.
--
-- Run as the project owner role (postgres), DEVELOPMENT project only.
-- =============================================================================
begin;

drop function if exists public.admin_question_import_batch(jsonb);

do $$
begin
  if to_regprocedure('public.admin_question_import_batch(jsonb)') is not null then
    raise exception 'Rollback failed: the function still exists';
  end if;

  if (select count(*) from pg_proc
      where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\') <> 46 then
    raise exception 'Rollback check failed: expected 46 admin functions in total';
  end if;

  if (select count(*) from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname like 'admin\_%' escape '\'
        and has_function_privilege('authenticated', p.oid, 'execute')) <> 27 then
    raise exception 'Rollback check failed: expected 27 admin functions callable by signed-in users';
  end if;
end
$$;

notify pgrst, 'reload schema';

commit;