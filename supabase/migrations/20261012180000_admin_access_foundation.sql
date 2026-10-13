-- =============================================================================
-- UniExam Admin - Milestone 1B, Batch 1: admin access foundation
-- File: supabase/migrations/20261012180000_admin_access_foundation.sql
--
-- Creates ONLY new objects: 2 enums, 2 tables, 20 functions, triggers, indexes.
-- Touches no student table, policy, function, grant or default privilege.
--
-- Run ONCE, as the project owner role (postgres), against the DEVELOPMENT
-- project only, after you have confirmed the project ID in the dashboard.
-- It is deliberately not re-runnable: re-running fails on the first CREATE.
-- Run the whole script in one go; it is a single transaction.
-- =============================================================================
begin;

-- -----------------------------------------------------------------------------
-- 0. Preflight: abort early, with a clear message, instead of half-applying.
-- -----------------------------------------------------------------------------
do $$
begin
  if current_user in ('anon', 'authenticated', 'authenticator', 'service_role',
                      'supabase_auth_admin', 'supabase_storage_admin') then
    raise exception 'Run this migration as the project owner role (postgres), not as %.', current_user;
  end if;

  if to_regclass('public.admin_users') is not null
     or to_regclass('public.admin_audit_log') is not null
     or to_regtype('public.admin_role') is not null
     or to_regtype('public.admin_status') is not null then
    raise exception 'Admin access objects already exist. This migration is not re-runnable; use the rollback script first.';
  end if;

  -- Columns of Supabase Auth that the access checks read. If Supabase changes
  -- these, we want to know now, not when an admin is locked out.
  perform 1
  from (values
    ('users', 'id'), ('users', 'email'), ('users', 'email_confirmed_at'),
    ('sessions', 'id'), ('sessions', 'user_id'), ('sessions', 'aal'), ('sessions', 'not_after'),
    ('mfa_factors', 'user_id'), ('mfa_factors', 'factor_type'), ('mfa_factors', 'status')
  ) as r(t, c)
  where not exists (
    select 1 from pg_attribute a
    where a.attrelid = to_regclass('auth.' || r.t)
      and a.attname = r.c
      and not a.attisdropped
  );
  if found then
    raise exception 'Expected Supabase Auth columns are missing (auth.users / auth.sessions / auth.mfa_factors). Aborting.';
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- 1. Types
-- -----------------------------------------------------------------------------
create type public.admin_role as enum (
  'super_admin',
  'academic_admin',
  'question_reviewer',
  'support_admin',
  'analytics_viewer'
);

create type public.admin_status as enum ('active', 'suspended', 'revoked');

-- -----------------------------------------------------------------------------
-- 2. Tables
-- -----------------------------------------------------------------------------
-- One row per admin identity. Role and status live ONLY here and are read from
-- the database on every check, never from the JWT, so changes apply at once.
create table public.admin_users (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       public.admin_role   not null,
  status     public.admin_status not null default 'active',
  created_at timestamptz not null default now(),
  created_by uuid,                       -- null = created by a database operator
  updated_at timestamptz not null default now(),
  updated_by uuid                        -- null = changed by a database operator
);

-- At most ONE active Super Admin, enforced by the database itself.
create unique index admin_users_single_active_super_admin
  on public.admin_users ((role))
  where role = 'super_admin' and status = 'active';

-- Append-only audit log with a hash chain (tamper evidence, see notes).
create table public.admin_audit_log (
  id              bigint generated always as identity primary key,
  occurred_at     timestamptz not null default now(),
  actor_kind      text   not null check (actor_kind in ('admin', 'operator')),
  actor_user_id   uuid,
  action          text   not null check (action in (
                    'admin.granted', 'admin.role_changed', 'admin.suspended',
                    'admin.reactivated', 'admin.revoked',
                    'super_admin.bootstrapped', 'super_admin.replaced')),
  target_user_id  uuid   not null,       -- deliberately NOT a foreign key: the log must outlive users
  before_state    jsonb,
  after_state     jsonb,
  reason          text   not null check (char_length(reason) between 10 and 500),
  db_session_user text   not null default session_user,
  txid            bigint not null default pg_catalog.txid_current(),
  prev_hash       text   not null,       -- filled by trigger
  row_hash        text   not null,       -- filled by trigger
  constraint admin_audit_actor_consistent
    check ((actor_kind = 'admin') = (actor_user_id is not null))
);

