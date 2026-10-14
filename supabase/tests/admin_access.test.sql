-- =============================================================================
-- UniExam Admin - database tests for the admin access functions
-- File: supabase/tests/admin_access.test.sql
--
-- Run in the Supabase SQL editor as postgres, DEVELOPMENT project only.
-- The whole script is one DO block that ends by raising an error whose message
-- is the report. That is deliberate: it guarantees a rollback, so nothing the
-- tests create (users, sessions, admin records, audit rows) is ever kept.
-- Read the report at the top of the red error box:
--   "ALL PASS: N of N checks passed"   or   "FAILURES: ..."
-- =============================================================================
do $test$
declare
  r        record;
  v_total  integer;
  v_fail   integer;
  v_report text;

  q_state text := 'select state from public.admin_get_my_access()';
  q_role  text := 'select role::text from public.admin_get_my_access()';
  q_list  text := 'select ''ok'' from public.admin_list_admins() limit 1';
  q_audit text := 'select ''ok'' from public.admin_list_audit(5, null) limit 1';
  q_find  text := 'select ''ok'' from public.admin_find_user_by_email(''nobody@example.com'') limit 1';
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

  if not exists (select 1 from public.profiles) then
    raise exception 'At least one student profile is needed for the student tests. Aborting.';
  end if;

  -- Scaffolding ----------------------------------------------------------
  create temp table t_ids (k text primary key, v uuid);
  create temp table t_results (n serial primary key, name text, passed boolean, detail text);

  -- Runs one statement as one simulated actor and records pass or fail.
  --   p_expect = 'ERR:text'  -> must fail with an error containing text
  --   p_expect = anything else -> must succeed and return exactly that text
  -- {name} placeholders in p_sql are replaced with that test user's id.
  create function pg_temp.t(p_name text, p_who text, p_sql text, p_expect text)
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
      ('anon',         'anon',          null,       null,    null),
      ('svc',          'service_role',  null,       null,    null),
      ('op',           'postgres',      null,       null,    null),
      ('op_as_super',  'postgres',      'super',    'aal2',  'sid_super_aal2'),
      ('nobody',       'authenticated', null,       null,    null),
      ('outsider',     'authenticated', 'outsider', 'aal2',  null),
      ('super',        'authenticated', 'super',    'aal2',  'sid_super_aal2'),
      ('super_aal1',   'authenticated', 'super',    'aal1',  'sid_super_aal1'),
      ('super_stale',  'authenticated', 'super',    'aal2',  'sid_super_aal1'),
      ('super_nosid',  'authenticated', 'super',    'aal2',  null),
      ('reviewer',     'authenticated', 'reviewer', 'aal2',  'sid_reviewer_aal2'),
      ('student',      'authenticated', 'student',  'aal2',  'sid_student_aal2')
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
    else
      v_pass := v_err is null and coalesce(v_out, '') = p_expect;
    end if;

    insert into t_results (name, passed, detail)
    values (p_name, v_pass, coalesce('error: ' || v_err, 'returned: ' || v_out, 'returned nothing'));
  end
  $f$;

  -- Test data ------------------------------------------------------------
  insert into t_ids (k, v)
  select k, gen_random_uuid()
  from unnest(array['super','reviewer','outsider','unconfirmed','newsuper']) as k;

  insert into t_ids (k, v)
  select 'student', id from public.profiles order by created_at limit 1;

  insert into t_ids (k, v)
  select 'sid_' || u || '_' || a, gen_random_uuid()
  from unnest(array['super','reviewer','student']) as u,
       unnest(array['aal1','aal2']) as a;

  insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  select v, 'authenticated', 'authenticated', 'test-' || k || '@uniexam-test.invalid',
         case when k = 'unconfirmed' then null else now() end,
         now(), now(), '{}'::jsonb, '{}'::jsonb
  from t_ids
  where k in ('super','reviewer','outsider','unconfirmed','newsuper');

  -- Verified authenticators for the Super Admin and the student. The reviewer
  -- gets one later, to test the "enrolment required" state first.
  insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
  select gen_random_uuid(), v, 'test factor',
         'totp'::auth.factor_type, 'verified'::auth.factor_status, now(), now()
  from t_ids
  where k in ('super','student');

  for r in select u from unnest(array['super','reviewer','student']) as u loop
    insert into auth.sessions (id, user_id, created_at, updated_at, aal)
    select s.v, o.v, now(), now(),
           (case when s.k like '%aal2' then 'aal2' else 'aal1' end)::auth.aal_level
    from t_ids s
    join t_ids o on o.k = r.u
    where s.k like 'sid\_' || r.u || '\_aal_';
  end loop;

  -- Install the test Super Admin. This temporarily revokes the real one; the
  -- final rollback restores it.
  perform set_config('request.jwt.claims', '{}', true);
  perform public.admin_bootstrap_super_admin(
    (select v from t_ids where k = 'super'),
    'Test setup: install the test Super Admin', true);

  -- A. Exposure: who may touch what at all ---------------------------------
  perform pg_temp.t('anon cannot call admin_get_my_access', 'anon', q_state, 'ERR:permission denied');
  perform pg_temp.t('anon cannot read admin_users', 'anon',
    $q$select count(*)::text from public.admin_users$q$, 'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot read admin_users', 'outsider',
    $q$select count(*)::text from public.admin_users$q$, 'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot read the audit table', 'outsider',
    $q$select count(*)::text from public.admin_audit_log$q$, 'ERR:permission denied');
  perform pg_temp.t('signed-in users cannot write admin_users', 'outsider',
    $q$insert into public.admin_users (user_id, role) values ('{outsider}', 'super_admin')$q$,
    'ERR:permission denied');
  perform pg_temp.t('even the Super Admin cannot call the bootstrap function', 'super',
    $q$select 'ok' from (select public.admin_bootstrap_super_admin('{outsider}'::uuid, 'This call must be refused', false)) s$q$,
    'ERR:permission denied');
  perform pg_temp.t('even the Super Admin cannot call the chain verifier', 'super',
    $q$select ok::text from public.admin_verify_audit_chain()$q$, 'ERR:permission denied');
  perform pg_temp.t('service_role cannot call admin_grant_role', 'svc',
    $q$select 'ok' from (select public.admin_grant_role('{reviewer}'::uuid, 'question_reviewer', 'This call must be refused')) s$q$,
    'ERR:permission denied');

  -- B. Access state ------------------------------------------------------
  perform pg_temp.t('no identity -> none', 'nobody', q_state, 'none');
  perform pg_temp.t('signed-in non-admin -> none', 'outsider', q_state, 'none');
  perform pg_temp.t('Super Admin with an aal2 session -> active', 'super', q_state, 'active');
  perform pg_temp.t('...and the role is super_admin', 'super', q_role, 'super_admin');
  perform pg_temp.t('aal1 session -> step-up required', 'super_aal1', q_state, 'mfa_step_up_required');
  perform pg_temp.t('aal2 token but aal1 session row -> step-up required', 'super_stale', q_state, 'mfa_step_up_required');
  perform pg_temp.t('aal2 token with no session id -> step-up required', 'super_nosid', q_state, 'mfa_step_up_required');

  -- C. Authorization and the grant, change, suspend, revoke lifecycle ----------
  perform pg_temp.t('non-admin cannot grant', 'outsider',
    $q$select 'ok' from (select public.admin_grant_role('{reviewer}'::uuid, 'question_reviewer', 'Automated test reason')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('non-admin cannot list admins', 'outsider', q_list, 'ERR:not_authorized');
  perform pg_temp.t('non-admin cannot read the audit log', 'outsider', q_audit, 'ERR:not_authorized');
  perform pg_temp.t('non-admin cannot look up users', 'outsider', q_find, 'ERR:not_authorized');
  perform pg_temp.t('Super Admin without aal2 cannot grant', 'super_aal1',
    $q$select 'ok' from (select public.admin_grant_role('{reviewer}'::uuid, 'question_reviewer', 'Automated test reason')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('grant needs a reason of 10+ characters', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{reviewer}'::uuid, 'question_reviewer', 'short')) s$q$,
    'ERR:invalid_reason');
  perform pg_temp.t('cannot grant yourself', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{super}'::uuid, 'question_reviewer', 'Automated test reason')) s$q$,
    'ERR:cannot_target_self');
  perform pg_temp.t('super_admin cannot be granted through the app', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{outsider}'::uuid, 'super_admin', 'Automated test reason')) s$q$,
    'ERR:role_not_assignable');
  perform pg_temp.t('cannot grant an unconfirmed account', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{unconfirmed}'::uuid, 'question_reviewer', 'Automated test reason')) s$q$,
    'ERR:target_not_found');
  perform pg_temp.t('cannot grant an unknown id', 'super',
    $q$select 'ok' from (select public.admin_grant_role('00000000-0000-0000-0000-000000000001'::uuid, 'question_reviewer', 'Automated test reason')) s$q$,
    'ERR:target_not_found');
  perform pg_temp.t('cannot grant a student', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{student}'::uuid, 'question_reviewer', 'Automated test reason')) s$q$,
    'ERR:target_is_student');
  perform pg_temp.t('grant works', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{reviewer}'::uuid, 'question_reviewer', 'Automated test reason')) s$q$,
    'ok');
  perform pg_temp.t('the new admin is active with the granted role', 'op',
    $q$select status::text || ':' || role::text from public.admin_users where user_id = '{reviewer}'$q$,
    'active:question_reviewer');
  perform pg_temp.t('the grant wrote exactly one audit row', 'op',
    $q$select count(*)::text from public.admin_audit_log where target_user_id = '{reviewer}' and action = 'admin.granted'$q$,
    '1');
  perform pg_temp.t('cannot grant an account that is already an admin', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{reviewer}'::uuid, 'support_admin', 'Automated test reason')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('admin without an authenticator -> enrolment required', 'reviewer', q_state, 'mfa_enrollment_required');

  insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
  select gen_random_uuid(), v, 'test factor',
         'totp'::auth.factor_type, 'verified'::auth.factor_status, now(), now()
  from t_ids
  where k = 'reviewer';

  perform pg_temp.t('admin with authenticator and aal2 session -> active', 'reviewer', q_state, 'active');
  perform pg_temp.t('...with the granted role', 'reviewer', q_role, 'question_reviewer');
  perform pg_temp.t('a non-Super admin cannot grant', 'reviewer',
    $q$select 'ok' from (select public.admin_grant_role('{outsider}'::uuid, 'analytics_viewer', 'Automated test reason')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('a non-Super admin cannot list admins', 'reviewer', q_list, 'ERR:not_authorized');
  perform pg_temp.t('change role works', 'super',
    $q$select 'ok' from (select public.admin_change_role('{reviewer}'::uuid, 'support_admin', 'Automated test reason')) s$q$,
    'ok');
  perform pg_temp.t('changing to the same role is refused', 'super',
    $q$select 'ok' from (select public.admin_change_role('{reviewer}'::uuid, 'support_admin', 'Automated test reason')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('cannot change a role to super_admin', 'super',
    $q$select 'ok' from (select public.admin_change_role('{reviewer}'::uuid, 'super_admin', 'Automated test reason')) s$q$,
    'ERR:role_not_assignable');
  perform pg_temp.t('suspend works', 'super',
    $q$select 'ok' from (select public.admin_suspend('{reviewer}'::uuid, 'Automated test reason')) s$q$,
    'ok');
  perform pg_temp.t('a suspended admin sees suspended', 'reviewer', q_state, 'suspended');
  perform pg_temp.t('suspension takes effect immediately on functions', 'reviewer', q_list, 'ERR:not_authorized');
  perform pg_temp.t('cannot suspend twice', 'super',
    $q$select 'ok' from (select public.admin_suspend('{reviewer}'::uuid, 'Automated test reason')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('reactivate works', 'super',
    $q$select 'ok' from (select public.admin_reactivate('{reviewer}'::uuid, 'Automated test reason')) s$q$,
    'ok');
  perform pg_temp.t('cannot reactivate an active admin', 'super',
    $q$select 'ok' from (select public.admin_reactivate('{reviewer}'::uuid, 'Automated test reason')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('revoke works', 'super',
    $q$select 'ok' from (select public.admin_revoke('{reviewer}'::uuid, 'Automated test reason')) s$q$,
    'ok');
  perform pg_temp.t('a revoked admin -> none', 'reviewer', q_state, 'none');
  perform pg_temp.t('cannot revoke twice', 'super',
    $q$select 'ok' from (select public.admin_revoke('{reviewer}'::uuid, 'Automated test reason')) s$q$,
    'ERR:invalid_state');
  perform pg_temp.t('a revoked admin can be granted again', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{reviewer}'::uuid, 'analytics_viewer', 'Automated test reason')) s$q$,
    'ok');
  perform pg_temp.t('cannot revoke yourself', 'super',
    $q$select 'ok' from (select public.admin_revoke('{super}'::uuid, 'Automated test reason')) s$q$,
    'ERR:cannot_target_self');

  -- D. Exactly one Super Admin, and the operator-only path ------------------
  perform pg_temp.t('second Super Admin refused without the replace flag', 'op',
    $q$select 'ok' from (select public.admin_bootstrap_super_admin('{newsuper}'::uuid, 'Second Super Admin attempt', false)) s$q$,
    'ERR:active_super_admin_exists');
  perform pg_temp.t('bootstrap refuses a student account', 'op',
    $q$select 'ok' from (select public.admin_bootstrap_super_admin('{student}'::uuid, 'Student bootstrap attempt', true)) s$q$,
    'ERR:target_is_student');
  perform pg_temp.t('bootstrap refuses an unconfirmed account', 'op',
    $q$select 'ok' from (select public.admin_bootstrap_super_admin('{unconfirmed}'::uuid, 'Unconfirmed bootstrap attempt', true)) s$q$,
    'ERR:target_not_found');
  perform pg_temp.t('bootstrap refuses a session carrying an end-user identity', 'op_as_super',
    $q$select 'ok' from (select public.admin_bootstrap_super_admin('{newsuper}'::uuid, 'Identity bootstrap attempt', true)) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('replacement works with the replace flag', 'op',
    $q$select 'ok' from (select public.admin_bootstrap_super_admin('{newsuper}'::uuid, 'Test replacement of the Super Admin', true)) s$q$,
    'ok');
  perform pg_temp.t('exactly one active Super Admin afterwards', 'op',
    $q$select count(*)::text from public.admin_users where role = 'super_admin' and status = 'active'$q$,
    '1');
  perform pg_temp.t('the replaced Super Admin is revoked', 'op',
    $q$select status::text from public.admin_users where user_id = '{super}'$q$,
    'revoked');
  perform pg_temp.t('the replaced Super Admin can no longer act', 'super',
    $q$select 'ok' from (select public.admin_grant_role('{outsider}'::uuid, 'analytics_viewer', 'Automated test reason')) s$q$,
    'ERR:not_authorized');
  perform pg_temp.t('the database refuses a second active Super Admin directly', 'op',
    $q$insert into public.admin_users (user_id, role, status) values ('{outsider}', 'super_admin', 'active')$q$,
    'ERR:admin_users_single_active_super_admin');
  perform pg_temp.t('the audit hash chain verifies', 'op',
    $q$select ok::text from public.admin_verify_audit_chain()$q$,
    'true');

  -- F. The audit log cannot be altered ----------------------------------------
  perform pg_temp.t('audit rows cannot be updated, even by the owner', 'op',
    $q$update public.admin_audit_log set reason = 'tampering attempt' where id = (select min(id) from public.admin_audit_log)$q$,
    'ERR:audit_log_is_append_only');
  perform pg_temp.t('audit rows cannot be deleted, even by the owner', 'op',
    $q$delete from public.admin_audit_log where id = (select min(id) from public.admin_audit_log)$q$,
    'ERR:audit_log_is_append_only');
  perform pg_temp.t('the audit log cannot be truncated, even by the owner', 'op',
    $q$truncate public.admin_audit_log$q$,
    'ERR:audit_log_is_append_only');

  -- G. An admin change without an audit row cannot commit ---------------------
  perform pg_temp.t('an admin_users change with no audit row is refused at commit', 'op',
    $q$insert into public.admin_users (user_id, role, status) values ('{outsider}', 'analytics_viewer', 'active'); set constraints public.admin_users_require_audit immediate;$q$,
    'ERR:audit_required');

  -- E. Student guard at runtime ----------------------------------------------
  perform pg_temp.t('setup: an admin record for a student account', 'op',
    $q$insert into public.admin_users (user_id, role, status) values ('{student}', 'question_reviewer', 'active')$q$,
    'ok');
  perform pg_temp.t('a student with an admin record, authenticator and aal2 -> none', 'student', q_state, 'none');
  perform pg_temp.t('...and cannot call admin functions', 'student', q_list, 'ERR:not_authorized');

  -- Report (always rolls back) ------------------------------------------------
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