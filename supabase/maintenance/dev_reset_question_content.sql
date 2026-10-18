-- =============================================================================
-- UniExam - DEV-ONLY maintenance: remove question content and test records.
-- File: supabase/maintenance/dev_reset_question_content.sql  (NOT a migration)
--
-- Run as the project owner (postgres), DEVELOPMENT project only.
-- Single transaction. It ships ending in ROLLBACK, so the first run is a dry
-- run: read the NOTICE lines, then change the last line to COMMIT and run again.
--
-- WORKS IN EITHER STATE
--   * admin tables present (normal state): clears them here, guard by guard.
--   * admin tables already removed by the rollback scripts: those steps are
--     skipped automatically and only the student content is deleted.
--
-- WHAT IT DOES TO YOUR RULES
--   The guards below are suspended for one statement each, inside this
--   transaction, and re-enabled immediately after. Trigger enabled/disabled
--   state is transactional, so no other session ever sees a guard switched off.
--   Before the end, the script proves every guard that exists is enabled again
--   and that the audit hash chain (if the log exists) still verifies; otherwise
--   everything rolls back. Nothing is granted, no policy is changed, no function
--   is replaced.
--
--   Guards suspended (each only for its own step):
--     question_versions_guard, question_version_solutions_guard   -> step 3
--     admin_question_versions_guard (if the table exists)          -> step 3
--     admin_activity_log_no_update_delete (if it exists)           -> step 4
--     admin_audit_log_no_update_delete (if it exists)              -> step 5
-- =============================================================================
begin;

-- ---- EDIT THESE. Everything is off or "no" unless you change it. -------------
set local uniexam.reset_confirm            = 'delete-question-content-in-dev';    -- must become: delete-question-content-in-dev
set local uniexam.reset_questions          = 'yes'; -- remove ALL questions, versions, answer keys, review records
set local uniexam.reset_delete_attempts    = 'no';  -- 'yes' also deletes exam attempts that used those questions
set local uniexam.reset_activity_log       = 'yes'; -- remove ALL rows of admin_activity_log (if the table exists)
set local uniexam.reset_audit_keep_through = '';    -- '' = leave audit log alone; '0' = remove all; 'N' = keep ids 1..N
set local uniexam.reset_course_codes       = '';    -- e.g. 'CS101,MTH201'; '' = no courses
set local uniexam.reset_archive            = 'no';  -- 'yes' copies removed log rows into archive_* tables first

-- -----------------------------------------------------------------------------
-- 0. Preflight
-- -----------------------------------------------------------------------------
do $$
begin
  if current_user <> 'postgres' then
    raise exception 'Run this as the project owner role (postgres), not as %.', current_user;
  end if;

  if coalesce(current_setting('uniexam.reset_confirm', true), '') <> 'delete-question-content-in-dev' then
    raise exception 'Refusing to run: set uniexam.reset_confirm to ''delete-question-content-in-dev'' (see the top of this file).';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_avatar_url_in_bucket'
      and pg_get_constraintdef(oid) like '%yzywcnrjlzqpgshutlxf%'
  ) then
    raise exception 'This does not look like the development project. Stopping.';
  end if;

  if to_regclass('public.questions') is null
     or to_regclass('public.question_versions') is null
     or to_regclass('public.question_version_solutions') is null
     or to_regclass('public.attempt_questions') is null then
    raise exception 'Expected student tables are missing. Aborting.';
  end if;

  raise notice 'Admin tables present: question review % | activity log % | audit log %',
    to_regclass('public.admin_question_versions') is not null,
    to_regclass('public.admin_activity_log') is not null,
    to_regclass('public.admin_audit_log') is not null;
end
$$;

-- -----------------------------------------------------------------------------
-- 1. Optional archive of the two logs (retention copy, not evidence)
-- -----------------------------------------------------------------------------
do $$
declare
  v_stamp text := to_char(now(), 'YYYYMMDD_HH24MISS');
  v_keep  text := coalesce(current_setting('uniexam.reset_audit_keep_through', true), '');
