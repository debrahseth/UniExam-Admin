-- ROLLBACK for 20261014090000_admin_question_authoring.sql
-- Drops the admin question objects. Questions, versions and solutions in the
-- student tables are NOT touched. Authorship, review history and the activity
-- log ARE destroyed: export them first. Run as postgres.
begin;

-- Uncomment deliberately, after exporting both tables.
-- set local uniexam.rollback_confirm = 'destroy-question-review-and-activity-data';

do $$
declare
  v_a bigint := 0;
  v_b bigint := 0;
begin
  if to_regclass('public.admin_question_versions') is not null then
    select count(*) into v_a from public.admin_question_versions;
  end if;
  if to_regclass('public.admin_activity_log') is not null then
    select count(*) into v_b from public.admin_activity_log;
  end if;

  if (v_a > 0 or v_b > 0)
     and coalesce(current_setting('uniexam.rollback_confirm', true), '') <> 'destroy-question-review-and-activity-data' then
    raise exception 'Refusing to roll back: % review record(s) and % activity row(s) would be destroyed. Export them first, then set uniexam.rollback_confirm (see the top of this file).', v_a, v_b;
  end if;
end
$$;

-- Tables first (this also removes their triggers, indexes and foreign keys),
-- then the functions, then the type. No CASCADE on purpose.
drop table if exists public.admin_question_versions;
drop table if exists public.admin_activity_log;

drop function if exists public.admin_question_create_draft(uuid, uuid, text, text[], text, text, public.question_difficulty);
drop function if exists public.admin_question_create_version(uuid, text, text[], text, text, public.question_difficulty);
drop function if exists public.admin_question_update_draft(uuid, uuid, text, text[], text, text, public.question_difficulty);
drop function if exists public.admin_question_submit(uuid);
drop function if exists public.admin_question_discard_draft(uuid);
drop function if exists public.admin_question_approve(uuid);
drop function if exists public.admin_question_reject(uuid, text);
drop function if exists public.admin_question_retire(uuid, text);
drop function if exists public.admin_question_restore(uuid, text);
drop function if exists public.admin_question_list(uuid, text, integer, integer);
drop function if exists public.admin_question_get(uuid);
drop function if exists public.admin_internal_log_activity(uuid, public.admin_role, text, text, uuid, jsonb, text);
drop function if exists public.admin_internal_build_question(text, text[], text, text, public.question_difficulty);
drop function if exists public.admin_internal_require_role(public.admin_role[]);
drop function if exists public.admin_internal_lock_shared();
drop function if exists public.admin_qv_guard_trg();

drop type if exists public.admin_review_state;

notify pgrst, 'reload schema';

commit;