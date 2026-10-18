-- =============================================================================
-- UniExam Admin - database tests for the reviewer catalog
-- File: supabase/tests/admin_review_catalog.test.sql
--
-- Run in the Supabase SQL editor as postgres, DEVELOPMENT project only.
-- One DO block that ends by raising an error whose message is the report. That
-- guarantees a rollback: the test programmes, courses, topics, questions, users,
-- sessions and admin records are never kept. Read the first line of the error:
--   "ALL PASS: N of N checks passed"   or   "FAILURES: ..."
-- =============================================================================
do $test$
declare
  v_total  integer;
  v_fail   integer;
  v_report text;

  v_uni uuid;
  v_c1 uuid; v_c2 uuid;
  v_t1 uuid; v_t2 uuid;
  v_v1 uuid; v_v2a uuid; v_v2b uuid; v_v3 uuid; v_v4 uuid; v_v5 uuid; v_v9 uuid;
  v_q1 uuid; v_q2 uuid; v_q3 uuid; v_q4 uuid; v_q5 uuid;
  v_q6 uuid; v_q7 uuid; v_q8 uuid; v_q9 uuid;
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

  if to_regprocedure('public.admin_catalog_topics(uuid, text)') is null then
    raise exception 'Apply migration 20261016120000 first. Aborting.';
  end if;

  if exists (select 1 from public.programmes where code in ('ZZPA', 'ZZPB', 'ZZPC', 'ZZPD'))
     or exists (select 1 from public.courses where code in ('ZZC1', 'ZZC2', 'ZZC3'))
     or exists (select 1 from public.levels where code in ('ZZL1', 'ZZL2'))
     or exists (select 1 from public.semesters where code in ('ZZS1', 'ZZS2')) then
    raise exception 'Test codes (ZZPA..ZZPD, ZZC1..ZZC3, ZZL1, ZZL2, ZZS1, ZZS2) already exist. Aborting.';
  end if;

  select id into v_uni from public.universities order by created_at limit 1;
  if v_uni is null then
    raise exception 'At least one university is needed for the test data. Aborting.';
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

  -- Creates a script-loaded question (live, optionally retired), the way the
  -- import scripts do: a published version, no admin review record.
  create function pg_temp.mk_imported(p_course uuid, p_topic uuid, p_stem text, p_retire boolean)
  returns uuid
  language plpgsql
  as $f$
  declare
    v_q uuid;
    v_v uuid;
  begin
    insert into public.questions (course_id, topic_id, status)
    values (p_course, p_topic, 'draft')
    returning id into v_q;

    insert into public.question_versions (question_id, version, type, body, difficulty)
    values (v_q, 1, 'mcq',
            jsonb_build_object('stem', p_stem,
                               'options', jsonb_build_array(
                                 jsonb_build_object('id', 'a', 'text', 'yes'),
                                 jsonb_build_object('id', 'b', 'text', 'no'))),
            'medium')
    returning id into v_v;

    insert into public.question_version_solutions (question_version_id, correct_option_ids)
    values (v_v, array['a']);

    perform public.publish_question_version(v_v);

    if p_retire then
      update public.questions set status = 'retired' where id = v_q;
    end if;
    return v_q;
  end
  $f$;

  -- Identities and catalogue data --------------------------------------------
  insert into t_ids (k, v)
  select k, gen_random_uuid()
  from unnest(array[
    'super','academic','academic2','reviewer','support','analytics','outsider',
    'sid_super','sid_academic','sid_academic2','sid_reviewer','sid_support','sid_analytics',
    'pA','pB','pC','pD','l1','l2','s1','s2',
    'psA11','psA12','psA21','psB11',
    'c1','c2','c3','t1','t2','t3','t4']) as k;

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

  insert into public.levels (id, university_id, code, name, sort_order) values
    ((select v from t_ids where k = 'l1'), v_uni, 'ZZL1', 'Test level 1', 9001),
    ((select v from t_ids where k = 'l2'), v_uni, 'ZZL2', 'Test level 2', 9002);

  insert into public.semesters (id, university_id, code, name, sort_order) values
    ((select v from t_ids where k = 's1'), v_uni, 'ZZS1', 'Test semester 1', 9001),
    ((select v from t_ids where k = 's2'), v_uni, 'ZZS2', 'Test semester 2', 9002);

  insert into public.programmes (id, university_id, name, code, is_active) values
    ((select v from t_ids where k = 'pA'), v_uni, 'ZZ Alpha programme', 'ZZPA', true),
    ((select v from t_ids where k = 'pB'), v_uni, 'ZZ Beta programme',  'ZZPB', true),
    ((select v from t_ids where k = 'pC'), v_uni, 'ZZ Gamma programme', 'ZZPC', true),
    ((select v from t_ids where k = 'pD'), v_uni, 'ZZ Delta programme', 'ZZPD', false);

  insert into public.courses (id, code, title, is_active)
  select v, case k when 'c1' then 'ZZC1' when 'c2' then 'ZZC2' else 'ZZC3' end,
         'Catalog test course ' || k, (k <> 'c3')
  from t_ids
  where k in ('c1', 'c2', 'c3');

  insert into public.programme_semesters (id, programme_id, level_id, semester_id)
  select (select v from t_ids where k = x.ps),
         (select v from t_ids where k = x.p),
         (select v from t_ids where k = x.l),
         (select v from t_ids where k = x.s)
  from (values ('psA11', 'pA', 'l1', 's1'),
               ('psA12', 'pA', 'l1', 's2'),
               ('psA21', 'pA', 'l2', 's1'),
               ('psB11', 'pB', 'l1', 's1')) as x(ps, p, l, s);

  -- ZZC1 is shared by both programmes and sits in two slots of the first.
  insert into public.programme_courses (programme_semester_id, course_id, classification)
  select (select v from t_ids where k = x.ps),
         (select v from t_ids where k = x.c),
         x.cl
  from (values ('psA11', 'c1', 'COMPULSORY'),
               ('psA12', 'c2', 'ELECTIVE'),
               ('psA21', 'c1', 'COMPULSORY'),
               ('psA21', 'c3', 'COMPULSORY'),
               ('psB11', 'c1', 'COMPULSORY')) as x(ps, c, cl);

  insert into public.topics (id, course_id, title, sort_order) values
    ((select v from t_ids where k = 't1'), (select v from t_ids where k = 'c1'), 'ZZ topic one',   1),
    ((select v from t_ids where k = 't2'), (select v from t_ids where k = 'c1'), 'ZZ topic two',   2),
    ((select v from t_ids where k = 't3'), (select v from t_ids where k = 'c1'), 'ZZ topic three', 3),
    ((select v from t_ids where k = 't4'), (select v from t_ids where k = 'c2'), 'ZZ topic four',  1);

  select v into v_c1 from t_ids where k = 'c1';
  select v into v_c2 from t_ids where k = 'c2';
  select v into v_t1 from t_ids where k = 't1';
  select v into v_t2 from t_ids where k = 't2';

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

  -- Question data, in the first course. Authors and the reviewer act through
  -- the real functions; the imported ones are inserted the way the scripts do.
  --   Q1  topic one  live
  --   Q2  topic one  live, with a version in review (another author)
  --   Q3  topic one  never published, open draft
  --   Q9  topic one  never published, submitted by the Super Admin
  --   Q4  topic two  never published, submitted
  --   Q5  topic two  retired
  --   Q6  topic two  imported, live
  --   Q7  no topic   imported, live
  --   Q8  no topic   imported, retired
  --   topic three has no questions
  execute 'reset role'; perform pg_temp.as_actor('academic');
  v_v1 := public.admin_question_create_draft(v_c1, v_t1, 'Catalog Q1 live in topic one', array['one','two'], 'a', null, 'easy');
  perform public.admin_question_submit(v_v1);
  v_v2a := public.admin_question_create_draft(v_c1, v_t1, 'Catalog Q2 live with a version in review', array['one','two'], 'a', null, 'easy');
  perform public.admin_question_submit(v_v2a);
  v_v5 := public.admin_question_create_draft(v_c1, v_t2, 'Catalog Q5 retired in topic two', array['one','two'], 'a', null, 'easy');
  perform public.admin_question_submit(v_v5);

  execute 'reset role'; perform pg_temp.as_actor('reviewer');
  perform public.admin_question_approve(v_v1);
  perform public.admin_question_approve(v_v2a);
  perform public.admin_question_approve(v_v5);

  execute 'reset role';
  select question_id into v_q2 from public.question_versions where id = v_v2a;
  select question_id into v_q5 from public.question_versions where id = v_v5;

  perform pg_temp.as_actor('reviewer');
  perform public.admin_question_retire(v_q5, 'Retired for the catalog test.');

  execute 'reset role'; perform pg_temp.as_actor('academic2');
  v_v2b := public.admin_question_create_version(v_q2, 'Catalog Q2 rewritten wording', array['x','y'], 'b', null, 'medium');
  perform public.admin_question_submit(v_v2b);

  execute 'reset role'; perform pg_temp.as_actor('academic');
  v_v3 := public.admin_question_create_draft(v_c1, v_t1, 'Catalog Q3 draft in topic one', array['one','two'], 'a', null, 'hard');
  v_v4 := public.admin_question_create_draft(v_c1, v_t2, 'Catalog Q4 submitted in topic two', array['one','two'], 'a', null, 'easy');
  perform public.admin_question_submit(v_v4);

  execute 'reset role'; perform pg_temp.as_actor('super');
  v_v9 := public.admin_question_create_draft(v_c1, v_t1, 'Catalog Q9 submitted by the Super Admin', array['one','two'], 'a', null, 'easy');
  perform public.admin_question_submit(v_v9);

  execute 'reset role';
  select question_id into v_q1 from public.question_versions where id = v_v1;
  select question_id into v_q3 from public.question_versions where id = v_v3;
  select question_id into v_q4 from public.question_versions where id = v_v4;
  select question_id into v_q9 from public.question_versions where id = v_v9;

  v_q6 := pg_temp.mk_imported(v_c1, v_t2, 'Catalog Q6 imported in topic two', false);
  v_q7 := pg_temp.mk_imported(v_c1, null, 'Catalog Q7 imported without a topic', false);
  v_q8 := pg_temp.mk_imported(v_c1, null, 'Catalog Q8 imported retired without a topic', true);

  -- Everything above shares one transaction time, so give the questions a known
  -- creation order and the open submissions known ages.
  update public.questions q
     set created_at = now() - interval '1 day' + x.m * interval '1 minute'
  from (values (v_q1, 1), (v_q2, 2), (v_q3, 3), (v_q9, 4),
               (v_q4, 1), (v_q5, 2), (v_q6, 3),
               (v_q7, 1), (v_q8, 2)) as x(id, m)
  where q.id = x.id;

  update public.admin_question_versions set submitted_at = now() - interval '2 hours' where question_version_id = v_v2b;
  update public.admin_question_versions set submitted_at = now() - interval '1 hour'  where question_version_id = v_v9;
  update public.admin_question_versions set submitted_at = now() - interval '3 hours' where question_version_id = v_v4;

  insert into t_ids (k, v) values ('qQ2', v_q2), ('vQ2b', v_v2b);

  -- A. Gates ---------------------------------------------------------------
  perform pg_temp.t('anon cannot call admin_catalog_programmes', 'anon',
    $q$select 'ok' from public.admin_catalog_programmes() limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('anon cannot call admin_catalog_courses', 'anon',
    $q$select 'ok' from public.admin_catalog_courses('{pA}'::uuid) limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('anon cannot call admin_catalog_topics', 'anon',
    $q$select 'ok' from public.admin_catalog_topics('{c1}'::uuid) limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('anon cannot call admin_topic_questions', 'anon',
    $q$select 'ok' from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid) limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('service_role cannot call admin_catalog_topics', 'svc',
    $q$select 'ok' from public.admin_catalog_topics('{c1}'::uuid) limit 1$q$, 'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot call the internal filter function', 'outsider',
    $q$select public.admin_internal_filter_match('all', null::text, false, false, false)::text$q$, 'ERR:permission denied');
  perform pg_temp.t('non-admin cannot list programmes', 'outsider',
    $q$select 'ok' from public.admin_catalog_programmes() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('support admin cannot list programmes', 'support',
    $q$select 'ok' from public.admin_catalog_programmes() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('analytics viewer cannot list programmes', 'analytics',
    $q$select 'ok' from public.admin_catalog_programmes() limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('non-admin cannot read topic cards', 'outsider',
    $q$select 'ok' from public.admin_catalog_topics('{c1}'::uuid) limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('support admin cannot read a topic question list', 'support',
    $q$select 'ok' from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid) limit 1$q$, 'ERR:not_authorized');
  perform pg_temp.t('academic admin can list programmes', 'academic',
    $q$select 'ok' from public.admin_catalog_programmes() limit 1$q$, 'ANY');
  perform pg_temp.t('question reviewer can list programmes', 'reviewer',
    $q$select 'ok' from public.admin_catalog_programmes() limit 1$q$, 'ANY');
  perform pg_temp.t('Super Admin can list programmes', 'super',
    $q$select 'ok' from public.admin_catalog_programmes() limit 1$q$, 'ANY');
  perform pg_temp.t('the four catalog functions are read-only (stable) and security definer', 'op',
    $q$select count(*)::text from pg_proc
       where pronamespace = 'public'::regnamespace
         and proname in ('admin_catalog_programmes', 'admin_catalog_courses', 'admin_catalog_topics', 'admin_topic_questions')
         and provolatile = 's' and prosecdef$q$,
    '4');
  perform pg_temp.t('there are 46 admin functions in total', 'op',
    $q$select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\'$q$,
    '46');
  perform pg_temp.t('signed-in users can call exactly 27 of them', 'op',
    $q$select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'admin\_%' escape '\' and has_function_privilege('authenticated', p.oid, 'execute')$q$,
    '27');

  -- B. Programme cards -------------------------------------------------------
  perform pg_temp.t('programmes come back by name with course count and active flag', 'reviewer',
    $q$select string_agg(x.code || ':' || x.course_count::text || ':' || x.is_active::text, ',' order by x.rn)
       from (select p.code, p.course_count, p.is_active, row_number() over () as rn
             from public.admin_catalog_programmes() p where p.code like 'ZZP%') x$q$,
    'ZZPA:3:true,ZZPB:1:true,ZZPD:0:false,ZZPC:0:true');
  perform pg_temp.t('a course in several slots counts once', 'reviewer',
    $q$select p.course_count::text from public.admin_catalog_programmes() p where p.code = 'ZZPA'$q$,
    '3');
  perform pg_temp.t('a programme with no courses is listed with 0', 'reviewer',
    $q$select p.course_count::text from public.admin_catalog_programmes() p where p.code = 'ZZPC'$q$,
    '0');
  perform pg_temp.t('an inactive programme is listed and flagged', 'reviewer',
    $q$select p.is_active::text from public.admin_catalog_programmes() p where p.code = 'ZZPD'$q$,
    'false');
  perform pg_temp.t('a shared course counts in each programme', 'reviewer',
    $q$select p.course_count::text from public.admin_catalog_programmes() p where p.code = 'ZZPB'$q$,
    '1');

  -- C. Course cards ----------------------------------------------------------
  perform pg_temp.t('course slots come back by level, semester and code', 'reviewer',
    $q$select string_agg(x.code || '@' || x.level_code || '/' || x.semester_code, ',' order by x.rn)
       from (select r.code, r.level_code, r.semester_code, row_number() over () as rn
             from public.admin_catalog_courses('{pA}'::uuid) r) x$q$,
    'ZZC1@ZZL1/ZZS1,ZZC2@ZZL1/ZZS2,ZZC1@ZZL2/ZZS1,ZZC3@ZZL2/ZZS1');
  perform pg_temp.t('topic counts come back per course', 'reviewer',
    $q$select string_agg(x.code || ':' || x.topic_count::text, ',' order by x.rn)
       from (select r.code, r.topic_count, row_number() over () as rn
             from public.admin_catalog_courses('{pA}'::uuid) r) x$q$,
    'ZZC1:3,ZZC2:1,ZZC1:3,ZZC3:0');
  perform pg_temp.t('a shared course shows the same topic count under the other programme', 'reviewer',
    $q$select r.topic_count::text from public.admin_catalog_courses('{pB}'::uuid) r where r.code = 'ZZC1'$q$,
    '3');
  perform pg_temp.t('the second programme has exactly one course slot', 'reviewer',
    $q$select count(*)::text from public.admin_catalog_courses('{pB}'::uuid)$q$,
    '1');
  perform pg_temp.t('an inactive course is listed and flagged', 'reviewer',
    $q$select r.is_active::text || ':' || r.classification from public.admin_catalog_courses('{pA}'::uuid) r where r.code = 'ZZC3'$q$,
    'false:COMPULSORY');
  perform pg_temp.t('an elective is marked as an elective', 'reviewer',
    $q$select r.is_active::text || ':' || r.classification from public.admin_catalog_courses('{pA}'::uuid) r where r.code = 'ZZC2'$q$,
    'true:ELECTIVE');
  perform pg_temp.t('level and semester names and sort values come back', 'reviewer',
    $q$select r.level_name || '/' || r.level_sort::text || '/' || r.semester_name || '/' || r.semester_sort::text
       from public.admin_catalog_courses('{pA}'::uuid) r where r.code = 'ZZC2'$q$,
    'Test level 1/9001/Test semester 2/9002');
  perform pg_temp.t('a programme with no courses returns no rows', 'reviewer',
    $q$select count(*)::text from public.admin_catalog_courses('{pC}'::uuid)$q$,
    '0');
  perform pg_temp.t('an unknown programme is refused', 'reviewer',
    $q$select 'ok' from public.admin_catalog_courses('00000000-0000-0000-0000-0000000000a1'::uuid) limit 1$q$,
    'ERR:target_not_found');
  perform pg_temp.t('a missing programme is refused', 'reviewer',
    $q$select 'ok' from public.admin_catalog_courses(null::uuid) limit 1$q$,
    'ERR:target_not_found');
  perform pg_temp.t('non-admin cannot read course cards', 'outsider',
    $q$select 'ok' from public.admin_catalog_courses('{pA}'::uuid) limit 1$q$,
    'ERR:not_authorized');

  -- D. Topic cards (title=total/live/retired/draft/waiting/mine) -----------------
  perform pg_temp.t('all (reviewer): every topic, the empty one with zeros, then No topic', 'reviewer',
    $q$select string_agg(x.title || '=' || x.total_count || '/' || x.live_count || '/' || x.retired_count || '/' || x.draft_count || '/' || x.waiting_count || '/' || x.mine_count, ',' order by x.rn)
       from (select t.title, t.total_count, t.live_count, t.retired_count, t.draft_count, t.waiting_count, t.mine_count, row_number() over () as rn
             from public.admin_catalog_topics('{c1}'::uuid, 'all') t) x$q$,
    'ZZ topic one=4/2/0/2/2/0,ZZ topic two=3/1/1/1/1/0,ZZ topic three=0/0/0/0/0/0,No topic=2/1/1/0/0/0');
  perform pg_temp.t('live (reviewer)', 'reviewer',
    $q$select string_agg(x.title || '=' || x.total_count || '/' || x.live_count || '/' || x.retired_count || '/' || x.draft_count || '/' || x.waiting_count || '/' || x.mine_count, ',' order by x.rn)
       from (select t.title, t.total_count, t.live_count, t.retired_count, t.draft_count, t.waiting_count, t.mine_count, row_number() over () as rn
             from public.admin_catalog_topics('{c1}'::uuid, 'live') t) x$q$,
    'ZZ topic one=2/2/0/0/1/0,ZZ topic two=1/1/0/0/0/0,No topic=1/1/0/0/0/0');
  perform pg_temp.t('retired (reviewer)', 'reviewer',
    $q$select string_agg(x.title || '=' || x.total_count || '/' || x.live_count || '/' || x.retired_count || '/' || x.draft_count || '/' || x.waiting_count || '/' || x.mine_count, ',' order by x.rn)
       from (select t.title, t.total_count, t.live_count, t.retired_count, t.draft_count, t.waiting_count, t.mine_count, row_number() over () as rn
             from public.admin_catalog_topics('{c1}'::uuid, 'retired') t) x$q$,
    'ZZ topic two=1/0/1/0/0/0,No topic=1/0/1/0/0/0');
  perform pg_temp.t('waiting for review (reviewer)', 'reviewer',
    $q$select string_agg(x.title || '=' || x.total_count || '/' || x.live_count || '/' || x.retired_count || '/' || x.draft_count || '/' || x.waiting_count || '/' || x.mine_count, ',' order by x.rn)
       from (select t.title, t.total_count, t.live_count, t.retired_count, t.draft_count, t.waiting_count, t.mine_count, row_number() over () as rn
             from public.admin_catalog_topics('{c1}'::uuid, 'needs_review') t) x$q$,
    'ZZ topic one=2/1/0/1/2/0,ZZ topic two=1/0/0/1/1/0');
  perform pg_temp.t('my work (academic admin): only open versions they wrote', 'academic',
    $q$select string_agg(x.title || '=' || x.total_count || '/' || x.live_count || '/' || x.retired_count || '/' || x.draft_count || '/' || x.waiting_count || '/' || x.mine_count, ',' order by x.rn)
       from (select t.title, t.total_count, t.live_count, t.retired_count, t.draft_count, t.waiting_count, t.mine_count, row_number() over () as rn
             from public.admin_catalog_topics('{c1}'::uuid, 'mine') t) x$q$,
    'ZZ topic one=1/0/0/1/0/1,ZZ topic two=1/0/0/1/1/1');
  perform pg_temp.t('my work (reviewer): nothing', 'reviewer',
    $q$select count(*)::text from public.admin_catalog_topics('{c1}'::uuid, 'mine')$q$,
    '0');
  perform pg_temp.t('my work (Super Admin)', 'super',
    $q$select string_agg(x.title || '=' || x.total_count || '/' || x.live_count || '/' || x.retired_count || '/' || x.draft_count || '/' || x.waiting_count || '/' || x.mine_count, ',' order by x.rn)
       from (select t.title, t.total_count, t.live_count, t.retired_count, t.draft_count, t.waiting_count, t.mine_count, row_number() over () as rn
             from public.admin_catalog_topics('{c1}'::uuid, 'mine') t) x$q$,
    'ZZ topic one=1/0/0/1/1/1');
  perform pg_temp.t('my work (second academic admin): a live question with their version in review', 'academic2',
    $q$select string_agg(x.title || '=' || x.total_count || '/' || x.live_count || '/' || x.retired_count || '/' || x.draft_count || '/' || x.waiting_count || '/' || x.mine_count, ',' order by x.rn)
       from (select t.title, t.total_count, t.live_count, t.retired_count, t.draft_count, t.waiting_count, t.mine_count, row_number() over () as rn
             from public.admin_catalog_topics('{c1}'::uuid, 'mine') t) x$q$,
    'ZZ topic one=1/1/0/0/1/1');
  perform pg_temp.t('all (academic admin): the same totals, with their own work counted', 'academic',
    $q$select string_agg(x.title || '=' || x.total_count || '/' || x.live_count || '/' || x.retired_count || '/' || x.draft_count || '/' || x.waiting_count || '/' || x.mine_count, ',' order by x.rn)
       from (select t.title, t.total_count, t.live_count, t.retired_count, t.draft_count, t.waiting_count, t.mine_count, row_number() over () as rn
             from public.admin_catalog_topics('{c1}'::uuid, 'all') t) x$q$,
    'ZZ topic one=4/2/0/2/2/1,ZZ topic two=3/1/1/1/1/1,ZZ topic three=0/0/0/0/0/0,No topic=2/1/1/0/0/0');
  perform pg_temp.t('waiting for review (Super Admin) includes their own submission', 'super',
    $q$select string_agg(x.title || '=' || x.total_count || '/' || x.live_count || '/' || x.retired_count || '/' || x.draft_count || '/' || x.waiting_count || '/' || x.mine_count, ',' order by x.rn)
       from (select t.title, t.total_count, t.live_count, t.retired_count, t.draft_count, t.waiting_count, t.mine_count, row_number() over () as rn
             from public.admin_catalog_topics('{c1}'::uuid, 'needs_review') t) x$q$,
    'ZZ topic one=2/1/0/1/2/1,ZZ topic two=1/0/0/1/1/0');
  perform pg_temp.t('live + retired + draft equals the total on every card', 'reviewer',
    $q$select bool_and(t.live_count + t.retired_count + t.draft_count = t.total_count)::text
       from public.admin_catalog_topics('{c1}'::uuid, 'all') t$q$,
    'true');
  perform pg_temp.t('an empty topic is hidden under a filter', 'reviewer',
    $q$select count(*)::text from public.admin_catalog_topics('{c1}'::uuid, 'live') t where t.title = 'ZZ topic three'$q$,
    '0');
  perform pg_temp.t('no No-topic row when the course has no such questions', 'reviewer',
    $q$select string_agg(x.title || '=' || x.total_count, ',' order by x.rn)
       from (select t.title, t.total_count, row_number() over () as rn
             from public.admin_catalog_topics('{c2}'::uuid, 'all') t) x$q$,
    'ZZ topic four=0');
  perform pg_temp.t('a filter with no matches returns no rows', 'reviewer',
    $q$select count(*)::text from public.admin_catalog_topics('{c2}'::uuid, 'live')$q$,
    '0');
  perform pg_temp.t('the No topic row has a null topic id', 'reviewer',
    $q$select (t.topic_id is null)::text from public.admin_catalog_topics('{c1}'::uuid, 'all') t where t.title = 'No topic'$q$,
    'true');
  perform pg_temp.t('an unknown filter is refused', 'reviewer',
    $q$select 'ok' from public.admin_catalog_topics('{c1}'::uuid, 'bogus') limit 1$q$,
    'ERR:invalid_filter');
  perform pg_temp.t('a missing filter is refused', 'reviewer',
    $q$select 'ok' from public.admin_catalog_topics('{c1}'::uuid, null::text) limit 1$q$,
    'ERR:invalid_filter');
  perform pg_temp.t('an unknown course is refused', 'reviewer',
    $q$select 'ok' from public.admin_catalog_topics('00000000-0000-0000-0000-0000000000a2'::uuid) limit 1$q$,
    'ERR:target_not_found');
  perform pg_temp.t('a missing course is refused', 'reviewer',
    $q$select 'ok' from public.admin_catalog_topics(null::uuid) limit 1$q$,
    'ERR:target_not_found');

  -- E. Every card total equals the length of its modal list ---------------------
  perform pg_temp.t('card totals equal list lengths: all', 'reviewer',
    $q$select bool_and(t.total_count = (select count(*) from public.admin_topic_questions('{c1}'::uuid, t.topic_id, 'all')))::text
       from public.admin_catalog_topics('{c1}'::uuid, 'all') t$q$,
    'true');
  perform pg_temp.t('card totals equal list lengths: waiting for review', 'reviewer',
    $q$select bool_and(t.total_count = (select count(*) from public.admin_topic_questions('{c1}'::uuid, t.topic_id, 'needs_review')))::text
       from public.admin_catalog_topics('{c1}'::uuid, 'needs_review') t$q$,
    'true');
  perform pg_temp.t('card totals equal list lengths: live', 'reviewer',
    $q$select bool_and(t.total_count = (select count(*) from public.admin_topic_questions('{c1}'::uuid, t.topic_id, 'live')))::text
       from public.admin_catalog_topics('{c1}'::uuid, 'live') t$q$,
    'true');
  perform pg_temp.t('card totals equal list lengths: retired', 'reviewer',
    $q$select bool_and(t.total_count = (select count(*) from public.admin_topic_questions('{c1}'::uuid, t.topic_id, 'retired')))::text
       from public.admin_catalog_topics('{c1}'::uuid, 'retired') t$q$,
    'true');
  perform pg_temp.t('card totals equal list lengths: my work', 'academic',
    $q$select bool_and(t.total_count = (select count(*) from public.admin_topic_questions('{c1}'::uuid, t.topic_id, 'mine')))::text
       from public.admin_catalog_topics('{c1}'::uuid, 'mine') t$q$,
    'true');

  -- F. The questions behind a card (version:review state, in modal order) ----------
  perform pg_temp.t('all, topic one: creation order, live version shown', 'reviewer',
    $q$select string_agg(x.version::text || ':' || x.review_state, ',' order by x.rn)
       from (select q.version, q.review_state, row_number() over () as rn
             from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid, 'all') q) x$q$,
    '1:approved,1:approved,1:draft,1:submitted');
  perform pg_temp.t('all, topic two: creation order', 'reviewer',
    $q$select string_agg(x.version::text || ':' || x.review_state, ',' order by x.rn)
       from (select q.version, q.review_state, row_number() over () as rn
             from public.admin_topic_questions('{c1}'::uuid, '{t2}'::uuid, 'all') q) x$q$,
    '1:submitted,1:approved,1:imported');
  perform pg_temp.t('all, no topic (null topic id): the imported questions', 'reviewer',
    $q$select string_agg(x.version::text || ':' || x.review_state, ',' order by x.rn)
       from (select q.version, q.review_state, row_number() over () as rn
             from public.admin_topic_questions('{c1}'::uuid, null::uuid, 'all') q) x$q$,
    '1:imported,1:imported');
  perform pg_temp.t('an empty topic has an empty list', 'reviewer',
    $q$select count(*)::text from public.admin_topic_questions('{c1}'::uuid, '{t3}'::uuid, 'all')$q$,
    '0');
  perform pg_temp.t('waiting for review, topic one: oldest submission first, version in review', 'reviewer',
    $q$select string_agg(x.version::text || ':' || x.review_state, ',' order by x.rn)
       from (select q.version, q.review_state, row_number() over () as rn
             from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid, 'needs_review') q) x$q$,
    '2:submitted,1:submitted');
  perform pg_temp.t('waiting for review, topic two', 'reviewer',
    $q$select string_agg(x.version::text || ':' || x.review_state, ',' order by x.rn)
       from (select q.version, q.review_state, row_number() over () as rn
             from public.admin_topic_questions('{c1}'::uuid, '{t2}'::uuid, 'needs_review') q) x$q$,
    '1:submitted');
  perform pg_temp.t('live, topic two', 'reviewer',
    $q$select string_agg(x.version::text || ':' || x.review_state, ',' order by x.rn)
       from (select q.version, q.review_state, row_number() over () as rn
             from public.admin_topic_questions('{c1}'::uuid, '{t2}'::uuid, 'live') q) x$q$,
    '1:imported');
  perform pg_temp.t('retired, topic two: the last published version', 'reviewer',
    $q$select string_agg(x.version::text || ':' || x.review_state, ',' order by x.rn)
       from (select q.version, q.review_state, row_number() over () as rn
             from public.admin_topic_questions('{c1}'::uuid, '{t2}'::uuid, 'retired') q) x$q$,
    '1:approved');
  perform pg_temp.t('my work (academic admin), topic one: their open draft', 'academic',
    $q$select string_agg(x.version::text || ':' || x.review_state, ',' order by x.rn)
       from (select q.version, q.review_state, row_number() over () as rn
             from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid, 'mine') q) x$q$,
    '1:draft');
  perform pg_temp.t('my work (second academic admin), topic one: the version in review, not the live one', 'academic2',
    $q$select string_agg(x.version::text || ':' || x.review_state, ',' order by x.rn)
       from (select q.version, q.review_state, row_number() over () as rn
             from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid, 'mine') q) x$q$,
    '2:submitted');
  perform pg_temp.t('under All, a live question with a version in review shows its live version', 'reviewer',
    $q$select (q.version = 1)::text
       from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid, 'all') q where q.question_id = '{qQ2}'::uuid$q$,
    'true');
  perform pg_temp.t('under Waiting for Review, the same question shows the version in review', 'reviewer',
    $q$select (q.version = 2 and q.version_id = '{vQ2b}'::uuid)::text
       from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid, 'needs_review') q where q.question_id = '{qQ2}'::uuid$q$,
    'true');
  perform pg_temp.t('a topic of another course is refused', 'reviewer',
    $q$select 'ok' from public.admin_topic_questions('{c1}'::uuid, '{t4}'::uuid, 'all') limit 1$q$,
    'ERR:target_not_found');
  perform pg_temp.t('an unknown course is refused for the question list', 'reviewer',
    $q$select 'ok' from public.admin_topic_questions('00000000-0000-0000-0000-0000000000a3'::uuid, null::uuid, 'all') limit 1$q$,
    'ERR:target_not_found');
  perform pg_temp.t('an unknown filter is refused for the question list', 'reviewer',
    $q$select 'ok' from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid, 'bogus') limit 1$q$,
    'ERR:invalid_filter');
  perform pg_temp.t('a missing filter is refused for the question list', 'reviewer',
    $q$select 'ok' from public.admin_topic_questions('{c1}'::uuid, '{t1}'::uuid, null::text) limit 1$q$,
    'ERR:invalid_filter');

  -- G. The access audit chain is untouched ------------------------------------------
  perform pg_temp.t('the access audit hash chain still verifies', 'op',
    $q$select ok::text from public.admin_verify_audit_chain()$q$,
    'true');

  -- Report (always rolls back) ----------------------------------------------------------
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