create index admin_audit_log_target_idx on public.admin_audit_log (target_user_id, id desc);
create index admin_audit_log_txid_idx   on public.admin_audit_log (txid);

comment on table public.admin_users is
  'UniExam Admin access records. No direct client access: RLS on, no policies, no grants. Changed only via admin_* functions.';
comment on table public.admin_audit_log is
  'Append-only, hash-chained audit trail of admin access changes. No direct client access.';

-- -----------------------------------------------------------------------------
-- 3. Internal helper functions (no EXECUTE for any API role; see section 6)
-- -----------------------------------------------------------------------------

-- One global lock serialises every admin mutation (grant, change, suspend,
-- reactivate, revoke, bootstrap) and every audit append. It is taken BEFORE
-- the caller is authorised, so authorisation is evaluated against fresh state.
create function public.admin_internal_lock()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('uniexam.admin.mutations', 0));
end
$$;

create function public.admin_internal_check_reason(p_reason text)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  if pg_catalog.char_length(v_reason) < 10 or pg_catalog.char_length(v_reason) > 500 then
    raise exception 'invalid_reason' using errcode = '22023',
      hint = 'A reason of 10 to 500 characters is required.';
  end if;
  return v_reason;
end
$$;

-- Session assurance for the CALLING user. Two separate facts are checked:
--   (a) ENROLMENT: the account has a verified TOTP factor (account property).
--   (b) ASSURANCE: this session actually completed a second factor, i.e. the
--       JWT says aal2 AND the live session row agrees (session property).
-- aal2 alone is not enough: a factor removed after the session was upgraded
-- would still show aal2 until the token expires, so (a) is checked on its own.
create function public.admin_internal_session_state()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid    uuid  := auth.uid();
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
  v_sid    uuid;
begin
  if v_uid is null then
    return 'no_session';
  end if;

  if not exists (
    select 1 from auth.mfa_factors f
    where f.user_id = v_uid
      and f.factor_type::text = 'totp'
      and f.status::text = 'verified'
  ) then
    return 'mfa_not_enrolled';
  end if;

  begin
    v_sid := (v_claims ->> 'session_id')::uuid;
  exception when others then
    v_sid := null;
  end;

  if (v_claims ->> 'aal') is distinct from 'aal2'
     or v_sid is null
     or not exists (
       select 1 from auth.sessions s
       where s.id = v_sid
         and s.user_id = v_uid
         and s.aal::text = 'aal2'
         and (s.not_after is null or s.not_after > pg_catalog.now())
     ) then
    return 'mfa_step_up_required';
  end if;

  return 'ok';
end
$$;

