-- =============================================================================
-- UniExam Admin - database tests for question search
-- File: supabase/tests/admin_question_search.test.sql
--
-- Run in the Supabase SQL editor as postgres, DEVELOPMENT project only.
-- One DO block that ends by raising an error whose message is the report. That
-- guarantees a rollback: the test courses, topics, questions, versions, users,
-- sessions and admin records are never kept. Read the first line of the error:
--   "ALL PASS: N of N checks passed"   or   "FAILURES: ..."
-- =============================================================================
do $test$
declare
  v_total  integer;
  v_fail   integer;
  v_report text;

  v_course1 uuid; v_course2 uuid;
  v_ta uuid; v_tb uuid; v_tc uuid;
  v_vA1 uuid; v_vA2 uuid; v_vB uuid; v_vC uuid; v_vD uuid; v_vE uuid;
  v_vF uuid; v_vG uuid; v_vH uuid; v_vI uuid; v_vJ uuid;
  v_qA uuid; v_qB uuid; v_qC uuid; v_qD uuid; v_qE uuid;
  v_qF uuid; v_qG uuid; v_qH uuid; v_qI uuid; v_qJ uuid;
begin
  -- Guards ---------------------------------------------------------------
  if current_user <> 'postgres' then
    raise exception 'Run this as the project owner role (postgres), not as %.', current_user;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_avatar_url_in_bucket'
      and pg_get_constraintdef(oid) like '%yzywcnrjlzqpgshutlxf%'
  ) then
    raise exception 'This does not look like the development project. Aborting.';
  end if;

  if to_regprocedure('public.admin_question_search(text, text, uuid, uuid, public.question_difficulty, timestamptz, uuid, text, integer)') is null then
    raise exception 'Apply migration 20261015090000 first. Aborting.';
  end if;

  if exists (select 1 from public.courses where code in ('ZZS101', 'ZZS102')) then
    raise exception 'A course with a test code (ZZS101 or ZZS102) already exists. Aborting.';
  end if;

  -- Scaffolding ----------------------------------------------------------
  create temp table t_ids (k text primary key, v uuid);
  create temp table t_results (n serial primary key, name text, passed boolean, detail text);

  -- Switches to one simulated actor. Always called as postgres: it resets the
  -- role first, then sets the claims and the database role.
  create function pg_temp.as_actor(p_who text)
  returns void
  language plpgsql
  as $f$
  declare
    v_role text;
    v_user text;
    v_aal  text;
    v_sid  text;
    v_uid  uuid;
    v_sidv uuid;
  begin
    execute 'reset role';

    select m.r_, m.u_, m.a_, m.s_ into v_role, v_user, v_aal, v_sid
    from (values
      ('anon',      'anon',          null,        null,   null),
      ('svc',       'service_role',  null,        null,   null),
      ('op',        'postgres',      null,        null,   null),
      ('outsider',  'authenticated', 'outsider',  'aal2', null),
      ('super',     'authenticated', 'super',     'aal2', 'sid_super'),
      ('academic',  'authenticated', 'academic',  'aal2', 'sid_academic'),
      ('academic2', 'authenticated', 'academic2', 'aal2', 'sid_academic2'),
      ('reviewer',  'authenticated', 'reviewer',  'aal2', 'sid_reviewer'),
      ('support',   'authenticated', 'support',   'aal2', 'sid_support'),
      ('analytics', 'authenticated', 'analytics', 'aal2', 'sid_analytics')
    ) as m(w, r_, u_, a_, s_)
    where m.w = p_who;

    if v_role is null then
      raise exception 'unknown actor %', p_who;
    end if;

    select v into v_uid  from t_ids where k = v_user;
    select v into v_sidv from t_ids where k = v_sid;

    perform set_config(
      'request.jwt.claims',
      case when v_uid is null then '{}'
           else json_build_object('sub', v_uid, 'role', v_role,
                                  'aal', v_aal, 'session_id', v_sidv)::text end,
      true);

    execute format('set local role %I', v_role);
  end
  $f$;

  -- Runs one statement as one actor and records pass or fail.
  --   p_expect 'ERR:text' -> must fail with an error containing text
  --   p_expect 'ANY'      -> must succeed, any result
  --   anything else       -> must succeed and return exactly that text
  -- {name} placeholders in p_sql are replaced with the id stored under that name.
  create function pg_temp.t(p_name text, p_who text, p_sql text, p_expect text)
  returns void
  language plpgsql
  as $f$
  declare
    v_sql  text := p_sql;
    v_out  text;
    v_err  text;
    v_pass boolean;
    r      record;
  begin
    for r in select k, v from t_ids loop
      v_sql := replace(v_sql, '{' || r.k || '}', r.v::text);
    end loop;

    begin
      perform pg_temp.as_actor(p_who);
      if lower(ltrim(v_sql)) ~ '^(select|with)' then
        execute v_sql into v_out;
      else
        execute v_sql;
        v_out := 'ok';
      end if;
    exception when others then
      v_err := sqlerrm;
    end;
    execute 'reset role';

    if p_expect like 'ERR:%' then
      v_pass := v_err is not null and position(substr(p_expect, 5) in v_err) > 0;
    elsif p_expect = 'ANY' then
      v_pass := v_err is null;
    else
      v_pass := v_err is null and coalesce(v_out, '') = p_expect;
    end if;

    insert into t_results (name, passed, detail)
    values (p_name, v_pass, coalesce('error: ' || v_err, 'returned: ' || v_out, 'returned nothing'));
  end
  $f$;

  -- Identities, courses, topics --------------------------------------------
  insert into t_ids (k, v)
  select k, gen_random_uuid()
  from unnest(array[
    'super','academic','academic2','reviewer','support','analytics','outsider',
    'sid_super','sid_academic','sid_academic2','sid_reviewer','sid_support','sid_analytics',
    'course1','course2','topicA','topicB','topicC']) as k;

  insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  select v, 'authenticated', 'authenticated', 'test-' || k || '@uniexam-test.invalid',
         now(), now(), now(), '{}'::jsonb, '{}'::jsonb
  from t_ids
  where k in ('super','academic','academic2','reviewer','support','analytics','outsider');

  insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
  select gen_random_uuid(), v, 'test factor',
         'totp'::auth.factor_type, 'verified'::auth.factor_status, now(), now()
  from t_ids
  where k in ('super','academic','academic2','reviewer','support','analytics');

  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  select s.v, o.v, now(), now(), 'aal2'::auth.aal_level
  from t_ids s
  join t_ids o on s.k = 'sid_' || o.k
  where o.k in ('super','academic','academic2','reviewer','support','analytics');

  insert into public.courses (id, code, title, is_active)
  select v, case k when 'course1' then 'ZZS101' else 'ZZS102' end, 'Search test course', true
  from t_ids
  where k in ('course1', 'course2');

  insert into public.topics (id, course_id, title, sort_order) values
    ((select v from t_ids where k = 'topicA'), (select v from t_ids where k = 'course1'), 'Search topic A', 1),
    ((select v from t_ids where k = 'topicB'), (select v from t_ids where k = 'course1'), 'Search topic B', 2),
    ((select v from t_ids where k = 'topicC'), (select v from t_ids where k = 'course2'), 'Search topic C', 1);

  perform set_config('request.jwt.claims', '{}', true);
  perform public.admin_bootstrap_super_admin(
    (select v from t_ids where k = 'super'),
    'Test setup: install the test Super Admin', true);

  perform pg_temp.t('setup: Super Admin grants Academic admin', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{academic}'::uuid, 'academic_admin', 'Automated test reason')) s$q$, 'ok');
  perform pg_temp.t('setup: Super Admin grants a second Academic admin', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{academic2}'::uuid, 'academic_admin', 'Automated test reason')) s$q$, 'ok');
  perform pg_temp.t('setup: Super Admin grants Question reviewer', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{reviewer}'::uuid, 'question_reviewer', 'Automated test reason')) s$q$, 'ok');
  perform pg_temp.t('setup: Super Admin grants Support admin', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{support}'::uuid, 'support_admin', 'Automated test reason')) s$q$, 'ok');
  perform pg_temp.t('setup: Super Admin grants Analytics viewer', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{analytics}'::uuid, 'analytics_viewer', 'Automated test reason')) s$q$, 'ok');

  -- Question data. Authors and reviewers act through the real functions.
  --   A  live v1 plus a v2 draft in progress      (academic)
  --   B  submitted, waiting for review             (academic)
  --   C  draft                                     (academic)
  --   D  submitted, waiting for review             (super)
  --   E  approved, then retired                    (academic, reviewer)
  --   F  script-loaded and live                    (inserted directly)
  --   G  live, in the second course                (academic, reviewer)
  --   H  rejected                                  (academic2, reviewer)
  --   I, J  drafts used to test literal % and _    (academic)
  select v into v_course1 from t_ids where k = 'course1';
  select v into v_course2 from t_ids where k = 'course2';
  select v into v_ta from t_ids where k = 'topicA';
  select v into v_tb from t_ids where k = 'topicB';
  select v into v_tc from t_ids where k = 'topicC';

  execute 'reset role'; perform pg_temp.as_actor('academic');
  v_vA1 := public.admin_question_create_draft(v_course1, v_ta, 'Alpha question about resistors', array['one','two'], 'a', null, 'easy');
  perform public.admin_question_submit(v_vA1);
  execute 'reset role'; perform pg_temp.as_actor('reviewer');
  perform public.admin_question_approve(v_vA1);
  execute 'reset role';
  select question_id into v_qA from public.question_versions where id = v_vA1;

  perform pg_temp.as_actor('academic');
  v_vA2 := public.admin_question_create_version(v_qA, 'Rewritten wording about capacitors', array['x','y'], 'b', null, 'medium');
  v_vB := public.admin_question_create_draft(v_course1, v_ta, 'Beta question about inductors', array['one','two'], 'a', null, 'medium');
  perform public.admin_question_submit(v_vB);
  v_vC := public.admin_question_create_draft(v_course1, v_tb, 'Gamma question about diodes', array['one','two'], 'a', null, 'hard');
  v_vE := public.admin_question_create_draft(v_course1, v_ta, 'Epsilon question about relays', array['one','two'], 'a', null, 'easy');
  perform public.admin_question_submit(v_vE);
  v_vG := public.admin_question_create_draft(v_course2, v_tc, 'Kappa question about motors', array['one','two'], 'a', null, 'easy');
  perform public.admin_question_submit(v_vG);
  v_vI := public.admin_question_create_draft(v_course1, v_ta, 'Iota value 50% of_total', array['one','two'], 'a', null, 'easy');
  v_vJ := public.admin_question_create_draft(v_course1, v_ta, 'Jota value 50X of total', array['one','two'], 'a', null, 'easy');

  execute 'reset role'; perform pg_temp.as_actor('academic2');
  v_vH := public.admin_question_create_draft(v_course1, v_tb, 'Eta question about fuses', array['one','two'], 'a', null, 'easy');
  perform public.admin_question_submit(v_vH);

  execute 'reset role'; perform pg_temp.as_actor('super');
  v_vD := public.admin_question_create_draft(v_course1, v_tb, 'Delta question about transistors', array['one','two'], 'a', null, 'hard');
  perform public.admin_question_submit(v_vD);

  execute 'reset role'; perform pg_temp.as_actor('reviewer');
  perform public.admin_question_approve(v_vE);
  perform public.admin_question_approve(v_vG);
  perform public.admin_question_reject(v_vH, 'Needs clearer wording please.');

  execute 'reset role';
  select question_id into v_qE from public.question_versions where id = v_vE;
  perform pg_temp.as_actor('reviewer');
  perform public.admin_question_retire(v_qE, 'Retired for the search test.');
  execute 'reset role';

  -- F: a script-loaded question, live, with an external key.
  insert into public.questions (course_id, topic_id, status, external_key)
  values (v_course1, v_ta, 'draft', 'ZZS-IMP-001')
  returning id into v_qF;
  insert into public.question_versions (question_id, version, type, body, difficulty)
  values (v_qF, 1, 'mcq',
          jsonb_build_object('stem', 'Imported question about voltage',
                             'options', jsonb_build_array(
                               jsonb_build_object('id', 'a', 'text', 'yes'),
                               jsonb_build_object('id', 'b', 'text', 'no'))),
          'medium')
  returning id into v_vF;
  insert into public.question_version_solutions (question_version_id, correct_option_ids)
  values (v_vF, array['a']);
  perform public.publish_question_version(v_vF);

  select question_id into v_qB from public.question_versions where id = v_vB;
  select question_id into v_qC from public.question_versions where id = v_vC;
  select question_id into v_qD from public.question_versions where id = v_vD;
  select question_id into v_qG from public.question_versions where id = v_vG;
  select question_id into v_qH from public.question_versions where id = v_vH;
  select question_id into v_qI from public.question_versions where id = v_vI;
  select question_id into v_qJ from public.question_versions where id = v_vJ;

  -- Everything above shares one transaction time, so give the open versions
  -- known activity times (in the future) and the review queue known ages.
  -- E and F keep the transaction time on purpose: they tie.
  update public.admin_question_versions set updated_at = now() + interval '40 minutes' where question_version_id = v_vA2;
  update public.admin_question_versions set updated_at = now() + interval '30 minutes', submitted_at = now() - interval '2 hours' where question_version_id = v_vB;
  update public.admin_question_versions set updated_at = now() + interval '20 minutes' where question_version_id = v_vC;
  update public.admin_question_versions set updated_at = now() + interval '10 minutes', submitted_at = now() - interval '1 hour' where question_version_id = v_vD;
  update public.admin_question_versions set updated_at = now() + interval '50 minutes' where question_version_id = v_vH;
  update public.admin_question_versions set updated_at = now() + interval '5 minutes' where question_version_id = v_vI;
  update public.admin_question_versions set updated_at = now() + interval '6 minutes' where question_version_id = v_vJ;

  insert into t_ids (k, v) values
    ('qA', v_qA), ('qB', v_qB), ('qC', v_qC), ('qD', v_qD), ('qE', v_qE),
    ('qF', v_qF), ('qG', v_qG), ('qH', v_qH), ('qI', v_qI), ('qJ', v_qJ),
    ('vA1', v_vA1), ('vA2', v_vA2);

  -- A. Gates ---------------------------------------------------------------
  perform pg_temp.t('anon cannot call admin_question_search', 'anon',
    $q$select 'ok' from public.admin_question_search() limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('anon cannot call admin_question_counts', 'anon',
    $q$select 'ok' from public.admin_question_counts() limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('anon cannot call admin_question_history', 'anon',
    $q$select 'ok' from public.admin_question_history('{qA}'::uuid) limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('service_role cannot call admin_question_search', 'svc',
    $q$select 'ok' from public.admin_question_search() limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot call the internal base function', 'outsider',
    $q$select 'ok' from public.admin_internal_question_base('{outsider}'::uuid, null::text, null::uuid, null::uuid, null::public.question_difficulty) limit 1$q$,
    'ERR:permission denied');
  perform pg_temp.t('non-admin cannot search', 'outsider',
    $q$select 'ok' from public.admin_question_search() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('support admin cannot search', 'support',
    $q$select 'ok' from public.admin_question_search() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('analytics viewer cannot search', 'analytics',
    $q$select 'ok' from public.admin_question_search() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('non-admin cannot count', 'outsider',
    $q$select 'ok' from public.admin_question_counts() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('non-admin cannot read a question history', 'outsider',
    $q$select 'ok' from public.admin_question_history('{qA}'::uuid) limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('support admin cannot read a question history', 'support',
    $q$select 'ok' from public.admin_question_history('{qA}'::uuid) limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('academic admin can search', 'academic',
    $q$select 'ok' from public.admin_question_search(p_limit => 1) limit 1$q$, 'ANY');
  perform pg_temp.t('question reviewer can search', 'reviewer',
    $q$select 'ok' from public.admin_question_search(p_limit => 1) limit 1$q$, 'ANY');
  perform pg_temp.t('Super Admin can search', 'super',
    $q$select 'ok' from public.admin_question_search(p_limit => 1) limit 1$q$, 'ANY');
  perform pg_temp.t('academic admin can count', 'academic',
    $q$select 'ok' from public.admin_question_counts() limit 1$q$, 'ANY');
  perform pg_temp.t('there are 41 admin functions in total', 'op',
    $q$select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\'$q$,
    '41');
  perform pg_temp.t('signed-in users can call exactly 23 of them', 'op',
    $q$select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'admin\_%' escape '\' and has_function_privilege('authenticated', p.oid, 'execute')$q$,
    '23');

  -- B. Validation ----------------------------------------------------------
  perform pg_temp.t('an unknown view is refused', 'academic',
    $q$select 'ok' from public.admin_question_search(p_view => 'bogus') limit 1$q$, 'ERR:invalid_filter');
  perform pg_temp.t('an unknown direction is refused', 'academic',
    $q$select 'ok' from public.admin_question_search(p_dir => 'sideways') limit 1$q$, 'ERR:invalid_filter');
  perform pg_temp.t('a cursor time without a cursor id is refused', 'academic',
    $q$select 'ok' from public.admin_question_search(p_cursor_at => now()) limit 1$q$, 'ERR:invalid_filter');
  perform pg_temp.t('a cursor id without a cursor time is refused', 'academic',
    $q$select 'ok' from public.admin_question_search(p_cursor_id => '{qA}'::uuid) limit 1$q$, 'ERR:invalid_filter');
  perform pg_temp.t('search text of one character is refused', 'academic',
    $q$select 'ok' from public.admin_question_search(p_query => 'a') limit 1$q$, 'ERR:invalid_filter');
  perform pg_temp.t('search text over 100 characters is refused', 'academic',
    $q$select 'ok' from public.admin_question_search(p_query => repeat('x', 101)) limit 1$q$, 'ERR:invalid_filter');
  perform pg_temp.t('a limit of 0 is raised to 1 (two rows come back: page plus one)', 'academic',
    $q$select count(*)::text from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 0)$q$,
    '2');
  perform pg_temp.t('a missing limit defaults to 25 (all 9 rows come back)', 'academic',
    $q$select count(*)::text from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => null::integer)$q$,
    '9');

  -- C. One row per question --------------------------------------------------
  perform pg_temp.t('the test course returns exactly 9 rows, one per question', 'academic',
    $q$select count(*)::text from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 100)$q$,
    '9');
  perform pg_temp.t('the question with two versions appears once', 'academic',
    $q$select count(*)::text from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 100) s where s.stem like 'Alpha%'$q$,
    '1');
  perform pg_temp.t('that row shows the live version and the open draft together', 'academic',
    $q$select (s.live_version = 1 and s.open_version = 2 and s.open_state = 'draft' and s.current_version = 1 and s.is_live
               and s.open_author_email = 'test-academic@uniexam-test.invalid' and not s.current_is_imported
               and s.current_version_id = '{vA1}'::uuid and s.open_version_id = '{vA2}'::uuid)::text
       from public.admin_question_search(p_query => 'resistors', p_course_id => '{course1}'::uuid) s$q$,
    'true');
  perform pg_temp.t('a retired question keeps its last published version', 'academic',
    $q$select (s.question_status = 'retired' and not s.is_live and s.is_retired and s.live_version = 1
               and s.open_version is null and s.current_version = 1)::text
       from public.admin_question_search(p_query => 'relays', p_course_id => '{course1}'::uuid) s$q$,
    'true');
  perform pg_temp.t('a script-loaded question is flagged as imported', 'academic',
    $q$select (s.current_is_imported and s.is_live and s.open_version is null and s.live_version = 1
               and s.topic_title = 'Search topic A')::text
       from public.admin_question_search(p_query => 'voltage', p_course_id => '{course1}'::uuid) s$q$,
    'true');
  perform pg_temp.t('a rejected, never-published question shows its open version', 'academic',
    $q$select (s.open_state = 'rejected' and not s.is_live and s.live_version is null and s.current_version = 1
               and s.question_status = 'draft')::text
       from public.admin_question_search(p_query => 'fuses', p_course_id => '{course1}'::uuid) s$q$,
    'true');
  perform pg_temp.t('a submitted question needs review for the reviewer', 'reviewer',
    $q$select s.needs_review::text from public.admin_question_search(p_query => 'inductors', p_course_id => '{course1}'::uuid) s$q$,
    'true');
  perform pg_temp.t('...but not for its own author', 'academic',
    $q$select s.needs_review::text from public.admin_question_search(p_query => 'inductors', p_course_id => '{course1}'::uuid) s$q$,
    'false');
  perform pg_temp.t('...and it is marked as the author''s own', 'academic',
    $q$select s.is_mine::text from public.admin_question_search(p_query => 'inductors', p_course_id => '{course1}'::uuid) s$q$,
    'true');

  -- D. Search --------------------------------------------------------------
  perform pg_temp.t('search finds a live stem', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_query => 'resistors', p_course_id => '{course1}'::uuid) s) x$q$,
    'Alpha');
  perform pg_temp.t('search finds the stem of an open version, still as one row', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn) || ':' || count(*)::text
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_query => 'capacitors', p_course_id => '{course1}'::uuid) s) x$q$,
    'Alpha:1');
  perform pg_temp.t('search ignores case', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_query => 'RESISTORS', p_course_id => '{course1}'::uuid) s) x$q$,
    'Alpha');
  perform pg_temp.t('a shared phrase matches every question that has it', 'academic',
    $q$select count(*)::text from public.admin_question_search(p_query => 'question about', p_course_id => '{course1}'::uuid, p_limit => 100)$q$,
    '7');
  perform pg_temp.t('search finds an external key', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_query => 'ZZS-IMP-001', p_course_id => '{course1}'::uuid) s) x$q$,
    'Imported');
  perform pg_temp.t('search finds part of an external key', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_query => 'zzs-imp', p_course_id => '{course1}'::uuid) s) x$q$,
    'Imported');
  perform pg_temp.t('a percent sign in the search text is literal', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_query => '50%', p_course_id => '{course1}'::uuid) s) x$q$,
    'Iota');
  perform pg_temp.t('an underscore in the search text is literal', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_query => 'of_total', p_course_id => '{course1}'::uuid) s) x$q$,
    'Iota');
  perform pg_temp.t('the other near-identical stem is found on its own', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_query => '50X', p_course_id => '{course1}'::uuid) s) x$q$,
    'Jota');
  perform pg_temp.t('search text that matches nothing returns no rows', 'academic',
    $q$select count(*)::text from public.admin_question_search(p_query => 'zzzz-no-such-text', p_course_id => '{course1}'::uuid)$q$,
    '0');

  -- E. Filters -------------------------------------------------------------
  perform pg_temp.t('the course filter returns only that course', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_course_id => '{course2}'::uuid) s) x$q$,
    'Kappa');
  perform pg_temp.t('the topic filter returns only that topic, newest first', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_topic_id => '{topicB}'::uuid) s) x$q$,
    'Eta,Gamma,Delta');
  perform pg_temp.t('the difficulty filter: hard', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_difficulty => 'hard', p_course_id => '{course1}'::uuid) s) x$q$,
    'Gamma,Delta');
  perform pg_temp.t('the difficulty filter uses the live version, not the draft', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_difficulty => 'medium', p_course_id => '{course1}'::uuid) s) x$q$,
    'Beta,Imported');

  -- F. Views and ordering ------------------------------------------------------
  perform pg_temp.t('all: newest activity first, ties broken by id', 'academic',
    $q$select (string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
               = 'Eta,Alpha,Beta,Gamma,Delta,Jota,Iota,'
                 || (select string_agg(v.l, ',' order by v.q desc)
                     from (values ('Epsilon', '{qE}'::uuid), ('Imported', '{qF}'::uuid)) v(l, q)))::text
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 100) s) x$q$,
    'true');
  perform pg_temp.t('needs review (reviewer): oldest submission first', 'reviewer',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_view => 'needs_review', p_course_id => '{course1}'::uuid) s) x$q$,
    'Beta,Delta');
  perform pg_temp.t('needs review (Super Admin): their own submission is excluded', 'super',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_view => 'needs_review', p_course_id => '{course1}'::uuid) s) x$q$,
    'Beta');
  perform pg_temp.t('mine (academic admin): open versions they wrote', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_view => 'mine', p_course_id => '{course1}'::uuid) s) x$q$,
    'Alpha,Beta,Gamma,Jota,Iota');
  perform pg_temp.t('mine (second academic admin)', 'academic2',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_view => 'mine', p_course_id => '{course1}'::uuid) s) x$q$,
    'Eta');
  perform pg_temp.t('live', 'academic',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_view => 'live', p_course_id => '{course1}'::uuid) s) x$q$,
    'Alpha,Imported');
  perform pg_temp.t('retired', 'reviewer',
    $q$select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
       from (select s.stem, row_number() over () as rn from public.admin_question_search(p_view => 'retired', p_course_id => '{course1}'::uuid) s) x$q$,
    'Epsilon');

  -- G. Counts ----------------------------------------------------------------
  perform pg_temp.t('counts for an academic admin (all, review, mine, live, retired)', 'academic',
    $q$select c.all_count::text || ',' || c.needs_review_count::text || ',' || c.mine_count::text || ',' || c.live_count::text || ',' || c.retired_count::text
       from public.admin_question_counts(p_course_id => '{course1}'::uuid) c$q$,
    '9,1,5,2,1');
  perform pg_temp.t('counts for the reviewer', 'reviewer',
    $q$select c.all_count::text || ',' || c.needs_review_count::text || ',' || c.mine_count::text || ',' || c.live_count::text || ',' || c.retired_count::text
       from public.admin_question_counts(p_course_id => '{course1}'::uuid) c$q$,
    '9,2,0,2,1');
  perform pg_temp.t('counts for the Super Admin', 'super',
    $q$select c.all_count::text || ',' || c.needs_review_count::text || ',' || c.mine_count::text || ',' || c.live_count::text || ',' || c.retired_count::text
       from public.admin_question_counts(p_course_id => '{course1}'::uuid) c$q$,
    '9,1,1,2,1');
  perform pg_temp.t('counts for the second academic admin', 'academic2',
    $q$select c.all_count::text || ',' || c.needs_review_count::text || ',' || c.mine_count::text || ',' || c.live_count::text || ',' || c.retired_count::text
       from public.admin_question_counts(p_course_id => '{course1}'::uuid) c$q$,
    '9,2,1,2,1');
  perform pg_temp.t('counts for the second course', 'reviewer',
    $q$select c.all_count::text || ',' || c.needs_review_count::text || ',' || c.mine_count::text || ',' || c.live_count::text || ',' || c.retired_count::text
       from public.admin_question_counts(p_course_id => '{course2}'::uuid) c$q$,
    '1,0,0,1,0');
  perform pg_temp.t('counts follow the search text', 'academic',
    $q$select c.all_count::text || ',' || c.needs_review_count::text || ',' || c.mine_count::text || ',' || c.live_count::text || ',' || c.retired_count::text
       from public.admin_question_counts(p_query => 'question about', p_course_id => '{course1}'::uuid) c$q$,
    '7,1,3,2,1');

  -- H. Keyset paging ------------------------------------------------------------
  perform pg_temp.t('page 1 (limit 3): three rows plus one extra', 'academic',
    $q$select (select string_agg(split_part(x.stem, ' ', 1), ',' order by x.rn)
               from (select s.stem, row_number() over () as rn
                     from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 3) s) x
               where x.rn <= 3)
              || ':' ||
              (select count(*)::text from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 3))$q$,
    'Eta,Alpha,Beta:4');
  perform pg_temp.t('page 2 follows page 1 with no gap or repeat', 'academic',
    $q$with p1 as (
         select s.sort_at, s.question_id, row_number() over () as rn
         from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 3) s),
       c1 as (select sort_at, question_id from p1 where rn = 3),
       p2 as (
         select s.stem, row_number() over () as rn
         from c1, public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => c1.sort_at, p_cursor_id => c1.question_id, p_dir => 'next', p_limit => 3) s)
       select (select string_agg(split_part(stem, ' ', 1), ',' order by rn) from p2 where rn <= 3)
              || ':' || (select count(*)::text from p2)$q$,
    'Gamma,Delta,Jota:4');
  perform pg_temp.t('page 3 is the last page, with no extra row', 'academic',
    $q$with p1 as (
         select s.sort_at, s.question_id, row_number() over () as rn
         from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 3) s),
       c1 as (select sort_at, question_id from p1 where rn = 3),
       p2 as (
         select s.sort_at, s.question_id, row_number() over () as rn
         from c1, public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => c1.sort_at, p_cursor_id => c1.question_id, p_dir => 'next', p_limit => 3) s),
       c2 as (select sort_at, question_id from p2 where rn = 3),
       p3 as (
         select s.stem, row_number() over () as rn
         from c2, public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => c2.sort_at, p_cursor_id => c2.question_id, p_dir => 'next', p_limit => 3) s)
       select ((select string_agg(split_part(stem, ' ', 1), ',' order by rn) from p3)
               = 'Iota,' || (select string_agg(v.l, ',' order by v.q desc)
                             from (values ('Epsilon', '{qE}'::uuid), ('Imported', '{qF}'::uuid)) v(l, q)))::text
              || ':' || (select count(*)::text from p3)$q$,
    'true:3');
  perform pg_temp.t('going back from page 3 returns the rows just before it', 'academic',
    $q$with p1 as (
         select s.sort_at, s.question_id, row_number() over () as rn
         from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 3) s),
       c1 as (select sort_at, question_id from p1 where rn = 3),
       p2 as (
         select s.sort_at, s.question_id, row_number() over () as rn
         from c1, public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => c1.sort_at, p_cursor_id => c1.question_id, p_dir => 'next', p_limit => 3) s),
       c2 as (select sort_at, question_id from p2 where rn = 3),
       p3 as (
         select s.sort_at, s.question_id, row_number() over () as rn
         from c2, public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => c2.sort_at, p_cursor_id => c2.question_id, p_dir => 'next', p_limit => 3) s),
       c3 as (select sort_at, question_id from p3 where rn = 1),
       pv as (
         select s.stem, row_number() over () as rn
         from c3, public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => c3.sort_at, p_cursor_id => c3.question_id, p_dir => 'prev', p_limit => 3) s)
       select (select string_agg(split_part(stem, ' ', 1), ',' order by rn) from pv where rn > 1)
              || ':' || (select count(*)::text from pv)$q$,
    'Gamma,Delta,Jota:4');
  perform pg_temp.t('going back from page 2 reaches page 1 with no extra row', 'academic',
    $q$with p1 as (
         select s.sort_at, s.question_id, row_number() over () as rn
         from public.admin_question_search(p_course_id => '{course1}'::uuid, p_limit => 3) s),
       c1 as (select sort_at, question_id from p1 where rn = 3),
       p2 as (
         select s.sort_at, s.question_id, row_number() over () as rn
         from c1, public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => c1.sort_at, p_cursor_id => c1.question_id, p_dir => 'next', p_limit => 3) s),
       c2 as (select sort_at, question_id from p2 where rn = 1),
       pv as (
         select s.stem, row_number() over () as rn
         from c2, public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => c2.sort_at, p_cursor_id => c2.question_id, p_dir => 'prev', p_limit => 3) s)
       select (select string_agg(split_part(stem, ' ', 1), ',' order by rn) from pv)
              || ':' || (select count(*)::text from pv)$q$,
    'Eta,Alpha,Beta:3');
  perform pg_temp.t('two rows with the same time are not skipped or repeated going forward', 'academic',
    $q$select (count(*) = 1 and bool_and(s.question_id = least('{qE}'::uuid, '{qF}'::uuid)))::text
       from public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => now(), p_cursor_id => greatest('{qE}'::uuid, '{qF}'::uuid), p_dir => 'next', p_limit => 5) s$q$,
    'true');
  perform pg_temp.t('...and going back across the same tie', 'academic',
    $q$select (bool_or(s.question_id = greatest('{qE}'::uuid, '{qF}'::uuid)) and not bool_or(s.question_id = least('{qE}'::uuid, '{qF}'::uuid)))::text
       from public.admin_question_search(p_course_id => '{course1}'::uuid, p_cursor_at => now(), p_cursor_id => least('{qE}'::uuid, '{qF}'::uuid), p_dir => 'prev', p_limit => 5) s$q$,
    'true');
  perform pg_temp.t('the review queue pages oldest first, forward and back', 'reviewer',
    $q$with p1 as (
         select s.stem, s.sort_at, s.question_id, row_number() over () as rn
         from public.admin_question_search(p_view => 'needs_review', p_course_id => '{course1}'::uuid, p_limit => 1) s),
       c1 as (select sort_at, question_id from p1 where rn = 1),
       p2 as (
         select s.stem, s.sort_at, s.question_id, row_number() over () as rn
         from c1, public.admin_question_search(p_view => 'needs_review', p_course_id => '{course1}'::uuid, p_cursor_at => c1.sort_at, p_cursor_id => c1.question_id, p_dir => 'next', p_limit => 1) s),
       c2 as (select sort_at, question_id from p2 where rn = 1),
       p3 as (
         select s.stem, row_number() over () as rn
         from c2, public.admin_question_search(p_view => 'needs_review', p_course_id => '{course1}'::uuid, p_cursor_at => c2.sort_at, p_cursor_id => c2.question_id, p_dir => 'prev', p_limit => 1) s)
       select (select split_part(stem, ' ', 1) from p1 where rn = 1) || ':' || (select count(*)::text from p1)
              || '/' || (select split_part(stem, ' ', 1) from p2 where rn = 1) || ':' || (select count(*)::text from p2)
              || '/' || (select split_part(stem, ' ', 1) from p3 where rn = 1) || ':' || (select count(*)::text from p3)$q$,
    'Beta:2/Delta:1/Beta:1');

  -- I. Version history --------------------------------------------------------------
  perform pg_temp.t('history lists versions newest first with their states', 'academic',
    $q$select string_agg(h.version::text || ':' || h.review_state, ',' order by h.rn)
       from (select x.version, x.review_state, row_number() over () as rn from public.admin_question_history('{qA}'::uuid) x) h$q$,
    '2:draft,1:approved');
  perform pg_temp.t('history marks only the live version as live', 'academic',
    $q$select string_agg(h.is_live::text, ',' order by h.rn)
       from (select x.is_live, row_number() over () as rn from public.admin_question_history('{qA}'::uuid) x) h$q$,
    'false,true');
  perform pg_temp.t('history marks which versions were ever published', 'academic',
    $q$select string_agg(h.was_published::text, ',' order by h.rn)
       from (select x.was_published, row_number() over () as rn from public.admin_question_history('{qA}'::uuid) x) h$q$,
    'false,true');
  perform pg_temp.t('history shows a script-loaded question as imported', 'reviewer',
    $q$select string_agg(h.version::text || ':' || h.review_state, ',' order by h.rn)
       from (select x.version, x.review_state, row_number() over () as rn from public.admin_question_history('{qF}'::uuid) x) h$q$,
    '1:imported');
  perform pg_temp.t('history of an unknown question is refused', 'academic',
    $q$select 'ok' from public.admin_question_history('00000000-0000-0000-0000-000000000003'::uuid) limit 1$q$,
    'ERR:target_not_found');
  perform pg_temp.t('history of a missing question id is refused', 'academic',
    $q$select 'ok' from public.admin_question_history(null::uuid) limit 1$q$,
    'ERR:target_not_found');

  -- J. The access audit chain is untouched ----------------------------------------------
  perform pg_temp.t('the access audit hash chain still verifies', 'op',
    $q$select ok::text from public.admin_verify_audit_chain()$q$,
    'true');

  -- Report (always rolls back) ------------------------------------------------------------
  select count(*), count(*) filter (where not passed) into v_total, v_fail from t_results;

  select string_agg(
           case when passed then 'ok    ' else 'FAIL  ' end || name ||
           case when passed then '' else '   <-- ' || detail end,
           E'\n' order by n)
    into v_report
  from t_results;

  raise exception using
    errcode = 'P0001',
    message = format(E'%s: %s of %s checks passed (nothing was saved)\n%s',
                     case when v_fail = 0 then 'ALL PASS' else 'FAILURES' end,
                     v_total - v_fail, v_total, v_report);
end
$test$;