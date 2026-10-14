-- =============================================================================
-- UniExam Admin - database tests for question authoring and review
-- File: supabase/tests/admin_question_authoring.test.sql
--
-- Run in the Supabase SQL editor as postgres, DEVELOPMENT project only.
-- One DO block that ends by raising an error whose message is the report. That
-- guarantees a rollback: the test course, topics, questions, users, sessions and
-- admin records are never kept. Read the first line of the error:
--   "ALL PASS: N of N checks passed"   or   "FAILURES: ..."
-- =============================================================================
do $test$
declare
  v_total  integer;
  v_fail   integer;
  v_report text;
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

  if to_regclass('public.admin_question_versions') is null then
    raise exception 'Apply migration 20261014090000 first. Aborting.';
  end if;

  if exists (select 1 from public.courses where code in ('ZZT101', 'ZZT102')) then
    raise exception 'A course with a test code (ZZT101 or ZZT102) already exists. Aborting.';
  end if;

  -- Scaffolding ----------------------------------------------------------
  create temp table t_ids (k text primary key, v uuid);
  create temp table t_results (n serial primary key, name text, passed boolean, detail text);

  -- Runs one statement as one simulated actor and records pass or fail.
  --   p_expect 'ERR:text' -> must fail with an error containing text
  --   p_expect 'ANY'      -> must succeed, any result
  --   anything else       -> must succeed and return exactly that text
  --   p_store             -> on success, keep the returned uuid under this key
  -- {name} placeholders in p_sql are replaced with the id stored under that name.
  create function pg_temp.t(p_name text, p_who text, p_sql text, p_expect text, p_store text default null)
  returns void
  language plpgsql
  as $f$
  declare
    v_role text;
    v_user text;
    v_aal  text;
    v_sid  text;
    v_sql  text := p_sql;
    v_uid  uuid;
    v_sidv uuid;
    v_out  text;
    v_err  text;
    v_pass boolean;
    r      record;
  begin
    select m.r_, m.u_, m.a_, m.s_ into v_role, v_user, v_aal, v_sid
    from (values
      ('anon',          'anon',          null,        null,   null),
      ('svc',           'service_role',  null,        null,   null),
      ('op',            'postgres',      null,        null,   null),
      ('outsider',      'authenticated', 'outsider',  'aal2', null),
      ('super',         'authenticated', 'super',     'aal2', 'sid_super'),
      ('academic',      'authenticated', 'academic',  'aal2', 'sid_academic'),
      ('academic_aal1', 'authenticated', 'academic',  'aal1', 'sid_academic_aal1'),
      ('academic2',     'authenticated', 'academic2', 'aal2', 'sid_academic2'),
      ('reviewer',      'authenticated', 'reviewer',  'aal2', 'sid_reviewer'),
      ('support',       'authenticated', 'support',   'aal2', 'sid_support'),
      ('analytics',     'authenticated', 'analytics', 'aal2', 'sid_analytics')
    ) as m(w, r_, u_, a_, s_)
    where m.w = p_who;

    if v_role is null then
      raise exception 'unknown actor %', p_who;
    end if;

    for r in select k, v from t_ids loop
      v_sql := replace(v_sql, '{' || r.k || '}', r.v::text);
    end loop;

    select v into v_uid  from t_ids where k = v_user;
    select v into v_sidv from t_ids where k = v_sid;

    perform set_config(
      'request.jwt.claims',
      case when v_uid is null then '{}'
           else json_build_object('sub', v_uid, 'role', v_role,
                                  'aal', v_aal, 'session_id', v_sidv)::text end,
      true);

    begin
      execute format('set local role %I', v_role);
      if lower(ltrim(v_sql)) like 'select%' then
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

    if v_pass and p_store is not null then
      begin
        insert into t_ids (k, v) values (p_store, v_out::uuid);
      exception when others then
        v_pass := false;
        v_err := 'could not store the result: ' || sqlerrm;
      end;
    end if;

    insert into t_results (name, passed, detail)
    values (p_name, v_pass, coalesce('error: ' || v_err, 'returned: ' || v_out, 'returned nothing'));
  end
  $f$;

  -- Test data ------------------------------------------------------------
  insert into t_ids (k, v)
  select k, gen_random_uuid()
  from unnest(array[
    'super','academic','academic2','reviewer','support','analytics','outsider',
    'sid_super','sid_academic','sid_academic2','sid_reviewer','sid_support',
    'sid_analytics','sid_academic_aal1',
    'course1','course_off','topicA','topicB','topicX']) as k;

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

  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  select s.v, o.v, now(), now(), 'aal1'::auth.aal_level
  from t_ids s
  join t_ids o on o.k = 'academic'
  where s.k = 'sid_academic_aal1';

  insert into public.courses (id, code, title, is_active)
  select v, case k when 'course1' then 'ZZT101' else 'ZZT102' end,
         'Admin test course', (k = 'course1')
  from t_ids
  where k in ('course1', 'course_off');

  insert into public.topics (id, course_id, title, sort_order) values
    ((select v from t_ids where k = 'topicA'), (select v from t_ids where k = 'course1'),    'Test topic A', 1),
    ((select v from t_ids where k = 'topicB'), (select v from t_ids where k = 'course1'),    'Test topic B', 2),
    ((select v from t_ids where k = 'topicX'), (select v from t_ids where k = 'course_off'), 'Test topic X', 1);

  -- Install the test Super Admin (temporarily replaces the real one; the final
  -- rollback restores it).
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

  -- A. Exposure ------------------------------------------------------------
  perform pg_temp.t('anon cannot call admin_question_list', 'anon',
    $q$select 'ok' from public.admin_question_list() limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('service_role cannot call admin_question_approve', 'svc',
    $q$select 'ok' from (select public.admin_question_approve('00000000-0000-0000-0000-000000000001'::uuid)) s$q$,
    'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot call the internal content builder', 'outsider',
    $q$select 'ok' from public.admin_internal_build_question('x'::text, array['a','b']::text[], 'a'::text, null::text, 'easy'::public.question_difficulty) limit 1$q$,
    'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot call the internal role check', 'outsider',
    $q$select public.admin_internal_require_role(array['super_admin']::public.admin_role[])::text$q$,
    'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot read admin_question_versions', 'outsider',
    $q$select count(*)::text from public.admin_question_versions$q$, 'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot read the activity log', 'outsider',
    $q$select count(*)::text from public.admin_activity_log$q$, 'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot write admin_question_versions', 'outsider',
    $q$insert into public.admin_question_versions (question_version_id, question_id, author_id) values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid())$q$,
    'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot read answer keys directly', 'outsider',
    $q$select count(*)::text from public.question_version_solutions$q$, 'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot read question versions directly', 'outsider',
    $q$select count(*)::text from public.question_versions$q$, 'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot write questions directly', 'outsider',
    $q$insert into public.questions (course_id) values ('{course1}')$q$, 'ERR:permission denied');
  perform pg_temp.t('API roles have no privileges on the two new tables', 'op',
    $q$select bool_or(has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger'))::text
       from unnest(array['anon','authenticated','service_role']) r,
            unnest(array['public.admin_question_versions','public.admin_activity_log']) t$q$,
    'false');
  perform pg_temp.t('there are 37 admin functions in total', 'op',
    $q$select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\'$q$,
    '37');
  perform pg_temp.t('signed-in users can call exactly 20 of them', 'op',
    $q$select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'admin\_%' escape '\' and has_function_privilege('authenticated', p.oid, 'execute')$q$,
    '20');

  -- B. Role gates ----------------------------------------------------------
  perform pg_temp.t('non-admin cannot list questions', 'outsider',
    $q$select 'ok' from public.admin_question_list() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('support admin cannot list questions', 'support',
    $q$select 'ok' from public.admin_question_list() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('analytics viewer cannot list questions', 'analytics',
    $q$select 'ok' from public.admin_question_list() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('non-admin cannot create a draft', 'outsider',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('question reviewer cannot create a draft', 'reviewer',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('support admin cannot create a draft', 'support',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('academic admin without an aal2 session cannot create a draft', 'academic_aal1',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('academic admin can list questions', 'academic',
    $q$select 'ok' from public.admin_question_list() limit 1$q$, 'ANY');
  perform pg_temp.t('question reviewer can list questions', 'reviewer',
    $q$select 'ok' from public.admin_question_list() limit 1$q$, 'ANY');
  perform pg_temp.t('Super Admin can list questions', 'super',
    $q$select 'ok' from public.admin_question_list() limit 1$q$, 'ANY');
  perform pg_temp.t('an unknown list filter is refused', 'academic',
    $q$select 'ok' from public.admin_question_list(null, 'bogus') limit 1$q$, 'ERR:invalid_filter');

  -- C. Content rules -------------------------------------------------------
  perform pg_temp.t('a blank stem is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, '   ', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_stem');
  perform pg_temp.t('a stem over 2000 characters is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, repeat('x', 2001), array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_stem');
  perform pg_temp.t('a control character in the stem is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'bell' || chr(7), array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_stem');
  perform pg_temp.t('one option is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_options');
  perform pg_temp.t('seven options are refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['1','2','3','4','5','6','7'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_options');
  perform pg_temp.t('duplicate options (ignoring case) are refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['Same','same'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_options');
  perform pg_temp.t('a blank option is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','  '], 'a', null, 'easy')) s$q$,
    'ERR:invalid_options');
  perform pg_temp.t('a line break inside an option is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one', 'two' || E'\n' || 'three'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_options');
  perform pg_temp.t('an option over 500 characters is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one', repeat('x', 501)], 'a', null, 'easy')) s$q$,
    'ERR:invalid_options');
  perform pg_temp.t('an answer outside the options is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'c', null, 'easy')) s$q$,
    'ERR:invalid_correct');
  perform pg_temp.t('an answer that is not a letter a to f is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'z', null, 'easy')) s$q$,
    'ERR:invalid_correct');
  perform pg_temp.t('a missing answer is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], null::text, null, 'easy')) s$q$,
    'ERR:invalid_correct');
  perform pg_temp.t('a missing difficulty is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'a', null, null::public.question_difficulty)) s$q$,
    'ERR:invalid_difficulty');
  perform pg_temp.t('an explanation over 4000 characters is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'a', repeat('x', 4001), 'easy')) s$q$,
    'ERR:invalid_explanation');
  perform pg_temp.t('an inactive course is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course_off}'::uuid, '{topicX}'::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_course');
  perform pg_temp.t('an unknown course is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('00000000-0000-0000-0000-000000000002'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_course');
  perform pg_temp.t('a missing course is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft(null::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_course');
  perform pg_temp.t('a topic from another course is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, '{topicX}'::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_topic');
  perform pg_temp.t('a missing topic is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_create_draft('{course1}'::uuid, null::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_topic');

  -- D. A first draft -------------------------------------------------------
  perform pg_temp.t('academic admin creates a draft', 'academic',
    $q$select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'What is 2 + 2?', array['3','5','6','4'], 'd', 'Two plus two is four.', 'easy')::text$q$,
    'ANY', 'v1');
  perform pg_temp.t('setup: remember the question of the first draft', 'op',
    $q$select question_id::text from public.question_versions where id = '{v1}'$q$, 'ANY', 'q1');
  perform pg_temp.t('the new question is a draft and not published', 'op',
    $q$select q.status::text || ':' || coalesce(q.published_version::text, 'none') from public.questions q where q.id = '{q1}'$q$,
    'draft:none');
  perform pg_temp.t('the draft is recorded for its author in state draft', 'op',
    $q$select state::text || ':' || (author_id = '{academic}')::text from public.admin_question_versions where question_version_id = '{v1}'$q$,
    'draft:true');
  perform pg_temp.t('the stored body has only stem and options', 'op',
    $q$select string_agg(k, ',' order by k) from public.question_versions qv, jsonb_object_keys(qv.body) k where qv.id = '{v1}'$q$,
    'options,stem');
  perform pg_temp.t('option ids are generated as a, b, c, d in order', 'op',
    $q$select string_agg(o ->> 'id', ',' order by n) from public.question_versions qv, jsonb_array_elements(qv.body -> 'options') with ordinality as t(o, n) where qv.id = '{v1}'$q$,
    'a,b,c,d');
  perform pg_temp.t('the answer key holds the chosen option', 'op',
    $q$select correct_option_ids[1] from public.question_version_solutions where question_version_id = '{v1}'$q$,
    'd');
  perform pg_temp.t('the explanation is stored with the single key text', 'op',
    $q$select string_agg(k, ',') from public.question_version_solutions s, jsonb_object_keys(s.explanation) k where s.question_version_id = '{v1}'$q$,
    'text');
  perform pg_temp.t('the draft is not served to students', 'op',
    $q$select count(*)::text from public._practice_pool('{course1}'::uuid, null, 'MIXED')$q$,
    '0');
  perform pg_temp.t('academic admin creates a second draft with a line break and no explanation', 'academic',
    $q$select public.admin_question_create_draft('{course1}'::uuid, '{topicB}'::uuid, 'Line one' || E'\n' || 'line two', array['yes','no'], 'a', '   ', 'medium')::text$q$,
    'ANY', 'v2');
  perform pg_temp.t('a line break in a stem is kept', 'op',
    $q$select ((body ->> 'stem') like ('%' || E'\n' || '%'))::text from public.question_versions where id = '{v2}'$q$,
    'true');
  perform pg_temp.t('an empty explanation is stored as null', 'op',
    $q$select (explanation is null)::text from public.question_version_solutions where question_version_id = '{v2}'$q$,
    'true');

  -- E. Authorship, editing, submission --------------------------------------
  perform pg_temp.t('another academic admin cannot edit the draft', 'academic2',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1}'::uuid, '{topicA}'::uuid, 'Changed', array['x','y'], 'a', null, 'easy')) s$q$,
    'ERR:not_author');
  perform pg_temp.t('another academic admin cannot submit the draft', 'academic2',
    $q$select 'ok' from (select public.admin_question_submit('{v1}'::uuid)) s$q$,
    'ERR:not_author');
  perform pg_temp.t('another academic admin cannot discard the draft', 'academic2',
    $q$select 'ok' from (select public.admin_question_discard_draft('{v1}'::uuid)) s$q$,
    'ERR:not_author');
  perform pg_temp.t('a question reviewer cannot edit a draft', 'reviewer',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1}'::uuid, '{topicA}'::uuid, 'Changed', array['x','y'], 'a', null, 'easy')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('an invalid edit is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1}'::uuid, '{topicA}'::uuid, 'Changed', array['1','2','3','4','5','6','7'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_options');
  perform pg_temp.t('the author edits the draft to fewer options and a different answer', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1}'::uuid, '{topicA}'::uuid, 'What is 2 + 2?', array['4','5'], 'a', 'Two plus two is four.', 'easy')) s$q$,
    'ok');
  perform pg_temp.t('the edit replaced the options and the answer key', 'op',
    $q$select jsonb_array_length(qv.body -> 'options')::text || ':' || (select s.correct_option_ids[1] from public.question_version_solutions s where s.question_version_id = qv.id) from public.question_versions qv where qv.id = '{v1}'$q$,
    '2:a');
  perform pg_temp.t('a never-published draft can change its topic', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1}'::uuid, '{topicB}'::uuid, 'What is 2 + 2?', array['4','5'], 'a', 'Two plus two is four.', 'easy')) s$q$,
    'ok');
  perform pg_temp.t('the topic really changed', 'op',
    $q$select t.title from public.questions q join public.topics t on t.id = q.topic_id where q.id = '{q1}'$q$,
    'Test topic B');
  perform pg_temp.t('the author can read the answer key', 'academic',
    $q$select correct_option_id from public.admin_question_get('{v1}'::uuid)$q$,
    'a');
  perform pg_temp.t('get marks the author''s own version', 'academic',
    $q$select is_mine::text from public.admin_question_get('{v1}'::uuid)$q$,
    'true');
  perform pg_temp.t('get marks another admin''s version as not mine', 'reviewer',
    $q$select is_mine::text from public.admin_question_get('{v1}'::uuid)$q$,
    'false');
  perform pg_temp.t('a support admin cannot read a question', 'support',
    $q$select 'ok' from public.admin_question_get('{v1}'::uuid)$q$,
    'ERR:not_authorized');
  perform pg_temp.t('an analytics viewer cannot read a question', 'analytics',
    $q$select 'ok' from public.admin_question_get('{v1}'::uuid)$q$,
    'ERR:not_authorized');
  perform pg_temp.t('a question reviewer cannot submit', 'reviewer',
    $q$select 'ok' from (select public.admin_question_submit('{v1}'::uuid)) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('a draft cannot be approved', 'reviewer',
    $q$select 'ok' from (select public.admin_question_approve('{v1}'::uuid)) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('a draft cannot be rejected', 'reviewer',
    $q$select 'ok' from (select public.admin_question_reject('{v1}'::uuid, 'This should not be possible.')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('the author submits the draft', 'academic',
    $q$select 'ok' from (select public.admin_question_submit('{v1}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('the record is now submitted', 'op',
    $q$select state::text from public.admin_question_versions where question_version_id = '{v1}'$q$,
    'submitted');
  perform pg_temp.t('a submitted version cannot be submitted again', 'academic',
    $q$select 'ok' from (select public.admin_question_submit('{v1}'::uuid)) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('a submitted version cannot be edited', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1}'::uuid, '{topicB}'::uuid, 'What is 2 + 2?', array['4','5'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('a submitted version cannot be discarded', 'academic',
    $q$select 'ok' from (select public.admin_question_discard_draft('{v1}'::uuid)) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('an academic admin cannot approve', 'academic',
    $q$select 'ok' from (select public.admin_question_approve('{v1}'::uuid)) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('a support admin cannot approve', 'support',
    $q$select 'ok' from (select public.admin_question_approve('{v1}'::uuid)) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('an analytics viewer cannot reject', 'analytics',
    $q$select 'ok' from (select public.admin_question_reject('{v1}'::uuid, 'This should not be possible.')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('list: one submitted version in the test course', 'academic',
    $q$select count(*)::text from public.admin_question_list('{course1}'::uuid, 'submitted')$q$,
    '1');
  perform pg_temp.t('list: one draft version in the test course', 'academic',
    $q$select count(*)::text from public.admin_question_list('{course1}'::uuid, 'draft')$q$,
    '1');
  perform pg_temp.t('list: two versions in the test course without a filter', 'academic',
    $q$select count(*)::text from public.admin_question_list('{course1}'::uuid)$q$,
    '2');
  perform pg_temp.t('list: no script-loaded versions in the test course', 'academic',
    $q$select count(*)::text from public.admin_question_list('{course1}'::uuid, 'imported')$q$,
    '0');

  -- F. Reject, edit, resubmit, approve ---------------------------------------
  perform pg_temp.t('a rejection needs a reason of 10+ characters', 'reviewer',
    $q$select 'ok' from (select public.admin_question_reject('{v1}'::uuid, 'short')) s$q$,
    'ERR:invalid_reason');
  perform pg_temp.t('the reviewer rejects with a reason', 'reviewer',
    $q$select 'ok' from (select public.admin_question_reject('{v1}'::uuid, 'The distractors are too similar.')) s$q$,
    'ok');
  perform pg_temp.t('the rejection is stored with its note', 'op',
    $q$select state::text || ':' || review_note from public.admin_question_versions where question_version_id = '{v1}'$q$,
    'rejected:The distractors are too similar.');
  perform pg_temp.t('the rejection is logged with the reason', 'op',
    $q$select reason from public.admin_activity_log where target_id = '{v1}' and action = 'question.rejected'$q$,
    'The distractors are too similar.');
  perform pg_temp.t('a rejected version cannot be submitted until edited', 'academic',
    $q$select 'ok' from (select public.admin_question_submit('{v1}'::uuid)) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('editing a rejected version returns it to draft', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1}'::uuid, '{topicB}'::uuid, 'What is 2 + 2?', array['4','5'], 'a', 'Two plus two is four.', 'easy')) s$q$,
    'ok');
  perform pg_temp.t('the review fields are cleared', 'op',
    $q$select state::text || ':' || (review_note is null)::text || ':' || (reviewer_id is null)::text from public.admin_question_versions where question_version_id = '{v1}'$q$,
    'draft:true:true');
  perform pg_temp.t('the author resubmits', 'academic',
    $q$select 'ok' from (select public.admin_question_submit('{v1}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('the reviewer approves (this publishes)', 'reviewer',
    $q$select 'ok' from (select public.admin_question_approve('{v1}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('the record shows the reviewer', 'op',
    $q$select state::text || ':' || (reviewer_id = '{reviewer}')::text from public.admin_question_versions where question_version_id = '{v1}'$q$,
    'approved:true');
  perform pg_temp.t('the question is now published at version 1', 'op',
    $q$select q.status::text || ':' || q.published_version::text from public.questions q where q.id = '{q1}'$q$,
    'published:1');
  perform pg_temp.t('the published version is frozen by the student schema', 'op',
    $q$update public.question_versions set difficulty = 'hard' where id = '{v1}'$q$,
    'ERR:immutable');
  perform pg_temp.t('the approved question is served to students', 'op',
    $q$select count(*)::text from public._practice_pool('{course1}'::uuid, null, 'MIXED')$q$,
    '1');
  perform pg_temp.t('the approval is logged', 'op',
    $q$select count(*)::text from public.admin_activity_log where target_id = '{v1}' and action = 'question.approved'$q$,
    '1');
  perform pg_temp.t('an approved version cannot be approved again', 'reviewer',
    $q$select 'ok' from (select public.admin_question_approve('{v1}'::uuid)) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('an approved version cannot be rejected', 'reviewer',
    $q$select 'ok' from (select public.admin_question_reject('{v1}'::uuid, 'Too late to reject this.')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('an approved version cannot be edited', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1}'::uuid, '{topicB}'::uuid, 'What is 2 + 2?', array['4','5'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('an approved version cannot be discarded', 'academic',
    $q$select 'ok' from (select public.admin_question_discard_draft('{v1}'::uuid)) s$q$,
    'ERR:invalid_state');

  -- G. A new version of a published question ---------------------------------
  perform pg_temp.t('a new version can be drafted for a published question', 'academic',
    $q$select public.admin_question_create_version('{q1}'::uuid, 'What is 2 + 3?', array['5','6'], 'a', null, 'easy')::text$q$,
    'ANY', 'v1b');
  perform pg_temp.t('the new version is number 2', 'op',
    $q$select version::text from public.question_versions where id = '{v1b}'$q$,
    '2');
  perform pg_temp.t('only one open version per question', 'academic',
    $q$select 'ok' from (select public.admin_question_create_version('{q1}'::uuid, 'What is 2 + 4?', array['6','7'], 'a', null, 'easy')) s$q$,
    'ERR:open_version_exists');
  perform pg_temp.t('the live version is unchanged while version 2 is a draft', 'op',
    $q$select q.published_version::text || ':' || (select count(*)::text from public._practice_pool('{course1}'::uuid, null, 'MIXED')) from public.questions q where q.id = '{q1}'$q$,
    '1:1');
  perform pg_temp.t('the topic of a published question cannot change', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1b}'::uuid, '{topicA}'::uuid, 'What is 2 + 3?', array['5','6'], 'a', null, 'easy')) s$q$,
    'ERR:topic_locked');
  perform pg_temp.t('the same topic is accepted', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{v1b}'::uuid, '{topicB}'::uuid, 'What is 2 + 3?', array['5','6'], 'a', null, 'easy')) s$q$,
    'ok');
  perform pg_temp.t('the author submits version 2', 'academic',
    $q$select 'ok' from (select public.admin_question_submit('{v1b}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('the reviewer approves version 2', 'reviewer',
    $q$select 'ok' from (select public.admin_question_approve('{v1b}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('version 2 is now the live version', 'op',
    $q$select published_version::text from public.questions where id = '{q1}'$q$,
    '2');
  perform pg_temp.t('version 1 is kept and still marked published', 'op',
    $q$select (published_at is not null)::text from public.question_versions where id = '{v1}'$q$,
    'true');
  perform pg_temp.t('students are served version 2 only', 'op',
    $q$select string_agg(qv.version::text, ',') from public.question_versions qv where qv.id in (select p from public._practice_pool('{course1}'::uuid, null, 'MIXED') p)$q$,
    '2');

  -- H. Nobody reviews their own work ------------------------------------------
  perform pg_temp.t('the Super Admin drafts a question', 'super',
    $q$select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'What is the capital of Ghana?', array['Accra','Kumasi','Tamale'], 'a', null, 'easy')::text$q$,
    'ANY', 'v3');
  perform pg_temp.t('setup: remember the question of that draft', 'op',
    $q$select question_id::text from public.question_versions where id = '{v3}'$q$, 'ANY', 'q3');
  perform pg_temp.t('a new version cannot be drafted for an unpublished question', 'academic',
    $q$select 'ok' from (select public.admin_question_create_version('{q3}'::uuid, 'Another stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('the Super Admin submits their own draft', 'super',
    $q$select 'ok' from (select public.admin_question_submit('{v3}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('the Super Admin cannot approve their own version', 'super',
    $q$select 'ok' from (select public.admin_question_approve('{v3}'::uuid)) s$q$,
    'ERR:cannot_review_own');
  perform pg_temp.t('the Super Admin cannot reject their own version', 'super',
    $q$select 'ok' from (select public.admin_question_reject('{v3}'::uuid, 'Rejecting my own question.')) s$q$,
    'ERR:cannot_review_own');
  perform pg_temp.t('the database refuses reviewer = author directly', 'op',
    $q$update public.admin_question_versions set state = 'approved', reviewer_id = author_id, reviewed_at = now() where question_version_id = '{v3}'$q$,
    'ERR:admin_qv_reviewer_not_author');
  perform pg_temp.t('the database requires a note on a rejection', 'op',
    $q$update public.admin_question_versions set state = 'rejected', reviewer_id = '{reviewer}', reviewed_at = now() where question_version_id = '{v3}'$q$,
    'ERR:admin_qv_rejected_has_note');
  perform pg_temp.t('setup: academic admin drafts a fourth question', 'academic',
    $q$select public.admin_question_create_draft('{course1}'::uuid, '{topicA}'::uuid, 'Draft four', array['p','q'], 'a', null, 'hard')::text$q$,
    'ANY', 'v4');
  perform pg_temp.t('setup: remember the question of the fourth draft', 'op',
    $q$select question_id::text from public.question_versions where id = '{v4}'$q$, 'ANY', 'q4');
  perform pg_temp.t('the database refuses a draft jumping straight to approved', 'op',
    $q$update public.admin_question_versions set state = 'approved', submitted_at = now(), reviewer_id = '{reviewer}', reviewed_at = now() where question_version_id = '{v4}'$q$,
    'ERR:invalid_state');
  perform pg_temp.t('the database refuses any change to an approved record', 'op',
    $q$update public.admin_question_versions set review_note = null where question_version_id = '{v1}'$q$,
    'ERR:invalid_state');
  perform pg_temp.t('the database refuses a change of author', 'op',
    $q$update public.admin_question_versions set author_id = '{reviewer}' where question_version_id = '{v4}'$q$,
    'ERR:admin_question_record_immutable_field');
  perform pg_temp.t('the database refuses deleting an approved record', 'op',
    $q$delete from public.admin_question_versions where question_version_id = '{v1}'$q$,
    'ERR:admin_question_record_not_deletable');
  perform pg_temp.t('the reviewer approves the Super Admin''s version', 'reviewer',
    $q$select 'ok' from (select public.admin_question_approve('{v3}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('that question is now published', 'op',
    $q$select status::text from public.questions where id = '{q3}'$q$,
    'published');
  perform pg_temp.t('two questions are now served', 'op',
    $q$select count(*)::text from public._practice_pool('{course1}'::uuid, null, 'MIXED')$q$,
    '2');

  -- I. Retire and restore ----------------------------------------------------
  perform pg_temp.t('a new version is drafted for the second question', 'academic',
    $q$select public.admin_question_create_version('{q3}'::uuid, 'What is the capital city of Ghana?', array['Accra','Kumasi','Tamale'], 'a', null, 'easy')::text$q$,
    'ANY', 'v3b');
  perform pg_temp.t('the author submits that version', 'academic',
    $q$select 'ok' from (select public.admin_question_submit('{v3b}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('an academic admin cannot retire a question', 'academic',
    $q$select 'ok' from (select public.admin_question_retire('{q3}'::uuid, 'Not allowed to do this.')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('retiring needs a reason', 'reviewer',
    $q$select 'ok' from (select public.admin_question_retire('{q3}'::uuid, 'short')) s$q$,
    'ERR:invalid_reason');
  perform pg_temp.t('a draft question cannot be retired', 'reviewer',
    $q$select 'ok' from (select public.admin_question_retire('{q4}'::uuid, 'Retiring a draft question.')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('the reviewer retires a published question', 'reviewer',
    $q$select 'ok' from (select public.admin_question_retire('{q3}'::uuid, 'The question contains an outdated fact.')) s$q$,
    'ok');
  perform pg_temp.t('the status is retired', 'op',
    $q$select status::text from public.questions where id = '{q3}'$q$,
    'retired');
  perform pg_temp.t('a retired question is no longer served', 'op',
    $q$select count(*)::text from public._practice_pool('{course1}'::uuid, null, 'MIXED')$q$,
    '1');
  perform pg_temp.t('a retired question cannot be retired again', 'reviewer',
    $q$select 'ok' from (select public.admin_question_retire('{q3}'::uuid, 'Retiring it for a second time.')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('a new version cannot be drafted for a retired question', 'academic',
    $q$select 'ok' from (select public.admin_question_create_version('{q3}'::uuid, 'Another stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:question_retired');
  perform pg_temp.t('a version of a retired question cannot be approved', 'reviewer',
    $q$select 'ok' from (select public.admin_question_approve('{v3b}'::uuid)) s$q$,
    'ERR:question_retired');
  perform pg_temp.t('an academic admin cannot restore a question', 'academic',
    $q$select 'ok' from (select public.admin_question_restore('{q3}'::uuid, 'Not allowed to do this.')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('restoring needs a reason', 'reviewer',
    $q$select 'ok' from (select public.admin_question_restore('{q3}'::uuid, 'short')) s$q$,
    'ERR:invalid_reason');
  perform pg_temp.t('a published question cannot be restored', 'reviewer',
    $q$select 'ok' from (select public.admin_question_restore('{q1}'::uuid, 'Trying to restore a live question.')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('the reviewer restores the question', 'reviewer',
    $q$select 'ok' from (select public.admin_question_restore('{q3}'::uuid, 'The fact was checked and is correct.')) s$q$,
    'ok');
  perform pg_temp.t('the restored question is served again', 'op',
    $q$select count(*)::text from public._practice_pool('{course1}'::uuid, null, 'MIXED')$q$,
    '2');
  perform pg_temp.t('retire and restore are both logged with reasons', 'op',
    $q$select count(*)::text from public.admin_activity_log where target_id = '{q3}' and action in ('question.retired', 'question.restored') and reason is not null$q$,
    '2');
  perform pg_temp.t('the reviewer can approve the new version after the restore', 'reviewer',
    $q$select 'ok' from (select public.admin_question_approve('{v3b}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('the second question''s live version is now 2', 'op',
    $q$select published_version::text from public.questions where id = '{q3}'$q$,
    '2');

  -- J. Discarding drafts -------------------------------------------------------
  perform pg_temp.t('an invalid edit of the fourth draft is refused', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{v4}'::uuid, '{topicA}'::uuid, 'Draft four', array['1','2','3','4','5','6','7'], 'a', null, 'hard')) s$q$,
    'ERR:invalid_options');
  perform pg_temp.t('the author discards a never-published draft', 'academic',
    $q$select 'ok' from (select public.admin_question_discard_draft('{v4}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('the draft question went with it', 'op',
    $q$select count(*)::text from public.questions where id = '{q4}'$q$,
    '0');
  perform pg_temp.t('its review record is gone', 'op',
    $q$select count(*)::text from public.admin_question_versions where question_version_id = '{v4}'$q$,
    '0');
  perform pg_temp.t('the discard is logged', 'op',
    $q$select count(*)::text from public.admin_activity_log where target_id = '{v4}' and action = 'question.discarded'$q$,
    '1');
  perform pg_temp.t('a draft version is created for a published question', 'academic',
    $q$select public.admin_question_create_version('{q1}'::uuid, 'What is 2 + 5?', array['7','8'], 'a', null, 'easy')::text$q$,
    'ANY', 'v5');
  perform pg_temp.t('the author discards that draft version', 'academic',
    $q$select 'ok' from (select public.admin_question_discard_draft('{v5}'::uuid)) s$q$,
    'ok');
  perform pg_temp.t('the published question survives with its live version', 'op',
    $q$select (select count(*) from public.questions where id = '{q1}')::text || ':' || (select count(*) from public.question_versions where id = '{v5}')::text || ':' || (select published_version from public.questions where id = '{q1}')::text$q$,
    '1:0:2');

  -- K. Access changes apply at once -----------------------------------------------
  perform pg_temp.t('the Super Admin suspends the second academic admin', 'super',
    $q$select 'ok' from (select public.admin_suspend('{academic2}'::uuid, 'Automated test reason')) s$q$,
    'ok');
  perform pg_temp.t('the suspended academic admin is refused at once', 'academic2',
    $q$select 'ok' from public.admin_question_list() limit 1$q$,
    'ERR:not_authorized');
  perform pg_temp.t('the Super Admin reactivates that admin', 'super',
    $q$select 'ok' from (select public.admin_reactivate('{academic2}'::uuid, 'Automated test reason')) s$q$,
    'ok');
  perform pg_temp.t('the reactivated academic admin works again', 'academic2',
    $q$select 'ok' from public.admin_question_list() limit 1$q$,
    'ANY');

  -- L. The new tables resist tampering ----------------------------------------------
  perform pg_temp.t('activity rows cannot be updated, even by the owner', 'op',
    $q$update public.admin_activity_log set reason = 'tampering attempt text' where id = (select min(id) from public.admin_activity_log)$q$,
    'ERR:activity_log_is_append_only');
  perform pg_temp.t('activity rows cannot be deleted, even by the owner', 'op',
    $q$delete from public.admin_activity_log where id = (select min(id) from public.admin_activity_log)$q$,
    'ERR:activity_log_is_append_only');
  perform pg_temp.t('the activity log cannot be truncated, even by the owner', 'op',
    $q$truncate public.admin_activity_log$q$,
    'ERR:activity_log_is_append_only');
  perform pg_temp.t('the review table cannot be truncated, even by the owner', 'op',
    $q$truncate public.admin_question_versions$q$,
    'ERR:admin_question_versions_truncate_blocked');
  perform pg_temp.t('a retire entry without a reason is refused by the database', 'op',
    $q$insert into public.admin_activity_log (actor_user_id, actor_role, action, target_kind, target_id) values ('{super}', 'super_admin', 'question.retired', 'question', gen_random_uuid())$q$,
    'ERR:admin_activity_reason_rule');
  perform pg_temp.t('an approval entry carrying a reason is refused by the database', 'op',
    $q$insert into public.admin_activity_log (actor_user_id, actor_role, action, target_kind, target_id, reason) values ('{super}', 'super_admin', 'question.approved', 'question_version', gen_random_uuid(), 'This should not be here.')$q$,
    'ERR:admin_activity_reason_rule');

  -- M. Script-loaded (imported) versions ---------------------------------------------
  perform pg_temp.t('setup: find a script-loaded version', 'op',
    $q$select qv.id::text from public.question_versions qv where not exists (select 1 from public.admin_question_versions a where a.question_version_id = qv.id) limit 1$q$,
    'ANY', 'imp1');
  perform pg_temp.t('a script-loaded version is shown as imported', 'reviewer',
    $q$select review_state from public.admin_question_get('{imp1}'::uuid)$q$,
    'imported');
  perform pg_temp.t('a script-loaded version cannot be edited here', 'academic',
    $q$select 'ok' from (select public.admin_question_update_draft('{imp1}'::uuid, '{topicA}'::uuid, 'Valid stem', array['one','two'], 'a', null, 'easy')) s$q$,
    'ERR:target_not_found');
  perform pg_temp.t('a script-loaded version cannot be approved here', 'reviewer',
    $q$select 'ok' from (select public.admin_question_approve('{imp1}'::uuid)) s$q$,
    'ERR:target_not_found');
  perform pg_temp.t('a script-loaded version cannot be discarded here', 'academic',
    $q$select 'ok' from (select public.admin_question_discard_draft('{imp1}'::uuid)) s$q$,
    'ERR:target_not_found');

  -- N. The access audit chain is untouched ----------------------------------------------
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