begin
  if coalesce(current_setting('uniexam.reset_archive', true), 'no') <> 'yes' then
    return;
  end if;

  if coalesce(current_setting('uniexam.reset_activity_log', true), '') = 'yes'
     and to_regclass('public.admin_activity_log') is not null then
    execute format('create table public.%I as table public.admin_activity_log', 'archive_admin_activity_log_' || v_stamp);
    execute format('alter table public.%I enable row level security', 'archive_admin_activity_log_' || v_stamp);
    execute format('revoke all on table public.%I from public, anon, authenticated, service_role', 'archive_admin_activity_log_' || v_stamp);
  end if;

  if v_keep ~ '^[0-9]{1,15}$' and to_regclass('public.admin_audit_log') is not null then
    execute format('create table public.%I as select * from public.admin_audit_log where id > %s',
                   'archive_admin_audit_log_' || v_stamp, v_keep::bigint);
    execute format('alter table public.%I enable row level security', 'archive_admin_audit_log_' || v_stamp);
    execute format('revoke all on table public.%I from public, anon, authenticated, service_role', 'archive_admin_audit_log_' || v_stamp);
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- 2. Exam attempts that used these questions (they block deleting the versions)
-- -----------------------------------------------------------------------------
do $$
declare
  v_rows     bigint;
  v_attempts bigint;
begin
  if coalesce(current_setting('uniexam.reset_questions', true), '') <> 'yes' then
    return;
  end if;

  select count(*), count(distinct attempt_id) into v_rows, v_attempts
  from public.attempt_questions;

  if v_rows > 0 then
    if coalesce(current_setting('uniexam.reset_delete_attempts', true), '') <> 'yes' then
      raise exception '% exam attempt(s) used these questions, and a foreign key stops their deletion. Set uniexam.reset_delete_attempts to ''yes'' to delete those attempts too (student data), or keep the questions.', v_attempts;
    end if;

    -- Cascades to attempt_questions, attempt_answers and room_attempts.
    delete from public.exam_attempts
    where id in (select attempt_id from public.attempt_questions);
    raise notice 'Deleted % exam attempt(s).', v_attempts;
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- 3. Questions (clear published-version references before deleting questions)
-- -----------------------------------------------------------------------------
do $$
declare
  v_n     bigint;
  v_admin boolean := to_regclass('public.admin_question_versions') is not null;
begin
  if coalesce(current_setting('uniexam.reset_questions', true), '') <> 'yes' then
    return;
  end if;

  alter table public.question_versions
    disable trigger question_versions_guard;

  alter table public.question_version_solutions
    disable trigger question_version_solutions_guard;

  if v_admin then
    alter table public.admin_question_versions
      disable trigger admin_question_versions_guard;
  end if;

  -- Break the circular reference to each question's published version.
UPDATE public.questions
SET status = 'draft',
    published_version = NULL
WHERE published_version IS NOT NULL;

  -- Delete questions; dependent versions and solutions cascade as configured.
  delete from public.questions;
  get diagnostics v_n = row_count;

  raise notice 'Deleted % question(s), along with dependent records where cascading is configured.', v_n;

  alter table public.question_versions
    enable trigger question_versions_guard;

  alter table public.question_version_solutions
    enable trigger question_version_solutions_guard;

  if v_admin then
    alter table public.admin_question_versions
      enable trigger admin_question_versions_guard;
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- 4. Activity log
-- -----------------------------------------------------------------------------
do $$
declare
  v_n bigint;
begin
  if coalesce(current_setting('uniexam.reset_activity_log', true), '') <> 'yes' then
    return;
  end if;
  if to_regclass('public.admin_activity_log') is null then
    raise notice 'admin_activity_log does not exist (already rolled back). Skipping.';
    return;
  end if;

  alter table public.admin_activity_log disable trigger admin_activity_log_no_update_delete;
  delete from public.admin_activity_log;
  get diagnostics v_n = row_count;
  alter table public.admin_activity_log enable trigger admin_activity_log_no_update_delete;
  raise notice 'Deleted % activity log row(s).', v_n;
end
$$;

-- -----------------------------------------------------------------------------
-- 5. Audit log: only the NEWEST rows can go. Removing rows from the start or the
--    middle would break the hash chain, so this step cannot do that by design.
-- -----------------------------------------------------------------------------
do $$
declare
  v_text  text := coalesce(current_setting('uniexam.reset_audit_keep_through', true), '');
  v_keep  bigint;
  v_n     bigint;
  v_chain record;