-- Returns the caller's id only if they are an ACTIVE admin (optionally with an
-- exact role) in a session that passes the MFA checks. Every failure raises the
-- same error, so callers learn nothing about why.
create function public.admin_internal_require_actor(p_role public.admin_role default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.admin_users%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select * into v_row from public.admin_users a where a.user_id = v_uid;

  if not found
     or v_row.status <> 'active'
     or public.admin_internal_session_state() <> 'ok'
     or (p_role is not null and v_row.role <> p_role) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  return v_uid;
end
$$;

create function public.admin_internal_audit(
  p_actor  uuid,
  p_action text,
  p_target uuid,
  p_before jsonb,
  p_after  jsonb,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.admin_audit_log
    (actor_kind, actor_user_id, action, target_user_id, before_state, after_state, reason)
  values
    (case when p_actor is null then 'operator' else 'admin' end,
     p_actor, p_action, p_target, p_before, p_after, p_reason);
end
$$;

create function public.admin_internal_audit_hash(p public.admin_audit_log)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.encode(
    pg_catalog.sha256(
      pg_catalog.convert_to(
        pg_catalog.concat_ws('|',
          p.id::text,
          pg_catalog.to_char(p.occurred_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'),
          coalesce(p.actor_user_id::text, ''),
          p.actor_kind,
          p.action,
          p.target_user_id::text,
          coalesce(p.before_state::text, ''),
          coalesce(p.after_state::text, ''),
          p.reason,
          p.db_session_user,
          p.txid::text,
          p.prev_hash),
        'UTF8')),
    'hex')
$$;

-- -----------------------------------------------------------------------------
-- 4. Trigger functions and triggers
-- -----------------------------------------------------------------------------

-- Generic blocker (audit log update/delete/truncate, admin_users truncate).
create function public.admin_block_trg()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '%', tg_argv[0] using errcode = '42501';
end
$$;

create trigger admin_audit_log_no_update_delete
  before update or delete on public.admin_audit_log
  for each row execute function public.admin_block_trg('audit_log_is_append_only');

create trigger admin_audit_log_no_truncate
  before truncate on public.admin_audit_log
  for each statement execute function public.admin_block_trg('audit_log_is_append_only');

create trigger admin_users_no_truncate
  before truncate on public.admin_users
  for each statement execute function public.admin_block_trg('admin_users_truncate_blocked');

-- Hash chain: each row commits to the previous row's hash.
create function public.admin_audit_chain_trg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev text;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('uniexam.admin.mutations', 0));
  select l.row_hash into v_prev from public.admin_audit_log l order by l.id desc limit 1;
  new.prev_hash := coalesce(v_prev, pg_catalog.repeat('0', 64));
  new.row_hash  := public.admin_internal_audit_hash(new);
  return new;
end
$$;

create trigger admin_audit_log_chain
  before insert on public.admin_audit_log
  for each row execute function public.admin_audit_chain_trg();

-- admin_users: identity fields are immutable; only revoked rows may be deleted
-- (so deleting an auth user cannot silently remove an active admin).
create function public.admin_users_guard_trg()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id
       or new.created_at <> old.created_at
       or new.created_by is distinct from old.created_by then
      raise exception 'admin_record_immutable_field' using errcode = '42501';
    end if;
    return new;
  end if;

  if old.status <> 'revoked' then
    raise exception 'admin_record_not_revoked' using errcode = '23503',
      hint = 'Revoke this admin before deleting the underlying user.';
  end if;
  return old;
end
$$;

create trigger admin_users_guard
  before update or delete on public.admin_users
  for each row execute function public.admin_users_guard_trg();

-- Atomicity guarantee enforced by the database: no admin_users row may be
-- inserted or changed in a transaction that did not also write an audit event
-- for that user. Checked at COMMIT, so a failed audit insert rolls back both.
create function public.admin_users_require_audit_trg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.admin_audit_log a
    where a.txid = pg_catalog.txid_current()
      and a.target_user_id = new.user_id
  ) then
    raise exception 'audit_required' using errcode = '23514';
  end if;
  return null;
end
$$;

create constraint trigger admin_users_require_audit
  after insert or update on public.admin_users
  deferrable initially deferred
  for each row execute function public.admin_users_require_audit_trg();

-- -----------------------------------------------------------------------------
-- 5. Callable functions
-- -----------------------------------------------------------------------------

-- 5.1 What may this session do? Reports only on the caller's own account.
create function public.admin_get_my_access()
returns table (state text, role public.admin_role)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.admin_users%rowtype;
  v_session text;
begin
  if v_uid is null then
    return query select 'none'::text, null::public.admin_role;
    return;
  end if;

  select * into v_row from public.admin_users a where a.user_id = v_uid;

  if not found or v_row.status = 'revoked' then
    return query select 'none'::text, null::public.admin_role;
  elsif v_row.status = 'suspended' then
    return query select 'suspended'::text, null::public.admin_role;
  else
    v_session := public.admin_internal_session_state();
    if v_session = 'ok' then
      return query select 'active'::text, v_row.role;
    elsif v_session = 'mfa_not_enrolled' then
      return query select 'mfa_enrollment_required'::text, null::public.admin_role;
    else
      return query select 'mfa_step_up_required'::text, null::public.admin_role;
    end if;
  end if;
end
$$;

-- 5.2 Grant (new admin, or re-grant after revocation). Never grants super_admin.
create function public.admin_grant_role(p_target uuid, p_role public.admin_role, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_reason text;
  v_row    public.admin_users%rowtype;
  v_before jsonb;
begin
  perform public.admin_internal_lock();
  v_actor  := public.admin_internal_require_actor('super_admin');
  v_reason := public.admin_internal_check_reason(p_reason);

  if p_target is null then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if p_target = v_actor then
    raise exception 'cannot_target_self' using errcode = '22023';
  end if;
  if p_role is null or p_role = 'super_admin' then
    raise exception 'role_not_assignable' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_target and u.email_confirmed_at is not null) then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;

  select * into v_row from public.admin_users a where a.user_id = p_target for update;

  if not found then
    insert into public.admin_users (user_id, role, status, created_by, updated_by)
    values (p_target, p_role, 'active', v_actor, v_actor);
    v_before := null;
  elsif v_row.status = 'revoked' then
    v_before := pg_catalog.jsonb_build_object('role', v_row.role, 'status', v_row.status);
    update public.admin_users
       set role = p_role, status = 'active', updated_at = pg_catalog.now(), updated_by = v_actor
     where user_id = p_target;
  else
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  perform public.admin_internal_audit(
    v_actor, 'admin.granted', p_target, v_before,
    pg_catalog.jsonb_build_object('role', p_role, 'status', 'active'), v_reason);
end
$$;

-- 5.3 Change the role of an active or suspended admin.
create function public.admin_change_role(p_target uuid, p_new_role public.admin_role, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_reason text;
  v_row    public.admin_users%rowtype;
begin
  perform public.admin_internal_lock();
  v_actor  := public.admin_internal_require_actor('super_admin');
  v_reason := public.admin_internal_check_reason(p_reason);

  if p_target is null then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if p_target = v_actor then
    raise exception 'cannot_target_self' using errcode = '22023';
  end if;
  if p_new_role is null or p_new_role = 'super_admin' then
    raise exception 'role_not_assignable' using errcode = '22023';
  end if;

  select * into v_row from public.admin_users a where a.user_id = p_target for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_row.role = 'super_admin' then
    raise exception 'cannot_modify_super_admin' using errcode = '22023';
  end if;
  if v_row.status = 'revoked' or v_row.role = p_new_role then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  update public.admin_users
     set role = p_new_role, updated_at = pg_catalog.now(), updated_by = v_actor
   where user_id = p_target;

  perform public.admin_internal_audit(
    v_actor, 'admin.role_changed', p_target,
    pg_catalog.jsonb_build_object('role', v_row.role, 'status', v_row.status),
    pg_catalog.jsonb_build_object('role', p_new_role, 'status', v_row.status), v_reason);
end
$$;

-- 5.4 Suspend an active admin.
create function public.admin_suspend(p_target uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_reason text;
  v_row    public.admin_users%rowtype;
begin
  perform public.admin_internal_lock();
  v_actor  := public.admin_internal_require_actor('super_admin');
  v_reason := public.admin_internal_check_reason(p_reason);

  if p_target is null then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if p_target = v_actor then
    raise exception 'cannot_target_self' using errcode = '22023';
  end if;

  select * into v_row from public.admin_users a where a.user_id = p_target for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_row.role = 'super_admin' then
    raise exception 'cannot_modify_super_admin' using errcode = '22023';
  end if;
  if v_row.status <> 'active' then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  update public.admin_users
     set status = 'suspended', updated_at = pg_catalog.now(), updated_by = v_actor
   where user_id = p_target;

  perform public.admin_internal_audit(
    v_actor, 'admin.suspended', p_target,
    pg_catalog.jsonb_build_object('role', v_row.role, 'status', v_row.status),
    pg_catalog.jsonb_build_object('role', v_row.role, 'status', 'suspended'), v_reason);
end
$$;

-- 5.5 Reactivate a suspended admin.
create function public.admin_reactivate(p_target uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_reason text;
  v_row    public.admin_users%rowtype;
begin
  perform public.admin_internal_lock();
  v_actor  := public.admin_internal_require_actor('super_admin');
  v_reason := public.admin_internal_check_reason(p_reason);

  if p_target is null then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if p_target = v_actor then
    raise exception 'cannot_target_self' using errcode = '22023';
  end if;

  select * into v_row from public.admin_users a where a.user_id = p_target for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_row.role = 'super_admin' then
    raise exception 'cannot_modify_super_admin' using errcode = '22023';
  end if;
  if v_row.status <> 'suspended' then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  update public.admin_users
     set status = 'active', updated_at = pg_catalog.now(), updated_by = v_actor
   where user_id = p_target;

  perform public.admin_internal_audit(
    v_actor, 'admin.reactivated', p_target,
    pg_catalog.jsonb_build_object('role', v_row.role, 'status', v_row.status),
    pg_catalog.jsonb_build_object('role', v_row.role, 'status', 'active'), v_reason);
end
$$;

-- 5.6 Revoke an active or suspended admin. The row is kept (status = revoked).
create function public.admin_revoke(p_target uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_reason text;
  v_row    public.admin_users%rowtype;
begin
  perform public.admin_internal_lock();
  v_actor  := public.admin_internal_require_actor('super_admin');
  v_reason := public.admin_internal_check_reason(p_reason);

  if p_target is null then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if p_target = v_actor then
    raise exception 'cannot_target_self' using errcode = '22023';
  end if;

  select * into v_row from public.admin_users a where a.user_id = p_target for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_row.role = 'super_admin' then
    raise exception 'cannot_modify_super_admin' using errcode = '22023';
  end if;
  if v_row.status = 'revoked' then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  update public.admin_users
     set status = 'revoked', updated_at = pg_catalog.now(), updated_by = v_actor
   where user_id = p_target;

  perform public.admin_internal_audit(
    v_actor, 'admin.revoked', p_target,
    pg_catalog.jsonb_build_object('role', v_row.role, 'status', v_row.status),
    pg_catalog.jsonb_build_object('role', v_row.role, 'status', 'revoked'), v_reason);
end
$$;

-- 5.7 Read: admin list (Super Admin only).
create function public.admin_list_admins()
returns table (
  user_id    uuid,
  email      text,
  role       public.admin_role,
  status     public.admin_status,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_internal_require_actor('super_admin');

  return query
    select a.user_id, u.email::text, a.role, a.status, a.created_at, a.updated_at
    from public.admin_users a
    join auth.users u on u.id = a.user_id
    order by a.created_at, a.user_id;
end
$$;

-- 5.8 Read: audit log page, newest first (Super Admin only).
create function public.admin_list_audit(p_limit integer default 50, p_before_id bigint default null)
returns table (
  id             bigint,
  occurred_at    timestamptz,
  actor_kind     text,
  actor_user_id  uuid,
  action         text,
  target_user_id uuid,
  before_state   jsonb,
  after_state    jsonb,
  reason         text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_internal_require_actor('super_admin');

  return query
    select l.id, l.occurred_at, l.actor_kind, l.actor_user_id, l.action,
           l.target_user_id, l.before_state, l.after_state, l.reason
    from public.admin_audit_log l
    where p_before_id is null or l.id < p_before_id
    order by l.id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
end
$$;

-- 5.9 OPERATOR ONLY. First provisioning and recovery of the Super Admin.
-- Must be run from the SQL editor / a database session, never from the app:
-- EXECUTE is granted to no API role, and it refuses any session that carries
-- an end-user identity.
create function public.admin_bootstrap_super_admin(
  p_user_id          uuid,
  p_reason           text,
  p_replace_existing boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reason text;
  v_old    public.admin_users%rowtype;
  v_cur    public.admin_users%rowtype;
  v_before jsonb;
begin
  if auth.uid() is not null then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  perform public.admin_internal_lock();
  v_reason := public.admin_internal_check_reason(p_reason);

  if p_user_id is null
     or not exists (select 1 from auth.users u where u.id = p_user_id and u.email_confirmed_at is not null) then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;

  select * into v_old
  from public.admin_users a
  where a.role = 'super_admin' and a.status = 'active'
  for update;

  if found then
    if v_old.user_id = p_user_id then
      raise exception 'invalid_state' using errcode = '22023';
    end if;
    if not coalesce(p_replace_existing, false) then
      raise exception 'active_super_admin_exists' using errcode = '22023';
    end if;

    -- Retire the current Super Admin first so the unique index is never violated.
    update public.admin_users
       set status = 'revoked', updated_at = pg_catalog.now(), updated_by = null
     where user_id = v_old.user_id;

    perform public.admin_internal_audit(
      null, 'super_admin.replaced', v_old.user_id,
      pg_catalog.jsonb_build_object('role', v_old.role, 'status', v_old.status),
      pg_catalog.jsonb_build_object('role', v_old.role, 'status', 'revoked'), v_reason);
  end if;

  select * into v_cur from public.admin_users a where a.user_id = p_user_id for update;

  begin
    if found then
      v_before := pg_catalog.jsonb_build_object('role', v_cur.role, 'status', v_cur.status);
      update public.admin_users
         set role = 'super_admin', status = 'active', updated_at = pg_catalog.now(), updated_by = null
       where user_id = p_user_id;
    else
      v_before := null;
      insert into public.admin_users (user_id, role, status, created_by, updated_by)
      values (p_user_id, 'super_admin', 'active', null, null);
    end if;
  exception when unique_violation then
    raise exception 'single_super_admin_violation' using errcode = '23505';
  end;

  perform public.admin_internal_audit(
    null, 'super_admin.bootstrapped', p_user_id, v_before,
    pg_catalog.jsonb_build_object('role', 'super_admin', 'status', 'active'), v_reason);
end
$$;

-- 5.10 OPERATOR ONLY. Recompute the hash chain and report the first bad row.
-- The returned head_hash is what you should store outside the database.
create function public.admin_verify_audit_chain()
returns table (ok boolean, rows_checked bigint, first_bad_id bigint, head_hash text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r      public.admin_audit_log%rowtype;
  v_prev text   := pg_catalog.repeat('0', 64);
  v_n    bigint := 0;
  v_bad  bigint;
begin
  for r in select * from public.admin_audit_log order by id loop
    v_n := v_n + 1;
    if r.prev_hash <> v_prev or r.row_hash <> public.admin_internal_audit_hash(r) then
      v_bad := r.id;
      exit;
    end if;
    v_prev := r.row_hash;
  end loop;

  return query select (v_bad is null), v_n, v_bad, v_prev;
end
$$;

-- -----------------------------------------------------------------------------
-- 6. Privileges. The default privileges in this project hand ALL on new tables
--    and EXECUTE on new functions to anon, authenticated and service_role, and
--    revoking from PUBLIC alone does not remove those explicit grants. So every
--    role is revoked by name, then the few intended grants are made.
-- -----------------------------------------------------------------------------
alter table public.admin_users     enable row level security;
alter table public.admin_audit_log enable row level security;
-- Deliberately no policies: with RLS on and no policy, every row is denied to
-- any role that is subject to RLS, even if a table grant were added later.

revoke all on table public.admin_users, public.admin_audit_log
  from public, anon, authenticated, service_role;
revoke all on sequence public.admin_audit_log_id_seq
  from public, anon, authenticated, service_role;

revoke all on function public.admin_internal_lock()                                          from public, anon, authenticated, service_role;
revoke all on function public.admin_internal_check_reason(text)                              from public, anon, authenticated, service_role;
revoke all on function public.admin_internal_session_state()                                 from public, anon, authenticated, service_role;
revoke all on function public.admin_internal_require_actor(public.admin_role)                from public, anon, authenticated, service_role;
revoke all on function public.admin_internal_audit(uuid, text, uuid, jsonb, jsonb, text)     from public, anon, authenticated, service_role;
revoke all on function public.admin_internal_audit_hash(public.admin_audit_log)              from public, anon, authenticated, service_role;
revoke all on function public.admin_block_trg()                                              from public, anon, authenticated, service_role;
revoke all on function public.admin_audit_chain_trg()                                        from public, anon, authenticated, service_role;
revoke all on function public.admin_users_guard_trg()                                        from public, anon, authenticated, service_role;
revoke all on function public.admin_users_require_audit_trg()                                from public, anon, authenticated, service_role;
revoke all on function public.admin_get_my_access()                                          from public, anon, authenticated, service_role;
revoke all on function public.admin_grant_role(uuid, public.admin_role, text)                from public, anon, authenticated, service_role;
revoke all on function public.admin_change_role(uuid, public.admin_role, text)               from public, anon, authenticated, service_role;
revoke all on function public.admin_suspend(uuid, text)                                      from public, anon, authenticated, service_role;
revoke all on function public.admin_reactivate(uuid, text)                                   from public, anon, authenticated, service_role;
revoke all on function public.admin_revoke(uuid, text)                                       from public, anon, authenticated, service_role;
revoke all on function public.admin_list_admins()                                            from public, anon, authenticated, service_role;
revoke all on function public.admin_list_audit(integer, bigint)                              from public, anon, authenticated, service_role;
revoke all on function public.admin_bootstrap_super_admin(uuid, text, boolean)               from public, anon, authenticated, service_role;
revoke all on function public.admin_verify_audit_chain()                                     from public, anon, authenticated, service_role;

-- The only functions the app may call. Each one authorises the caller itself.
grant execute on function public.admin_get_my_access()                           to authenticated;
grant execute on function public.admin_grant_role(uuid, public.admin_role, text)  to authenticated;
grant execute on function public.admin_change_role(uuid, public.admin_role, text) to authenticated;
grant execute on function public.admin_suspend(uuid, text)                        to authenticated;
grant execute on function public.admin_reactivate(uuid, text)                     to authenticated;
grant execute on function public.admin_revoke(uuid, text)                         to authenticated;
grant execute on function public.admin_list_admins()                              to authenticated;
grant execute on function public.admin_list_audit(integer, bigint)                to authenticated;

-- -----------------------------------------------------------------------------
-- 7. Self-check: fail the whole migration if the privilege model is not what
--    this file intends. Nothing is committed unless every assertion holds.
-- -----------------------------------------------------------------------------
do $$
declare
  v_all     text[] := array[
    'admin_internal_lock', 'admin_internal_check_reason', 'admin_internal_session_state',
    'admin_internal_require_actor', 'admin_internal_audit', 'admin_internal_audit_hash',
    'admin_block_trg', 'admin_audit_chain_trg', 'admin_users_guard_trg',
    'admin_users_require_audit_trg', 'admin_get_my_access', 'admin_grant_role',
    'admin_change_role', 'admin_suspend', 'admin_reactivate', 'admin_revoke',
    'admin_list_admins', 'admin_list_audit', 'admin_bootstrap_super_admin',
    'admin_verify_audit_chain'];
  v_app     text[] := array[
    'admin_get_my_access', 'admin_grant_role', 'admin_change_role', 'admin_suspend',
    'admin_reactivate', 'admin_revoke', 'admin_list_admins', 'admin_list_audit'];
  r         record;
  v_t       text;
  v_n       integer := 0;
begin
  for r in
    select p.oid, p.proname, p.proconfig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any (v_all)
  loop
    v_n := v_n + 1;

    if has_function_privilege('anon', r.oid, 'execute')
       or has_function_privilege('service_role', r.oid, 'execute') then
      raise exception 'Self-check failed: anon/service_role can execute %', r.proname;
    end if;

    if has_function_privilege('authenticated', r.oid, 'execute') <> (r.proname = any (v_app)) then
      raise exception 'Self-check failed: unexpected authenticated EXECUTE state on %', r.proname;
    end if;

    if r.proconfig is null
       or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
      raise exception 'Self-check failed: % has no fixed search_path', r.proname;
    end if;
  end loop;

  if v_n <> cardinality(v_all) then
    raise exception 'Self-check failed: expected % admin functions, found %', cardinality(v_all), v_n;
  end if;

  foreach v_t in array array['public.admin_users', 'public.admin_audit_log'] loop
    if has_table_privilege('anon', v_t, 'select, insert, update, delete, truncate, references, trigger')
       or has_table_privilege('authenticated', v_t, 'select, insert, update, delete, truncate, references, trigger')
       or has_table_privilege('service_role', v_t, 'select, insert, update, delete, truncate, references, trigger') then
      raise exception 'Self-check failed: an API role has a privilege on %', v_t;
    end if;
    if not (select c.relrowsecurity from pg_class c where c.oid = v_t::regclass) then
      raise exception 'Self-check failed: RLS is not enabled on %', v_t;
    end if;
  end loop;
end
$$;

-- Ask PostgREST to refresh its schema cache so the new RPCs are visible.
notify pgrst, 'reload schema';

commit;