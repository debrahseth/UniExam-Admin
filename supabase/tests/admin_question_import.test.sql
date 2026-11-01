-- =============================================================================
-- UniExam Admin - database tests for question import
-- File: supabase/tests/admin_question_import.test.sql
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

  if to_regprocedure('public.admin_question_import_batch(jsonb)') is null then
    raise exception 'Apply migration 20261031150000 first. Aborting.';
  end if;

  if exists (select 1 from public.courses where code in ('ZZI101', 'ZZI102')) then
    raise exception 'A course with a test code (ZZI101 or ZZI102) already exists. Aborting.';
  end if;

  if exists (select 1 from public.questions where external_key like 'zzi.%') then
    raise exception 'A question with a test key (zzi.*) already exists. Aborting.';
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
    'super','academic','reviewer','support','analytics','outsider',
    'sid_super','sid_academic','sid_reviewer','sid_support','sid_analytics',
    'course1','course2','topicA','topicC']) as k;

  insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  select v, 'authenticated', 'authenticated', 'test-' || k || '@uniexam-test.invalid',
         now(), now(), now(), '{}'::jsonb, '{}'::jsonb
  from t_ids
  where k in ('super','academic','reviewer','support','analytics','outsider');

  insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
  select gen_random_uuid(), v, 'test factor',
         'totp'::auth.factor_type, 'verified'::auth.factor_status, now(), now()
  from t_ids
  where k in ('super','academic','reviewer','support','analytics');

  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  select s.v, o.v, now(), now(), 'aal2'::auth.aal_level
  from t_ids s
  join t_ids o on s.k = 'sid_' || o.k
  where o.k in ('super','academic','reviewer','support','analytics');

  insert into public.courses (id, code, title, is_active)
  select v, case k when 'course1' then 'ZZI101' else 'ZZI102' end, 'Import test course', true
  from t_ids
  where k in ('course1', 'course2');

  insert into public.topics (id, course_id, title, sort_order) values
    ((select v from t_ids where k = 'topicA'), (select v from t_ids where k = 'course1'), 'Import topic A', 1),
    ((select v from t_ids where k = 'topicC'), (select v from t_ids where k = 'course2'), 'Import topic C', 1);

  perform set_config('request.jwt.claims', '{}', true);
  perform public.admin_bootstrap_super_admin(
    (select v from t_ids where k = 'super'),
    'Test setup: install the test Super Admin', true);

  perform pg_temp.t('setup: Super Admin grants Academic admin', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{academic}'::uuid, 'academic_admin', 'Automated test reason')) s$q$, 'ok');
  perform pg_temp.t('setup: Super Admin grants Question reviewer', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{reviewer}'::uuid, 'question_reviewer', 'Automated test reason')) s$q$, 'ok');
  perform pg_temp.t('setup: Super Admin grants Support admin', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{support}'::uuid, 'support_admin', 'Automated test reason')) s$q$, 'ok');
  perform pg_temp.t('setup: Super Admin grants Analytics viewer', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{analytics}'::uuid, 'analytics_viewer', 'Automated test reason')) s$q$, 'ok');

  -- A. Gates ---------------------------------------------------------------
  perform pg_temp.t('anon cannot call the import function', 'anon',
    $q$select 'ok' from public.admin_question_import_batch('[]'::jsonb) limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('service_role cannot call the import function', 'svc',
    $q$select 'ok' from public.admin_question_import_batch('[]'::jsonb) limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('non-admin cannot import', 'outsider',
    $q$select 'ok' from public.admin_question_import_batch('[]'::jsonb) limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('support admin cannot import', 'support',
    $q$select 'ok' from public.admin_question_import_batch('[]'::jsonb) limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('analytics viewer cannot import', 'analytics',
    $q$select 'ok' from public.admin_question_import_batch('[]'::jsonb) limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('question reviewer cannot import', 'reviewer',
    $q$select 'ok' from public.admin_question_import_batch('[]'::jsonb) limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('academic admin can call it: an empty batch returns no rows', 'academic',
    $q$select count(*)::text from public.admin_question_import_batch('[]'::jsonb)$q$, '0');

  -- B. Whole-batch validation --------------------------------------------------
  perform pg_temp.t('a null batch is refused', 'academic',
    $q$select 'ok' from public.admin_question_import_batch(null::jsonb) limit 1$q$, 'ERR:invalid_batch');
  perform pg_temp.t('an object instead of an array is refused', 'academic',
    $q$select 'ok' from public.admin_question_import_batch('{"key":"zzi.x.001"}'::jsonb) limit 1$q$, 'ERR:invalid_batch');
  perform pg_temp.t('a string instead of an array is refused', 'academic',
    $q$select 'ok' from public.admin_question_import_batch('"abc"'::jsonb) limit 1$q$, 'ERR:invalid_batch');
  perform pg_temp.t('101 items are refused', 'academic',
    $q$select 'ok' from public.admin_question_import_batch((select jsonb_agg('{}'::jsonb) from generate_series(1, 101))) limit 1$q$,
    'ERR:batch_too_large');
  perform pg_temp.t('100 items are accepted (each empty one fails on its own)', 'academic',
    $q$select count(*)::text || ':' || (count(*) filter (where o_error = 'invalid_key'))::text
       from public.admin_question_import_batch((select jsonb_agg('{}'::jsonb) from generate_series(1, 100)))$q$,
    '100:100');

  -- C. Creating --------------------------------------------------------------
  perform pg_temp.t('a valid item is created, with its key and version id', 'academic',
    $q$select (o_outcome = 'created' and o_version_id is not null and o_error is null
               and o_key = 'zzi.t.001' and o_index = 1)::text
       from public.admin_question_import_batch('[{"key":"zzi.t.001","source":"Test source","course_id":"{course1}","topic_id":"{topicA}","stem":"Import stem one","options":["a1","b1","c1","d1"],"correct":"b","explanation":"Because.","difficulty":"easy"}]'::jsonb)$q$,
    'true');

  insert into t_ids (k, v)
  select 'qT1', q.id from public.questions q where q.external_key = 'zzi.t.001';
  insert into t_ids (k, v)
  select 'vT1', a.question_version_id
  from public.admin_question_versions a
  join public.questions q on q.id = a.question_id
  where q.external_key = 'zzi.t.001';

  perform pg_temp.t('the question has its key, course, topic and draft status', 'op',
    $q$select (q.external_key = 'zzi.t.001' and q.course_id = '{course1}'::uuid
               and q.topic_id = '{topicA}'::uuid and q.status = 'draft' and q.published_version is null)::text
       from public.questions q where q.external_key = 'zzi.t.001'$q$,
    'true');
  perform pg_temp.t('the version has its source, number, difficulty, stem and options', 'op',
    $q$select (v.source = 'Test source' and v.version = 1 and v.difficulty = 'easy'
               and v.body ->> 'stem' = 'Import stem one'
               and jsonb_array_length(v.body -> 'options') = 4)::text
       from public.question_versions v where v.id = '{vT1}'::uuid$q$,
    'true');
  perform pg_temp.t('the answer key and explanation are stored', 'op',
    $q$select (s.correct_option_ids = array['b'] and s.explanation ->> 'text' = 'Because.')::text
       from public.question_version_solutions s where s.question_version_id = '{vT1}'::uuid$q$,
    'true');
  perform pg_temp.t('the admin record is a draft authored by the importing user', 'op',
    $q$select (a.state = 'draft' and a.author_id = '{academic}'::uuid)::text
       from public.admin_question_versions a where a.question_version_id = '{vT1}'::uuid$q$,
    'true');
  perform pg_temp.t('search finds it by key, as the author''s own open draft, not as imported', 'academic',
    $q$select (s.is_mine and not s.current_is_imported and s.open_state = 'draft')::text
       from public.admin_question_search(p_query => 'zzi.t.001', p_course_id => '{course1}'::uuid) s$q$,
    'true');

  -- D. Skips and repeat runs -----------------------------------------------------
  perform pg_temp.t('running the same item again is skipped', 'academic',
    $q$select o_outcome || ':' || coalesce(o_version_id::text, 'none') || ':' || coalesce(o_error, 'none')
       from public.admin_question_import_batch('[{"key":"zzi.t.001","source":"Test source","course_id":"{course1}","topic_id":"{topicA}","stem":"Import stem one","options":["a1","b1","c1","d1"],"correct":"b","explanation":"Because.","difficulty":"easy"}]'::jsonb)$q$,
    'skipped:none:none');
  perform pg_temp.t('an existing key is skipped even when the rest of the item is invalid', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none')
       from public.admin_question_import_batch('[{"key":"zzi.t.001","course_id":"{course1}","topic_id":"{topicA}","stem":"","options":["x"],"correct":"z","difficulty":"easy"}]'::jsonb)$q$,
    'skipped:none');
  perform pg_temp.t('skipping created nothing: still one question with that key', 'op',
    $q$select count(*)::text from public.questions q where q.external_key = 'zzi.t.001'$q$, '1');
  perform pg_temp.t('skipping created nothing: still one version', 'op',
    $q$select count(*)::text from public.question_versions v where v.question_id = '{qT1}'::uuid$q$, '1');
  perform pg_temp.t('the same key twice in one batch: created, then skipped', 'academic',
    $q$select string_agg(o_outcome, ',' order by o_index)
       from public.admin_question_import_batch('[{"key":"zzi.t.002","course_id":"{course1}","topic_id":"{topicA}","stem":"Twice","options":["x","y"],"correct":"a","difficulty":"easy"},{"key":"zzi.t.002","course_id":"{course1}","topic_id":"{topicA}","stem":"Twice","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'created,skipped');

  -- E. Items that fail: reported, and nothing is created --------------------------
  perform pg_temp.t('key too short', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"ab","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_key');
  perform pg_temp.t('key with a space', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi f 1","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_key');
  perform pg_temp.t('key starting with a dot', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":".zzi.bad","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_key');
  perform pg_temp.t('missing key', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_key');
  perform pg_temp.t('key that is a number', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":123,"course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_key');
  perform pg_temp.t('an item that is not an object', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') || ':' || coalesce(o_key, 'nokey') from public.admin_question_import_batch('[5]'::jsonb)$q$,
    'failed:invalid_item:nokey');
  perform pg_temp.t('empty stem', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.stem","course_id":"{course1}","topic_id":"{topicA}","stem":"","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_stem');
  perform pg_temp.t('stem that is not text', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.stem2","course_id":"{course1}","topic_id":"{topicA}","stem":42,"options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_stem');
  perform pg_temp.t('only one option', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.opt1","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_options');
  perform pg_temp.t('duplicate options (ignoring case)', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.opt2","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["Yes","yes"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_options');
  perform pg_temp.t('options that are not text', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.opt3","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":[1,2],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_options');
  perform pg_temp.t('seven options', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.opt4","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["a","b","c","d","e","f","g"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_options');
  perform pg_temp.t('options that are not an array', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.opt5","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":"x","correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_options');
  perform pg_temp.t('correct letter beyond the options', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.cor1","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"e","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_correct');
  perform pg_temp.t('correct given as an array (the app must unwrap it)', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.cor2","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":["a"],"difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_correct');
  perform pg_temp.t('correct missing', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.cor3","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_correct');
  perform pg_temp.t('unknown difficulty', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.dif1","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"impossible"}]'::jsonb)$q$,
    'failed:invalid_difficulty');
  perform pg_temp.t('difficulty missing', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.dif2","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a"}]'::jsonb)$q$,
    'failed:invalid_difficulty');
  perform pg_temp.t('explanation over 4000 characters', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none')
       from public.admin_question_import_batch(jsonb_build_array(jsonb_build_object(
         'key', 'zzi.f.exp1', 'course_id', '{course1}', 'topic_id', '{topicA}', 'stem', 'S',
         'options', jsonb_build_array('x', 'y'), 'correct', 'a', 'difficulty', 'easy',
         'explanation', repeat('e', 4001))))$q$,
    'failed:invalid_explanation');
  perform pg_temp.t('explanation that is not text', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.exp2","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy","explanation":5}]'::jsonb)$q$,
    'failed:invalid_explanation');
  perform pg_temp.t('course that does not exist', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.crs1","course_id":"00000000-0000-0000-0000-0000000000aa","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_course');
  perform pg_temp.t('course id that is not a uuid', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.crs2","course_id":"not-a-uuid","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_course');
  perform pg_temp.t('course missing', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.crs3","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_course');
  perform pg_temp.t('topic of another course', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.top1","course_id":"{course1}","topic_id":"{topicC}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_topic');
  perform pg_temp.t('topic missing', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.top2","course_id":"{course1}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_topic');
  perform pg_temp.t('source over 200 characters', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none')
       from public.admin_question_import_batch(jsonb_build_array(jsonb_build_object(
         'key', 'zzi.f.src1', 'source', repeat('s', 201), 'course_id', '{course1}', 'topic_id', '{topicA}',
         'stem', 'S', 'options', jsonb_build_array('x', 'y'), 'correct', 'a', 'difficulty', 'easy')))$q$,
    'failed:invalid_source');
  perform pg_temp.t('source that is not text', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.src2","source":5,"course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_source');
  perform pg_temp.t('source with a line break', 'academic',
    $q$select o_outcome || ':' || coalesce(o_error, 'none') from public.admin_question_import_batch('[{"key":"zzi.f.src3","source":"bad\nsource","course_id":"{course1}","topic_id":"{topicA}","stem":"S","options":["x","y"],"correct":"a","difficulty":"easy"}]'::jsonb)$q$,
    'failed:invalid_source');
  perform pg_temp.t('no failed item left a question behind', 'op',
    $q$select count(*)::text from public.questions q where q.external_key like 'zzi.f.%'$q$, '0');

  -- F. One bad item does not stop the others -----------------------------------------
  perform pg_temp.t('good, bad, good: created, failed, created', 'academic',
    $q$select string_agg(o_outcome, ',' order by o_index)
       from public.admin_question_import_batch('[{"key":"zzi.m.001","course_id":"{course1}","topic_id":"{topicA}","stem":"Mixed one","options":["x","y"],"correct":"a","difficulty":"easy"},{"key":"zzi.f.mix","course_id":"{course1}","topic_id":"{topicA}","stem":"","options":["x","y"],"correct":"a","difficulty":"easy"},{"key":"zzi.m.003","course_id":"{course1}","topic_id":"{topicA}","stem":"Mixed three","options":["x","y"],"correct":"b","difficulty":"hard"}]'::jsonb)$q$,
    'created,failed,created');
  perform pg_temp.t('only the two good items exist', 'op',
    $q$select count(*)::text from public.questions q where q.external_key like 'zzi.m.%'$q$, '2');
  perform pg_temp.t('the failed item left no question behind', 'op',
    $q$select count(*)::text from public.questions q where q.external_key = 'zzi.f.mix'$q$, '0');
  perform pg_temp.t('no question in the test course is left without a version', 'op',
    $q$select count(*)::text from public.questions q
       where q.course_id = '{course1}'::uuid
         and not exists (select 1 from public.question_versions v where v.question_id = q.id)$q$,
    '0');

  -- G. Source and explanation handling ----------------------------------------------
  perform pg_temp.t('source omitted, source blank, source trimmed, explanation omitted', 'academic',
    $q$select string_agg(o_outcome, ',' order by o_index)
       from public.admin_question_import_batch('[{"key":"zzi.n.001","course_id":"{course1}","topic_id":"{topicA}","stem":"N one","options":["x","y"],"correct":"a","difficulty":"easy"},{"key":"zzi.n.002","source":"   ","course_id":"{course1}","topic_id":"{topicA}","stem":"N two","options":["x","y"],"correct":"a","difficulty":"easy"},{"key":"zzi.n.003","source":"  Spaced source  ","course_id":"{course1}","topic_id":"{topicA}","stem":"N three","options":["x","y"],"correct":"a","difficulty":"easy"},{"key":"zzi.n.004","course_id":"{course1}","topic_id":"{topicA}","stem":"N four","options":["x","y"],"correct":"a","difficulty":"easy","explanation":null}]'::jsonb)$q$,
    'created,created,created,created');
  perform pg_temp.t('an omitted or blank source is stored as none', 'op',
    $q$select count(*)::text
       from public.question_versions v join public.questions q on q.id = v.question_id
       where q.external_key in ('zzi.n.001', 'zzi.n.002') and v.source is null$q$,
    '2');
  perform pg_temp.t('a source is stored trimmed', 'op',
    $q$select v.source
       from public.question_versions v join public.questions q on q.id = v.question_id
       where q.external_key = 'zzi.n.003'$q$,
    'Spaced source');
  perform pg_temp.t('an omitted explanation is stored as none', 'op',
    $q$select (s.explanation is null)::text
       from public.question_version_solutions s
       join public.question_versions v on v.id = s.question_version_id
       join public.questions q on q.id = v.question_id
       where q.external_key = 'zzi.n.004'$q$,
    'true');

  -- H. Roles and the review flow ------------------------------------------------------
  perform pg_temp.t('Super Admin can import', 'super',
    $q$select o_outcome from public.admin_question_import_batch('[{"key":"zzi.s.001","course_id":"{course1}","topic_id":"{topicA}","stem":"Super import","options":["x","y"],"correct":"a","difficulty":"medium"}]'::jsonb)$q$,
    'created');

  insert into t_ids (k, v)
  select 'vS1', a.question_version_id
  from public.admin_question_versions a
  join public.questions q on q.id = a.question_id
  where q.external_key = 'zzi.s.001';

  perform pg_temp.t('the author can submit an imported draft', 'academic',
    $q$select 'ok' from (select public.admin_question_submit('{vT1}'::uuid)) s$q$, 'ok');
  perform pg_temp.t('a reviewer can approve it', 'reviewer',
    $q$select 'ok' from (select public.admin_question_approve('{vT1}'::uuid)) s$q$, 'ok');
  perform pg_temp.t('it is published and keeps its key', 'op',
    $q$select (q.status = 'published' and q.published_version = 1 and q.external_key = 'zzi.t.001')::text
       from public.questions q where q.id = '{qT1}'::uuid$q$,
    'true');
  perform pg_temp.t('it keeps its source after publishing', 'op',
    $q$select v.source from public.question_versions v where v.id = '{vT1}'::uuid$q$,
    'Test source');
  perform pg_temp.t('importing the same key again after publishing is still skipped', 'academic',
    $q$select o_outcome from public.admin_question_import_batch('[{"key":"zzi.t.001","course_id":"{course1}","topic_id":"{topicA}","stem":"Import stem one","options":["a1","b1","c1","d1"],"correct":"b","difficulty":"easy"}]'::jsonb)$q$,
    'skipped');
  perform pg_temp.t('Super Admin can submit their own import', 'super',
    $q$select 'ok' from (select public.admin_question_submit('{vS1}'::uuid)) s$q$, 'ok');
  perform pg_temp.t('...but cannot approve it', 'super',
    $q$select 'ok' from (select public.admin_question_approve('{vS1}'::uuid)) s$q$, 'ERR:cannot_review_own');

  -- I. Function totals (pinned on purpose) -----------------------------------------------
  -- An unexpected new admin function, or one newly callable by signed-in users,
  -- must fail here so it is noticed. Update these numbers deliberately, in the
  -- same change as any migration that adds or drops admin functions:
  --   after 20261016120000_admin_review_catalog: 46 total, 27 callable
  --   after 20261031150000_admin_question_import: 47 total, 28 callable
  perform pg_temp.t('there are 47 admin functions in total', 'op',
    $q$select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\'$q$,
    '47');
  perform pg_temp.t('signed-in users can call exactly 28 of them', 'op',
    $q$select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'admin\_%' escape '\' and has_function_privilege('authenticated', p.oid, 'execute')$q$,
    '28');

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