begin
  if v_text = '' then
    return;
  end if;
  if to_regclass('public.admin_audit_log') is null then
    raise notice 'admin_audit_log does not exist (already rolled back). Skipping.';
    return;
  end if;
  if v_text !~ '^[0-9]{1,15}$' then
    raise exception 'uniexam.reset_audit_keep_through must be a whole number (or empty).';
  end if;
  v_keep := v_text::bigint;

  alter table public.admin_audit_log disable trigger admin_audit_log_no_update_delete;
  delete from public.admin_audit_log where id > v_keep;
  get diagnostics v_n = row_count;
  alter table public.admin_audit_log enable trigger admin_audit_log_no_update_delete;

  select * into v_chain from public.admin_verify_audit_chain();
  if not v_chain.ok then
    raise exception 'The audit chain no longer verifies (first bad id %). Nothing was changed.', v_chain.first_bad_id;
  end if;
  raise notice 'Deleted % audit row(s). Kept ids up to %. New head hash: %', v_n, v_keep, v_chain.head_hash;
end
$$;

-- -----------------------------------------------------------------------------
-- 6. Courses. A course that still has attempts, rooms or programme links is
--    refused by its foreign keys; the error names the blocking constraint.
-- -----------------------------------------------------------------------------
do $$
declare
  v_text  text := coalesce(current_setting('uniexam.reset_course_codes', true), '');
  v_codes text[];
  v_n     bigint;
begin
  if btrim(v_text) = '' then
    return;
  end if;

  select array_agg(btrim(x)) into v_codes
  from unnest(string_to_array(v_text, ',')) as x
  where btrim(x) <> '';

  delete from public.courses where code = any (v_codes);
  get diagnostics v_n = row_count;
  raise notice 'Deleted % course(s) of % requested (topics go with them).', v_n, coalesce(array_length(v_codes, 1), 0);
end
$$;

-- -----------------------------------------------------------------------------
-- 7. Proof: every guard that exists is back on, nothing is left that should be
--    gone, and the audit chain verifies. Any failure rolls everything back.
-- -----------------------------------------------------------------------------
do $$
declare
  r       record;
  v_n     bigint;
  v_chain record;
begin
  for r in
    select g.tbl, g.trg
    from (values
      ('public.question_versions',          'question_versions_guard'),
      ('public.question_version_solutions', 'question_version_solutions_guard'),
      ('public.admin_question_versions',    'admin_question_versions_guard'),
      ('public.admin_question_versions',    'admin_question_versions_no_truncate'),
      ('public.admin_activity_log',         'admin_activity_log_no_update_delete'),
      ('public.admin_activity_log',         'admin_activity_log_no_truncate'),
      ('public.admin_audit_log',            'admin_audit_log_no_update_delete'),
      ('public.admin_audit_log',            'admin_audit_log_no_truncate'),
      ('public.admin_audit_log',            'admin_audit_log_chain')
    ) as g(tbl, trg)
    where to_regclass(g.tbl) is not null
  loop
    if not exists (
      select 1 from pg_trigger t
      where t.tgrelid = to_regclass(r.tbl)
        and t.tgname = r.trg
        and not t.tgisinternal
        and t.tgenabled = 'O'
    ) then
      raise exception 'Guard % on % is missing or not enabled. Rolling back.', r.trg, r.tbl;
    end if;
  end loop;

  if coalesce(current_setting('uniexam.reset_questions', true), '') = 'yes' then
    for r in
      select t as tbl from unnest(array[
        'public.questions', 'public.question_versions',
        'public.question_version_solutions', 'public.admin_question_versions']) as t
      where to_regclass(t) is not null
    loop
      execute format('select count(*) from %s', r.tbl) into v_n;
      if v_n > 0 then
        raise exception '% still has % row(s) after the delete. Rolling back.', r.tbl, v_n;
      end if;
    end loop;
  end if;

  if coalesce(current_setting('uniexam.reset_activity_log', true), '') = 'yes'
     and to_regclass('public.admin_activity_log') is not null then
    select count(*) into v_n from public.admin_activity_log;
    if v_n > 0 then
      raise exception 'The activity log still has % row(s). Rolling back.', v_n;
    end if;
  end if;

  if to_regclass('public.admin_audit_log') is not null
     and to_regprocedure('public.admin_verify_audit_chain()') is not null then
    select * into v_chain from public.admin_verify_audit_chain();
    if not v_chain.ok then
      raise exception 'The audit chain does not verify (first bad id %). Rolling back.', v_chain.first_bad_id;
    end if;
    raise notice 'Audit chain verifies (% rows).', v_chain.rows_checked;
  end if;

  raise notice 'All guard triggers that exist are enabled.';
end
$$;

-- Dry run by default. Change to COMMIT once the NOTICE lines look right.
rollback;