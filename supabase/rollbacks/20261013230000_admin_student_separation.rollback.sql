-- ROLLBACK for 20261013230000_admin_student_separation.sql
-- Restores the four functions to their definitions from 20261012180000 and
-- drops admin_find_user_by_email. Destroys no data. Run as postgres.
begin;

drop function if exists public.admin_find_user_by_email(text);

create or replace function public.admin_internal_require_actor(p_role public.admin_role default null)
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

create or replace function public.admin_get_my_access()
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

create or replace function public.admin_grant_role(p_target uuid, p_role public.admin_role, p_reason text)
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

create or replace function public.admin_bootstrap_super_admin(
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

notify pgrst, 'reload schema';

commit;