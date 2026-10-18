-- =============================================================================
-- UniExam Admin - Milestone 1B, Batch 5: reviewer catalog
-- File: supabase/migrations/20261016120000_admin_review_catalog.sql
--
-- Creates ONLY 5 new functions. READ-ONLY: none of them writes anything. They read
-- the student catalogue tables and, through the per-question base function from
-- migration 20261015090000, the question and review tables. No table, type,
-- student definition, policy, trigger, grant or default privilege is changed.
--
-- Run ONCE as the project owner role (postgres), DEVELOPMENT project only.
-- Single transaction: any failure rolls everything back.
-- =============================================================================
begin;

-- -----------------------------------------------------------------------------
-- 0. Preflight
-- -----------------------------------------------------------------------------
do $$
begin
  if current_user in ('anon', 'authenticated', 'authenticator', 'service_role',
                      'supabase_auth_admin', 'supabase_storage_admin') then
    raise exception 'Run this migration as the project owner role (postgres), not as %.', current_user;
  end if;

  if to_regprocedure('public.admin_internal_filter_match(text, text, boolean, boolean, boolean)') is not null
     or to_regprocedure('public.admin_catalog_programmes()') is not null
     or to_regprocedure('public.admin_catalog_courses(uuid)') is not null
     or to_regprocedure('public.admin_catalog_topics(uuid, text)') is not null
     or to_regprocedure('public.admin_topic_questions(uuid, uuid, text)') is not null then
    raise exception 'Catalog functions already exist. Use the rollback script first.';
  end if;

  if to_regprocedure('public.admin_internal_question_base(uuid, text, uuid, uuid, public.question_difficulty)') is null
     or to_regprocedure('public.admin_internal_require_role(public.admin_role[])') is null then
    raise exception 'Migration 20261015090000 must be applied first.';
  end if;

  perform 1
  from (values
    ('programmes', 'id'), ('programmes', 'code'), ('programmes', 'name'),
    ('programmes', 'is_active'),
    ('programme_semesters', 'id'), ('programme_semesters', 'programme_id'),
    ('programme_semesters', 'level_id'), ('programme_semesters', 'semester_id'),
    ('programme_courses', 'programme_semester_id'), ('programme_courses', 'course_id'),
    ('programme_courses', 'classification'),
    ('courses', 'id'), ('courses', 'code'), ('courses', 'title'), ('courses', 'is_active'),
    ('levels', 'id'), ('levels', 'code'), ('levels', 'name'), ('levels', 'sort_order'),
    ('semesters', 'id'), ('semesters', 'code'), ('semesters', 'name'), ('semesters', 'sort_order'),
    ('topics', 'id'), ('topics', 'course_id'), ('topics', 'title'), ('topics', 'sort_order'),
    ('questions', 'created_at')
  ) as r(t, c)
  where not exists (
    select 1 from pg_attribute a
    where a.attrelid = to_regclass('public.' || r.t)
      and a.attname = r.c
      and not a.attisdropped
  );
  if found then
    raise exception 'Expected columns are missing. Aborting.';
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- 1. The one definition of the status filters (internal). The topic cards and
--    the modal list both use it, so a card count and the questions you can step
--    through can never disagree.
--      all | needs_review (any submitted version) | mine | live | retired
-- -----------------------------------------------------------------------------
create function public.admin_internal_filter_match(
  p_filter     text,
  p_open_state text,
  p_is_mine    boolean,
  p_is_live    boolean,
  p_is_retired boolean
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_filter
           when 'needs_review' then coalesce(p_open_state = 'submitted', false)
           when 'mine'         then coalesce(p_is_mine, false)
           when 'live'         then coalesce(p_is_live, false)
           when 'retired'      then coalesce(p_is_retired, false)
           else true
         end
$$;

-- -----------------------------------------------------------------------------
-- 2. Programme cards. A course in several level/semester slots counts once.
-- -----------------------------------------------------------------------------
create function public.admin_catalog_programmes()
returns table (
  programme_id uuid,
  code         text,
  name         text,
  is_active    boolean,
  course_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_internal_require_role(
    array['super_admin', 'academic_admin', 'question_reviewer']::public.admin_role[]);

  return query
    select p.id,
           p.code,
           p.name,
           p.is_active,
           (select count(distinct pc.course_id)
            from public.programme_semesters ps
            join public.programme_courses pc on pc.programme_semester_id = ps.id
            where ps.programme_id = p.id)
    from public.programmes p
    order by p.name, p.id;
end
$$;

-- -----------------------------------------------------------------------------
-- 3. Course cards of one programme: one row per course and level/semester slot.
--    The page groups rows into cards and applies the level and semester filters.
-- -----------------------------------------------------------------------------
create function public.admin_catalog_courses(p_programme_id uuid)
returns table (
  course_id      uuid,
  code           text,
  title          text,
  is_active      boolean,
  level_id       uuid,
  level_code     text,
  level_name     text,
  level_sort     integer,
  semester_id    uuid,
  semester_code  text,
  semester_name  text,
  semester_sort  integer,
  classification text,
  topic_count    bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_internal_require_role(
    array['super_admin', 'academic_admin', 'question_reviewer']::public.admin_role[]);

  if p_programme_id is null
     or not exists (select 1 from public.programmes p where p.id = p_programme_id) then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;

  return query
    select c.id,
           c.code,
           c.title,
           c.is_active,
           l.id,
           l.code,
           l.name,
           l.sort_order,
           s.id,
           s.code,
           s.name,
           s.sort_order,
           pc.classification,
           (select count(*) from public.topics t where t.course_id = c.id)
    from public.programme_semesters ps
    join public.programme_courses pc on pc.programme_semester_id = ps.id
    join public.courses c on c.id = pc.course_id
    join public.levels l on l.id = ps.level_id
    join public.semesters s on s.id = ps.semester_id
    where ps.programme_id = p_programme_id
    order by l.sort_order, s.sort_order, c.code, c.id;
end
$$;

-- -----------------------------------------------------------------------------
-- 4. Topic cards of one course, counting only the questions that match the
--    filter. Under a filter, topics with no match are left out. A "No topic"
--    row (topic_id null) appears only if matching questions without a topic
--    exist. Live, retired and draft add up to the total; waiting can overlap
--    with live (a new version is reviewed while the old one stays live).
-- -----------------------------------------------------------------------------
create function public.admin_catalog_topics(p_course_id uuid, p_filter text default 'all')
returns table (
  topic_id      uuid,
  title         text,
  sort_order    integer,
  total_count   bigint,
  live_count    bigint,
  retired_count bigint,
  draft_count   bigint,
  waiting_count bigint,
  mine_count    bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  v_actor := public.admin_internal_require_role(
    array['super_admin', 'academic_admin', 'question_reviewer']::public.admin_role[]);

  if p_filter is null
     or p_filter not in ('all', 'needs_review', 'mine', 'live', 'retired') then
    raise exception 'invalid_filter' using errcode = '22023';
  end if;
  if p_course_id is null
     or not exists (select 1 from public.courses c where c.id = p_course_id) then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;

  return query
    with q as (
      select b.question_id     as q_id,
             b.topic_id        as q_topic,
             b.question_status as q_status,
             b.open_state      as q_open,
             b.is_mine         as q_mine
      from public.admin_internal_question_base(
             v_actor, null::text, p_course_id, null::uuid, null::public.question_difficulty) b
      where public.admin_internal_filter_match(
              p_filter, b.open_state, b.is_mine, b.is_live, b.is_retired)
    )
    select t.id,
           t.title,
           t.sort_order,
           count(q.q_id),
           count(*) filter (where q.q_status = 'published'),
           count(*) filter (where q.q_status = 'retired'),
           count(*) filter (where q.q_status = 'draft'),
           count(*) filter (where q.q_open = 'submitted'),
           count(*) filter (where q.q_mine)
    from public.topics t
    left join q on q.q_topic = t.id
    where t.course_id = p_course_id
    group by t.id, t.title, t.sort_order
    having p_filter = 'all' or count(q.q_id) > 0
    union all
    select null::uuid,
           'No topic'::text,
           2147483647,
           count(*),
           count(*) filter (where q.q_status = 'published'),
           count(*) filter (where q.q_status = 'retired'),
           count(*) filter (where q.q_status = 'draft'),
           count(*) filter (where q.q_open = 'submitted'),
           count(*) filter (where q.q_mine)
    from q
    where q.q_topic is null
    having count(*) > 0
    order by 3, 2;
end
$$;

-- -----------------------------------------------------------------------------
-- 5. The questions behind one topic card, in the order the modal steps through
--    them. p_topic_id null means "the questions with no topic". The version to
--    show is the one needing action under Waiting for Review and My Work, and
--    otherwise the live version (the latest, if never published). Order: oldest
--    submission first under Waiting for Review, otherwise creation order.
-- -----------------------------------------------------------------------------
create function public.admin_topic_questions(
  p_course_id uuid,
  p_topic_id  uuid,
  p_filter    text default 'all'
)
returns table (
  question_id  uuid,
  version_id   uuid,
  version      integer,
  review_state text,
  sort_at      timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  v_actor := public.admin_internal_require_role(
    array['super_admin', 'academic_admin', 'question_reviewer']::public.admin_role[]);

  if p_filter is null
     or p_filter not in ('all', 'needs_review', 'mine', 'live', 'retired') then
    raise exception 'invalid_filter' using errcode = '22023';
  end if;
  if p_course_id is null
     or not exists (select 1 from public.courses c where c.id = p_course_id) then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if p_topic_id is not null
     and not exists (select 1 from public.topics t
                     where t.id = p_topic_id and t.course_id = p_course_id) then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;

  return query
    select x.q_id,
           x.v_id,
           x.v_num,
           coalesce(a.state::text, 'imported'),
           x.sort_key
    from (
      select b.question_id as q_id,
             (case when p_filter in ('needs_review', 'mine')
                   then b.open_version_id else b.current_version_id end) as v_id,
             (case when p_filter in ('needs_review', 'mine')
                   then b.open_version else b.current_version end) as v_num,
             (case when p_filter = 'needs_review'
                   then b.open_submitted_at else qq.created_at end) as sort_key
      from public.admin_internal_question_base(
             v_actor, null::text, p_course_id, null::uuid, null::public.question_difficulty) b
      join public.questions qq on qq.id = b.question_id
      where b.topic_id is not distinct from p_topic_id
        and public.admin_internal_filter_match(
              p_filter, b.open_state, b.is_mine, b.is_live, b.is_retired)
    ) x
    left join public.admin_question_versions a on a.question_version_id = x.v_id
    order by x.sort_key, x.q_id;
end
$$;

-- -----------------------------------------------------------------------------
-- 6. Privileges. Every role is revoked by name (this project's default
--    privileges grant new functions to API roles), then the intended grants.
-- -----------------------------------------------------------------------------
revoke all on function public.admin_internal_filter_match(text, text, boolean, boolean, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_catalog_programmes()
  from public, anon, authenticated, service_role;
revoke all on function public.admin_catalog_courses(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_catalog_topics(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_topic_questions(uuid, uuid, text)
  from public, anon, authenticated, service_role;

grant execute on function public.admin_catalog_programmes()               to authenticated;
grant execute on function public.admin_catalog_courses(uuid)              to authenticated;
grant execute on function public.admin_catalog_topics(uuid, text)         to authenticated;
grant execute on function public.admin_topic_questions(uuid, uuid, text)  to authenticated;

-- -----------------------------------------------------------------------------
-- 7. Self-check: nothing commits unless the privilege model is what this file
--    intends.
-- -----------------------------------------------------------------------------
do $$
declare
  v_new     text[] := array[
    'admin_internal_filter_match', 'admin_catalog_programmes', 'admin_catalog_courses',
    'admin_catalog_topics', 'admin_topic_questions'];
  v_app     text[] := array[
    'admin_catalog_programmes', 'admin_catalog_courses',
    'admin_catalog_topics', 'admin_topic_questions'];
  v_invoker text[] := array['admin_internal_filter_match'];
  r         record;
  v_n       integer := 0;
begin
  for r in
    select p.oid, p.proname, p.proconfig, p.prosecdef
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = any (v_new)
  loop
    v_n := v_n + 1;

    if has_function_privilege('anon', r.oid, 'execute')
       or has_function_privilege('service_role', r.oid, 'execute') then
      raise exception 'Self-check failed: anon/service_role can execute %', r.proname;
    end if;

    if has_function_privilege('authenticated', r.oid, 'execute') <> (r.proname = any (v_app)) then
      raise exception 'Self-check failed: unexpected authenticated EXECUTE state on %', r.proname;
    end if;

    if r.prosecdef = (r.proname = any (v_invoker)) then
      raise exception 'Self-check failed: unexpected SECURITY DEFINER setting on %', r.proname;
    end if;

    if r.proconfig is null
       or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
      raise exception 'Self-check failed: % has no fixed search_path', r.proname;
    end if;
  end loop;

  if v_n <> cardinality(v_new) then
    raise exception 'Self-check failed: expected % new functions, found %', cardinality(v_new), v_n;
  end if;

  if (select count(*) from pg_proc
      where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\') <> 46 then
    raise exception 'Self-check failed: expected 46 admin functions in total';
  end if;
end
$$;

notify pgrst, 'reload schema';

commit;