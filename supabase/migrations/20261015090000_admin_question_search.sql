-- =============================================================================
-- UniExam Admin - Milestone 1B, Batch 4: question search (one row per question)
-- File: supabase/migrations/20261015090000_admin_question_search.sql
--
-- Creates ONLY 4 new functions. READ-ONLY: none of them writes anything. They
-- read the student question tables and the admin review table. No table, type,
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

  if to_regprocedure('public.admin_question_search(text, text, uuid, uuid, public.question_difficulty, timestamptz, uuid, text, integer)') is not null
     or to_regprocedure('public.admin_question_counts(text, uuid, uuid, public.question_difficulty)') is not null
     or to_regprocedure('public.admin_question_history(uuid)') is not null
     or to_regprocedure('public.admin_internal_question_base(uuid, text, uuid, uuid, public.question_difficulty)') is not null then
    raise exception 'Question search functions already exist. Use the rollback script first.';
  end if;

  if to_regclass('public.admin_question_versions') is null
     or to_regprocedure('public.admin_internal_require_role(public.admin_role[])') is null then
    raise exception 'Migration 20261014090000 must be applied first.';
  end if;

  perform 1
  from (values
    ('questions', 'id'), ('questions', 'course_id'), ('questions', 'topic_id'),
    ('questions', 'status'), ('questions', 'published_version'),
    ('questions', 'external_key'), ('questions', 'updated_at'),
    ('question_versions', 'id'), ('question_versions', 'question_id'),
    ('question_versions', 'version'), ('question_versions', 'body'),
    ('question_versions', 'difficulty'), ('question_versions', 'published_at'),
    ('question_versions', 'created_at'),
    ('courses', 'id'), ('courses', 'code'),
    ('topics', 'id'), ('topics', 'title'),
    ('admin_question_versions', 'question_version_id'),
    ('admin_question_versions', 'question_id'),
    ('admin_question_versions', 'state'), ('admin_question_versions', 'author_id'),
    ('admin_question_versions', 'submitted_at'), ('admin_question_versions', 'updated_at')
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
-- 1. The one place the per-question logic lives (internal)
--    Exactly one row per question:
--      * the current version is the live version, or the latest if never published;
--      * at most one open version exists per question (unique index from
--        migration 20261014090000), so joining it cannot multiply rows.
-- -----------------------------------------------------------------------------
create function public.admin_internal_question_base(
  p_actor      uuid,
  p_query      text,
  p_course_id  uuid,
  p_topic_id   uuid,
  p_difficulty public.question_difficulty
)
returns table (
  question_id         uuid,
  course_id           uuid,
  course_code         text,
  topic_id            uuid,
  topic_title         text,
  question_status     public.question_status,
  stem                text,
  difficulty          public.question_difficulty,
  current_version_id  uuid,
  current_version     integer,
  current_is_imported boolean,
  live_version_id     uuid,
  live_version        integer,
  open_version_id     uuid,
  open_version        integer,
  open_state          text,
  open_author_email   text,
  open_submitted_at   timestamptz,
  is_live             boolean,
  is_retired          boolean,
  needs_review        boolean,
  is_mine             boolean,
  activity_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_q   text := pg_catalog.btrim(coalesce(p_query, ''));
  v_pat text;
begin
  if v_q <> '' then
    if pg_catalog.char_length(v_q) not between 2 and 100 then
      raise exception 'invalid_filter' using errcode = '22023';
    end if;
    -- Escape LIKE wildcards so the text is searched literally.
    v_pat := '%'
      || pg_catalog.replace(pg_catalog.replace(pg_catalog.replace(v_q, '\', '\\'), '%', '\%'), '_', '\_')
      || '%';
  end if;

  return query
    select q.id,
           q.course_id,
           c.code,
           q.topic_id,
           t.title,
           q.status,
           coalesce(cur.body ->> 'stem', ''),
           cur.difficulty,
           cur.id,
           cur.version,
           (cura.question_version_id is null),
           lv.id,
           lv.version,
           ov.id,
           ov.version,
           oa.state::text,
           ou.email::text,
           oa.submitted_at,
           (q.status = 'published'),
           (q.status = 'retired'),
           coalesce(oa.state = 'submitted' and oa.author_id <> p_actor, false),
           coalesce(oa.author_id = p_actor, false),
           greatest(q.updated_at, act.last_at)
    from public.questions q
    join public.courses c on c.id = q.course_id
    left join public.topics t on t.id = q.topic_id
    join lateral (
      select v.id, v.version
      from public.question_versions v
      where v.question_id = q.id
      order by v.version desc
      limit 1
    ) lat on true
    left join public.question_versions lv
      on lv.question_id = q.id and lv.version = q.published_version
    join public.question_versions cur on cur.id = coalesce(lv.id, lat.id)
    left join public.admin_question_versions cura on cura.question_version_id = cur.id
    left join public.admin_question_versions oa
      on oa.question_id = q.id and oa.state in ('draft', 'submitted', 'rejected')
    left join public.question_versions ov on ov.id = oa.question_version_id
    left join auth.users ou on ou.id = oa.author_id
    join lateral (
      select max(coalesce(a2.updated_at, v2.created_at)) as last_at
      from public.question_versions v2
      left join public.admin_question_versions a2 on a2.question_version_id = v2.id
      where v2.question_id = q.id
    ) act on true
    where (p_course_id is null or q.course_id = p_course_id)
      and (p_topic_id is null or q.topic_id = p_topic_id)
      and (p_difficulty is null or cur.difficulty = p_difficulty)
      and (v_pat is null
           or (cur.body ->> 'stem') ilike v_pat escape '\'
           or (ov.body ->> 'stem') ilike v_pat escape '\'
           or q.external_key ilike v_pat escape '\');
end
$$;

-- -----------------------------------------------------------------------------
-- 2. The list: filters, a view, and keyset paging in either direction
--    p_view: all | needs_review | mine | live | retired
--    p_dir:  next | prev   (the cursor is the sort_at and question_id of the
--            row on the page edge you are leaving)
--    The caller asks for p_limit and receives up to p_limit + 1 rows; the extra
--    row only signals that more exist in the direction of travel.
-- -----------------------------------------------------------------------------
create function public.admin_question_search(
  p_view       text default 'all',
  p_query      text default null,
  p_course_id  uuid default null,
  p_topic_id   uuid default null,
  p_difficulty public.question_difficulty default null,
  p_cursor_at  timestamptz default null,
  p_cursor_id  uuid default null,
  p_dir        text default 'next',
  p_limit      integer default 25
)
returns table (
  question_id         uuid,
  course_id           uuid,
  course_code         text,
  topic_id            uuid,
  topic_title         text,
  question_status     public.question_status,
  stem                text,
  difficulty          public.question_difficulty,
  current_version_id  uuid,
  current_version     integer,
  current_is_imported boolean,
  live_version_id     uuid,
  live_version        integer,
  open_version_id     uuid,
  open_version        integer,
  open_state          text,
  open_author_email   text,
  open_submitted_at   timestamptz,
  is_live             boolean,
  is_retired          boolean,
  needs_review        boolean,
  is_mine             boolean,
  sort_at             timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor      uuid;
  v_limit      integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_show_desc  boolean;
  v_fetch_desc boolean;
begin
  v_actor := public.admin_internal_require_role(
    array['super_admin', 'academic_admin', 'question_reviewer']::public.admin_role[]);

  if p_view is null or p_view not in ('all', 'needs_review', 'mine', 'live', 'retired')
     or p_dir is null or p_dir not in ('next', 'prev')
     or (p_cursor_at is null) <> (p_cursor_id is null) then
    raise exception 'invalid_filter' using errcode = '22023';
  end if;

  -- Rows are shown newest activity first, except the review queue, which is
  -- oldest submission first. Going back fetches in the opposite order and the
  -- outer query puts the rows back in display order.
  v_show_desc  := (p_view <> 'needs_review');
  v_fetch_desc := v_show_desc <> (p_dir = 'prev');

  return query
    select x.question_id, x.course_id, x.course_code, x.topic_id, x.topic_title,
           x.question_status, x.stem, x.difficulty,
           x.current_version_id, x.current_version, x.current_is_imported,
           x.live_version_id, x.live_version,
           x.open_version_id, x.open_version, x.open_state,
           x.open_author_email, x.open_submitted_at,
           x.is_live, x.is_retired, x.needs_review, x.is_mine, x.sort_at
    from (
      select s.*
      from (
        select b.*,
               case when p_view = 'needs_review' then b.open_submitted_at
                    else b.activity_at end as sort_at
        from public.admin_internal_question_base(
               v_actor, p_query, p_course_id, p_topic_id, p_difficulty) b
      ) s
      where (case p_view
               when 'needs_review' then s.needs_review
               when 'mine'         then s.is_mine
               when 'live'         then s.is_live
               when 'retired'      then s.is_retired
               else true end)
        and (p_cursor_at is null
             or case when v_fetch_desc
                     then (s.sort_at, s.question_id) < (p_cursor_at, p_cursor_id)
                     else (s.sort_at, s.question_id) > (p_cursor_at, p_cursor_id) end)
      order by case when v_fetch_desc then s.sort_at end desc,
               case when not v_fetch_desc then s.sort_at end asc,
               case when v_fetch_desc then s.question_id end desc,
               case when not v_fetch_desc then s.question_id end asc
      limit v_limit + 1
    ) x
    order by case when v_show_desc then x.sort_at end desc,
             case when not v_show_desc then x.sort_at end asc,
             case when v_show_desc then x.question_id end desc,
             case when not v_show_desc then x.question_id end asc;
end
$$;

-- -----------------------------------------------------------------------------
-- 3. Tab counts, under the same search, course, topic and difficulty filters
-- -----------------------------------------------------------------------------
create function public.admin_question_counts(
  p_query      text default null,
  p_course_id  uuid default null,
  p_topic_id   uuid default null,
  p_difficulty public.question_difficulty default null
)
returns table (
  all_count          bigint,
  needs_review_count bigint,
  mine_count         bigint,
  live_count         bigint,
  retired_count      bigint
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

  return query
    select count(*),
           count(*) filter (where b.needs_review),
           count(*) filter (where b.is_mine),
           count(*) filter (where b.is_live),
           count(*) filter (where b.is_retired)
    from public.admin_internal_question_base(
           v_actor, p_query, p_course_id, p_topic_id, p_difficulty) b;
end
$$;

-- -----------------------------------------------------------------------------
-- 4. Version history of one question (for the detail page)
-- -----------------------------------------------------------------------------
create function public.admin_question_history(p_question_id uuid)
returns table (
  version_id    uuid,
  version       integer,
  review_state  text,
  is_live       boolean,
  was_published boolean,
  author_email  text,
  updated_at    timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_internal_require_role(
    array['super_admin', 'academic_admin', 'question_reviewer']::public.admin_role[]);

  if p_question_id is null
     or not exists (select 1 from public.questions q where q.id = p_question_id) then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;

  return query
    select qv.id,
           qv.version,
           coalesce(a.state::text, 'imported'),
           (q.status = 'published' and q.published_version = qv.version),
           (qv.published_at is not null),
           au.email::text,
           coalesce(a.updated_at, qv.created_at)
    from public.question_versions qv
    join public.questions q on q.id = qv.question_id
    left join public.admin_question_versions a on a.question_version_id = qv.id
    left join auth.users au on au.id = a.author_id
    where qv.question_id = p_question_id
    order by qv.version desc;
end
$$;

-- -----------------------------------------------------------------------------
-- 5. Privileges. Every role is revoked by name (this project's default
--    privileges grant new functions to API roles), then the intended grants.
-- -----------------------------------------------------------------------------
revoke all on function public.admin_internal_question_base(uuid, text, uuid, uuid, public.question_difficulty)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_question_search(text, text, uuid, uuid, public.question_difficulty, timestamptz, uuid, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_question_counts(text, uuid, uuid, public.question_difficulty)
  from public, anon, authenticated, service_role;
revoke all on function public.admin_question_history(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.admin_question_search(text, text, uuid, uuid, public.question_difficulty, timestamptz, uuid, text, integer) to authenticated;
grant execute on function public.admin_question_counts(text, uuid, uuid, public.question_difficulty) to authenticated;
grant execute on function public.admin_question_history(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Self-check: nothing commits unless the privilege model is what this file
--    intends.
-- -----------------------------------------------------------------------------
do $$
declare
  v_new text[] := array[
    'admin_internal_question_base', 'admin_question_search',
    'admin_question_counts', 'admin_question_history'];
  v_app text[] := array[
    'admin_question_search', 'admin_question_counts', 'admin_question_history'];
  r     record;
  v_n   integer := 0;
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

    if not r.prosecdef then
      raise exception 'Self-check failed: % is not SECURITY DEFINER', r.proname;
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
      where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\') <> 41 then
    raise exception 'Self-check failed: expected 41 admin functions in total';
  end if;
end
$$;

notify pgrst, 'reload schema';

commit;