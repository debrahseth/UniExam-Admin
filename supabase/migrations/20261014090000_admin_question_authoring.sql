-- =============================================================================
-- UniExam Admin - Milestone 1B, Batch 3: question authoring and review
-- File: supabase/migrations/20261014090000_admin_question_authoring.sql
--
-- Creates ONLY new objects: 1 enum, 2 tables, 16 functions, triggers, indexes.
-- Its functions READ and WRITE the student question tables, but only through the
-- guards the student schema already enforces. It changes no student table
-- definition, policy, trigger, function, grant or default privilege. The two new
-- tables hold foreign keys to student tables (cascade from the student side).
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

  if to_regclass('public.admin_question_versions') is not null
     or to_regclass('public.admin_activity_log') is not null
     or to_regtype('public.admin_review_state') is not null then
    raise exception 'Question authoring objects already exist. Use the rollback script first.';
  end if;

  if to_regprocedure('public.admin_internal_require_actor(public.admin_role)') is null
     or to_regprocedure('public.admin_internal_check_reason(text)') is null
     or to_regprocedure('public.admin_block_trg()') is null
     or to_regprocedure('public.admin_find_user_by_email(text)') is null then
    raise exception 'Admin migrations 20261012180000 and 20261013230000 must be applied first.';
  end if;

  if to_regprocedure('public.publish_question_version(uuid)') is null
     or to_regtype('public.question_difficulty') is null
     or to_regtype('public.question_status') is null then
    raise exception 'Expected student question objects are missing. Aborting.';
  end if;

  perform 1
  from (values
    ('questions', 'id'), ('questions', 'course_id'), ('questions', 'topic_id'),
    ('questions', 'status'), ('questions', 'published_version'),
    ('question_versions', 'id'), ('question_versions', 'question_id'),
    ('question_versions', 'version'), ('question_versions', 'type'),
    ('question_versions', 'body'), ('question_versions', 'difficulty'),
    ('question_versions', 'published_at'),
    ('question_version_solutions', 'question_version_id'),
    ('question_version_solutions', 'correct_option_ids'),
    ('question_version_solutions', 'explanation'),
    ('courses', 'id'), ('courses', 'code'), ('courses', 'is_active'),
    ('topics', 'id'), ('topics', 'course_id'), ('topics', 'title')
  ) as r(t, c)
  where not exists (
    select 1 from pg_attribute a
    where a.attrelid = to_regclass('public.' || r.t)
      and a.attname = r.c
      and not a.attisdropped
  );
  if found then
    raise exception 'Expected student columns are missing. Aborting.';
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- 1. Type
-- -----------------------------------------------------------------------------
create type public.admin_review_state as enum ('draft', 'submitted', 'approved', 'rejected');

-- -----------------------------------------------------------------------------
-- 2. Tables
-- -----------------------------------------------------------------------------
-- One row per question version created through the admin app. Versions loaded by
-- scripts have no row here and are shown as "imported".
create table public.admin_question_versions (
  question_version_id uuid primary key
    references public.question_versions (id) on delete cascade,
  question_id  uuid not null
    references public.questions (id) on delete cascade,
  state        public.admin_review_state not null default 'draft',
  author_id    uuid not null,              -- not a foreign key: must outlive the user
  submitted_at timestamptz,
  reviewer_id  uuid,
  reviewed_at  timestamptz,
  review_note  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint admin_qv_reviewer_not_author
    check (reviewer_id is null or reviewer_id <> author_id),
  constraint admin_qv_submitted_consistent
    check ((state in ('submitted', 'approved', 'rejected')) = (submitted_at is not null)),
  constraint admin_qv_reviewed_consistent
    check ((state in ('approved', 'rejected')) = (reviewer_id is not null and reviewed_at is not null)),
  constraint admin_qv_note_length
    check (review_note is null or char_length(review_note) between 10 and 500),
  constraint admin_qv_rejected_has_note
    check (state <> 'rejected' or review_note is not null)
);

-- At most one open version per question.
create unique index admin_qv_one_open_per_question
  on public.admin_question_versions (question_id)
  where state in ('draft', 'submitted', 'rejected');

create index admin_qv_state_idx
  on public.admin_question_versions (state, updated_at desc);

-- Append-only record of content decisions. Separate from admin_audit_log so the
-- verified hash chain of access changes is untouched.
create table public.admin_activity_log (
  id              bigint generated always as identity primary key,
  occurred_at     timestamptz not null default now(),
  actor_user_id   uuid not null,
  actor_role      public.admin_role not null,
  action          text not null check (action in (
                    'question.approved', 'question.rejected', 'question.retired',
                    'question.restored', 'question.discarded')),
  target_kind     text not null check (target_kind in ('question', 'question_version')),
  target_id       uuid not null,           -- not a foreign key: the log must outlive content
  detail          jsonb,
  reason          text,
  db_session_user text not null default session_user,
  txid            bigint not null default pg_catalog.txid_current(),
  constraint admin_activity_reason_rule
    check ((action in ('question.rejected', 'question.retired', 'question.restored'))
           = (reason is not null)),
  constraint admin_activity_reason_length
    check (reason is null or char_length(reason) between 10 and 500)
);

create index admin_activity_log_target_idx on public.admin_activity_log (target_id, id desc);

comment on table public.admin_question_versions is
  'Authorship and review state of question versions created in UniExam Admin. No direct client access. Changed only via admin_question_* functions.';
comment on table public.admin_activity_log is
  'Append-only log of question approvals, rejections, retirements, restores and discards. No direct client access.';

create trigger admin_activity_log_no_update_delete
  before update or delete on public.admin_activity_log
  for each row execute function public.admin_block_trg('activity_log_is_append_only');

create trigger admin_activity_log_no_truncate
  before truncate on public.admin_activity_log
  for each statement execute function public.admin_block_trg('activity_log_is_append_only');

create trigger admin_question_versions_no_truncate
  before truncate on public.admin_question_versions
  for each statement execute function public.admin_block_trg('admin_question_versions_truncate_blocked');

-- Defence in depth: the review state machine and the immutable fields are
-- enforced by the table itself, not only by the functions.
create function public.admin_qv_guard_trg()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.state not in ('draft', 'rejected') then
      raise exception 'admin_question_record_not_deletable' using errcode = '23503';
    end if;
    return old;
  end if;

  if new.question_version_id <> old.question_version_id
     or new.question_id <> old.question_id
     or new.author_id <> old.author_id
     or new.created_at <> old.created_at then
    raise exception 'admin_question_record_immutable_field' using errcode = '42501';
  end if;

  if old.state = 'approved' then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  if new.state <> old.state and not (
       (old.state = 'draft'     and new.state = 'submitted')
    or (old.state = 'submitted' and new.state in ('approved', 'rejected'))
    or (old.state = 'rejected'  and new.state = 'draft')) then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  return new;
end
$$;

create trigger admin_question_versions_guard
  before update or delete on public.admin_question_versions
  for each row execute function public.admin_qv_guard_trg();

-- -----------------------------------------------------------------------------
-- 3. Internal helpers (no EXECUTE for any API role; see section 6)
-- -----------------------------------------------------------------------------

-- Shared form of the global admin lock. Access changes hold it exclusively, so
-- content operations wait for them, and run in parallel with each other.
create function public.admin_internal_lock_shared()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('uniexam.admin.mutations', 0));
end
$$;

-- Same checks as admin_internal_require_actor (active, no student profile, MFA
-- session), then requires one of the given roles.
create function public.admin_internal_require_role(p_roles public.admin_role[])
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid;
  v_role public.admin_role;
begin
  v_uid := public.admin_internal_require_actor(null);

  select a.role into v_role from public.admin_users a where a.user_id = v_uid;

  if v_role is null or p_roles is null or not (v_role = any (p_roles)) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  return v_uid;
end
$$;

-- Builds the stored body, answer and explanation from plain inputs. Option ids
-- are generated here (a to f, matching the exam's position letters), so the body
-- can only ever contain "stem" and "options" with "id" and "text".
create function public.admin_internal_build_question(
  p_stem        text,
  p_options     text[],
  p_correct     text,
  p_explanation text,
  p_difficulty  public.question_difficulty
)
returns table (
  o_body        jsonb,
  o_correct     text,
  o_explanation jsonb,
  o_difficulty  public.question_difficulty
)
language plpgsql
set search_path = ''
as $$
declare
  v_letters constant text[] := array['a', 'b', 'c', 'd', 'e', 'f'];
  v_ws      constant text   := E' \t\r\n';
  v_stem    text    := pg_catalog.btrim(coalesce(p_stem, ''), v_ws);
  v_expl    text    := pg_catalog.btrim(coalesce(p_explanation, ''), v_ws);
  v_n       integer := coalesce(pg_catalog.cardinality(p_options), 0);
  v_opts    jsonb   := '[]'::jsonb;
  v_seen    text[]  := array[]::text[];
  v_text    text;
  i         integer;
begin
  if pg_catalog.char_length(v_stem) not between 1 and 2000
     or pg_catalog.translate(v_stem, E'\r\n\t', '') ~ '[[:cntrl:]]' then
    raise exception 'invalid_stem' using errcode = '22023';
  end if;

  if v_n not between 2 and 6 then
    raise exception 'invalid_options' using errcode = '22023';
  end if;

  for i in 1 .. v_n loop
    v_text := pg_catalog.btrim(coalesce(p_options[i], ''), v_ws);
    if pg_catalog.char_length(v_text) not between 1 and 500
       or v_text ~ '[[:cntrl:]]'
       or pg_catalog.lower(v_text) = any (v_seen) then
      raise exception 'invalid_options' using errcode = '22023';
    end if;
    v_seen := v_seen || pg_catalog.lower(v_text);
    v_opts := v_opts || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('id', v_letters[i], 'text', v_text));
  end loop;

  if p_correct is null
     or p_correct !~ '^[a-f]$'
     or pg_catalog.array_position(v_letters, p_correct) > v_n then
    raise exception 'invalid_correct' using errcode = '22023';
  end if;

  if p_difficulty is null then
    raise exception 'invalid_difficulty' using errcode = '22023';
  end if;

  if v_expl <> '' and (pg_catalog.char_length(v_expl) > 4000
     or pg_catalog.translate(v_expl, E'\r\n\t', '') ~ '[[:cntrl:]]') then
    raise exception 'invalid_explanation' using errcode = '22023';
  end if;

  return query select
    pg_catalog.jsonb_build_object('stem', v_stem, 'options', v_opts),
    p_correct,
    case when v_expl = '' then null::jsonb
         else pg_catalog.jsonb_build_object('text', v_expl) end,
    p_difficulty;
end
$$;

create function public.admin_internal_log_activity(
  p_actor  uuid,
  p_role   public.admin_role,
  p_action text,
  p_kind   text,
  p_target uuid,
  p_detail jsonb,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.admin_activity_log
    (actor_user_id, actor_role, action, target_kind, target_id, detail, reason)
  values
    (p_actor, p_role, p_action, p_kind, p_target, p_detail, p_reason);
end
$$;

-- -----------------------------------------------------------------------------
-- 4. Authoring (Super Admin and Academic admin)
-- -----------------------------------------------------------------------------

-- 4.1 New question, first version, as a draft. Returns the version id.
create function public.admin_question_create_draft(
  p_course_id   uuid,
  p_topic_id    uuid,
  p_stem        text,
  p_options     text[],
  p_correct     text,
  p_explanation text,
  p_difficulty  public.question_difficulty
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor    uuid;
  v_c        record;
  v_question uuid;
  v_version  uuid;
begin
  perform public.admin_internal_lock_shared();
  v_actor := public.admin_internal_require_role(array['super_admin', 'academic_admin']::public.admin_role[]);

  select * into v_c from public.admin_internal_build_question(
    p_stem, p_options, p_correct, p_explanation, p_difficulty);

  if p_course_id is null
     or not exists (select 1 from public.courses c where c.id = p_course_id and c.is_active) then
    raise exception 'invalid_course' using errcode = '22023';
  end if;
  if p_topic_id is null
     or not exists (select 1 from public.topics t where t.id = p_topic_id and t.course_id = p_course_id) then
    raise exception 'invalid_topic' using errcode = '22023';
  end if;

  insert into public.questions (course_id, topic_id, status)
  values (p_course_id, p_topic_id, 'draft')
  returning id into v_question;

  insert into public.question_versions (question_id, version, type, body, difficulty)
  values (v_question, 1, 'mcq', v_c.o_body, v_c.o_difficulty)
  returning id into v_version;

  insert into public.question_version_solutions (question_version_id, correct_option_ids, explanation)
  values (v_version, array[v_c.o_correct], v_c.o_explanation);

  insert into public.admin_question_versions (question_version_id, question_id, state, author_id)
  values (v_version, v_question, 'draft', v_actor);

  return v_version;
end
$$;

-- 4.2 New draft version of an existing published question. Returns the version id.
create function public.admin_question_create_version(
  p_question_id uuid,
  p_stem        text,
  p_options     text[],
  p_correct     text,
  p_explanation text,
  p_difficulty  public.question_difficulty
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor   uuid;
  v_c       record;
  v_q       public.questions%rowtype;
  v_next    integer;
  v_version uuid;
begin
  perform public.admin_internal_lock_shared();
  v_actor := public.admin_internal_require_role(array['super_admin', 'academic_admin']::public.admin_role[]);

  select * into v_c from public.admin_internal_build_question(
    p_stem, p_options, p_correct, p_explanation, p_difficulty);

  select * into v_q from public.questions q where q.id = p_question_id for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_q.status = 'retired' then
    raise exception 'question_retired' using errcode = '22023';
  end if;
  if v_q.published_version is null then
    raise exception 'invalid_state' using errcode = '22023';
  end if;
  if exists (select 1 from public.admin_question_versions a
             where a.question_id = p_question_id
               and a.state in ('draft', 'submitted', 'rejected')) then
    raise exception 'open_version_exists' using errcode = '22023';
  end if;

  select coalesce(max(qv.version), 0) + 1 into v_next
  from public.question_versions qv where qv.question_id = p_question_id;

  insert into public.question_versions (question_id, version, type, body, difficulty)
  values (p_question_id, v_next, 'mcq', v_c.o_body, v_c.o_difficulty)
  returning id into v_version;

  insert into public.question_version_solutions (question_version_id, correct_option_ids, explanation)
  values (v_version, array[v_c.o_correct], v_c.o_explanation);

  insert into public.admin_question_versions (question_version_id, question_id, state, author_id)
  values (v_version, p_question_id, 'draft', v_actor);

  return v_version;
end
$$;

-- 4.3 Edit your own draft or rejected version. A rejected version returns to draft.
create function public.admin_question_update_draft(
  p_version_id  uuid,
  p_topic_id    uuid,
  p_stem        text,
  p_options     text[],
  p_correct     text,
  p_explanation text,
  p_difficulty  public.question_difficulty
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor     uuid;
  v_c         record;
  v_t         public.admin_question_versions%rowtype;
  v_q         public.questions%rowtype;
  v_published timestamptz;
begin
  perform public.admin_internal_lock_shared();
  v_actor := public.admin_internal_require_role(array['super_admin', 'academic_admin']::public.admin_role[]);

  select * into v_c from public.admin_internal_build_question(
    p_stem, p_options, p_correct, p_explanation, p_difficulty);

  select * into v_t from public.admin_question_versions a
  where a.question_version_id = p_version_id for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_t.author_id <> v_actor then
    raise exception 'not_author' using errcode = '42501';
  end if;
  if v_t.state not in ('draft', 'rejected') then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  select qv.published_at into v_published
  from public.question_versions qv where qv.id = p_version_id;
  if v_published is not null then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  select * into v_q from public.questions q where q.id = v_t.question_id for update;

  if v_q.published_version is null then
    if p_topic_id is null
       or not exists (select 1 from public.topics t where t.id = p_topic_id and t.course_id = v_q.course_id) then
      raise exception 'invalid_topic' using errcode = '22023';
    end if;
    update public.questions set topic_id = p_topic_id where id = v_q.id;
  elsif p_topic_id is distinct from v_q.topic_id then
    raise exception 'topic_locked' using errcode = '22023';
  end if;

  -- The solution is replaced around the body update so the student schema's own
  -- body-versus-answer guards pass in either direction (for example fewer options).
  delete from public.question_version_solutions where question_version_id = p_version_id;

  update public.question_versions
     set body = v_c.o_body, difficulty = v_c.o_difficulty
   where id = p_version_id;

  insert into public.question_version_solutions (question_version_id, correct_option_ids, explanation)
  values (p_version_id, array[v_c.o_correct], v_c.o_explanation);

  update public.admin_question_versions
     set state = 'draft', submitted_at = null,
         reviewer_id = null, reviewed_at = null, review_note = null,
         updated_at = pg_catalog.now()
   where question_version_id = p_version_id;
end
$$;

-- 4.4 Submit your own draft for review.
create function public.admin_question_submit(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_t     public.admin_question_versions%rowtype;
begin
  perform public.admin_internal_lock_shared();
  v_actor := public.admin_internal_require_role(array['super_admin', 'academic_admin']::public.admin_role[]);

  select * into v_t from public.admin_question_versions a
  where a.question_version_id = p_version_id for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_t.author_id <> v_actor then
    raise exception 'not_author' using errcode = '42501';
  end if;
  if v_t.state <> 'draft' then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  update public.admin_question_versions
     set state = 'submitted', submitted_at = pg_catalog.now(), updated_at = pg_catalog.now()
   where question_version_id = p_version_id;
end
$$;

-- 4.5 Discard your own unpublished draft or rejected version.
create function public.admin_question_discard_draft(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor     uuid;
  v_role      public.admin_role;
  v_t         public.admin_question_versions%rowtype;
  v_q         public.questions%rowtype;
  v_published timestamptz;
  v_number    integer;
begin
  perform public.admin_internal_lock_shared();
  v_actor := public.admin_internal_require_role(array['super_admin', 'academic_admin']::public.admin_role[]);
  select a.role into v_role from public.admin_users a where a.user_id = v_actor;

  select * into v_t from public.admin_question_versions a
  where a.question_version_id = p_version_id for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_t.author_id <> v_actor then
    raise exception 'not_author' using errcode = '42501';
  end if;
  if v_t.state not in ('draft', 'rejected') then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  select qv.published_at, qv.version into v_published, v_number
  from public.question_versions qv where qv.id = p_version_id;
  if v_published is not null then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  select * into v_q from public.questions q where q.id = v_t.question_id for update;

  perform public.admin_internal_log_activity(
    v_actor, v_role, 'question.discarded', 'question_version', p_version_id,
    pg_catalog.jsonb_build_object('question_id', v_q.id, 'version', v_number), null);

  -- A question that never had a published version and has no other version goes
  -- with its only draft. Everything else just loses this version.
  if v_q.published_version is null
     and not exists (select 1 from public.question_versions qv
                     where qv.question_id = v_q.id and qv.id <> p_version_id) then
    delete from public.questions where id = v_q.id;
  else
    delete from public.question_versions where id = p_version_id;
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- 5. Review (Super Admin and Question reviewer)
-- -----------------------------------------------------------------------------

-- 5.1 Approve a submitted version. This publishes it. Never your own version.
create function public.admin_question_approve(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_role   public.admin_role;
  v_t      public.admin_question_versions%rowtype;
  v_q      public.questions%rowtype;
  v_number integer;
begin
  perform public.admin_internal_lock_shared();
  v_actor := public.admin_internal_require_role(array['super_admin', 'question_reviewer']::public.admin_role[]);
  select a.role into v_role from public.admin_users a where a.user_id = v_actor;

  select * into v_t from public.admin_question_versions a
  where a.question_version_id = p_version_id for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_t.state <> 'submitted' then
    raise exception 'invalid_state' using errcode = '22023';
  end if;
  if v_t.author_id = v_actor then
    raise exception 'cannot_review_own' using errcode = '42501';
  end if;

  select * into v_q from public.questions q where q.id = v_t.question_id for update;
  if v_q.status = 'retired' then
    raise exception 'question_retired' using errcode = '22023';
  end if;

  update public.admin_question_versions
     set state = 'approved', reviewer_id = v_actor,
         reviewed_at = pg_catalog.now(), updated_at = pg_catalog.now()
   where question_version_id = p_version_id;

  -- The student schema's own publish function does the publishing.
  perform public.publish_question_version(p_version_id);

  select qv.version into v_number from public.question_versions qv where qv.id = p_version_id;
  perform public.admin_internal_log_activity(
    v_actor, v_role, 'question.approved', 'question_version', p_version_id,
    pg_catalog.jsonb_build_object('question_id', v_t.question_id, 'version', v_number), null);
end
$$;

-- 5.2 Reject a submitted version, with a reason. Never your own version.
create function public.admin_question_reject(p_version_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_role   public.admin_role;
  v_reason text;
  v_t      public.admin_question_versions%rowtype;
  v_number integer;
begin
  perform public.admin_internal_lock_shared();
  v_actor  := public.admin_internal_require_role(array['super_admin', 'question_reviewer']::public.admin_role[]);
  v_reason := public.admin_internal_check_reason(p_reason);
  select a.role into v_role from public.admin_users a where a.user_id = v_actor;

  select * into v_t from public.admin_question_versions a
  where a.question_version_id = p_version_id for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_t.state <> 'submitted' then
    raise exception 'invalid_state' using errcode = '22023';
  end if;
  if v_t.author_id = v_actor then
    raise exception 'cannot_review_own' using errcode = '42501';
  end if;

  update public.admin_question_versions
     set state = 'rejected', reviewer_id = v_actor, reviewed_at = pg_catalog.now(),
         review_note = v_reason, updated_at = pg_catalog.now()
   where question_version_id = p_version_id;

  select qv.version into v_number from public.question_versions qv where qv.id = p_version_id;
  perform public.admin_internal_log_activity(
    v_actor, v_role, 'question.rejected', 'question_version', p_version_id,
    pg_catalog.jsonb_build_object('question_id', v_t.question_id, 'version', v_number), v_reason);
end
$$;

-- 5.3 Retire a published question (it stops being served to new attempts).
create function public.admin_question_retire(p_question_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_role   public.admin_role;
  v_reason text;
  v_q      public.questions%rowtype;
begin
  perform public.admin_internal_lock_shared();
  v_actor  := public.admin_internal_require_role(array['super_admin', 'question_reviewer']::public.admin_role[]);
  v_reason := public.admin_internal_check_reason(p_reason);
  select a.role into v_role from public.admin_users a where a.user_id = v_actor;

  select * into v_q from public.questions q where q.id = p_question_id for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_q.status <> 'published' then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  update public.questions set status = 'retired' where id = p_question_id;

  perform public.admin_internal_log_activity(
    v_actor, v_role, 'question.retired', 'question', p_question_id,
    pg_catalog.jsonb_build_object('published_version', v_q.published_version), v_reason);
end
$$;

-- 5.4 Restore a retired question to its last published version.
create function public.admin_question_restore(p_question_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor  uuid;
  v_role   public.admin_role;
  v_reason text;
  v_q      public.questions%rowtype;
begin
  perform public.admin_internal_lock_shared();
  v_actor  := public.admin_internal_require_role(array['super_admin', 'question_reviewer']::public.admin_role[]);
  v_reason := public.admin_internal_check_reason(p_reason);
  select a.role into v_role from public.admin_users a where a.user_id = v_actor;

  select * into v_q from public.questions q where q.id = p_question_id for update;
  if not found then
    raise exception 'target_not_found' using errcode = 'P0002';
  end if;
  if v_q.status <> 'retired' or v_q.published_version is null then
    raise exception 'invalid_state' using errcode = '22023';
  end if;

  update public.questions set status = 'published' where id = p_question_id;

  perform public.admin_internal_log_activity(
    v_actor, v_role, 'question.restored', 'question', p_question_id,
    pg_catalog.jsonb_build_object('published_version', v_q.published_version), v_reason);
end
$$;

-- -----------------------------------------------------------------------------
-- 6. Reads (Super Admin, Academic admin and Question reviewer)
-- -----------------------------------------------------------------------------

-- 6.1 List versions. No answer keys here. p_state: imported, draft, submitted,
-- approved or rejected.
create function public.admin_question_list(
  p_course_id uuid default null,
  p_state     text default null,
  p_limit     integer default 50,
  p_offset    integer default 0
)
returns table (
  version_id      uuid,
  question_id     uuid,
  version         integer,
  review_state    text,
  question_status public.question_status,
  is_live         boolean,
  course_code     text,
  topic_title     text,
  stem            text,
  difficulty      public.question_difficulty,
  author_email    text,
  updated_at      timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.admin_internal_require_role(
    array['super_admin', 'academic_admin', 'question_reviewer']::public.admin_role[]);

  if p_state is not null
     and p_state not in ('imported', 'draft', 'submitted', 'approved', 'rejected') then
    raise exception 'invalid_filter' using errcode = '22023';
  end if;

  return query
    select qv.id,
           q.id,
           qv.version,
           coalesce(a.state::text, 'imported'),
           q.status,
           (q.status = 'published' and q.published_version = qv.version),
           c.code,
           t.title,
           qv.body ->> 'stem',
           qv.difficulty,
           u.email::text,
           coalesce(a.updated_at, qv.created_at)
    from public.question_versions qv
    join public.questions q on q.id = qv.question_id
    join public.courses c on c.id = q.course_id
    left join public.topics t on t.id = q.topic_id
    left join public.admin_question_versions a on a.question_version_id = qv.id
    left join auth.users u on u.id = a.author_id
    where (p_course_id is null or q.course_id = p_course_id)
      and (p_state is null or coalesce(a.state::text, 'imported') = p_state)
    order by coalesce(a.updated_at, qv.created_at) desc, qv.id
    limit least(greatest(coalesce(p_limit, 50), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0);
end
$$;

-- 6.2 One version in full, including the answer key and review history.
create function public.admin_question_get(p_version_id uuid)
returns table (
  version_id        uuid,
  question_id       uuid,
  version           integer,
  review_state      text,
  question_status   public.question_status,
  is_live           boolean,
  course_id         uuid,
  course_code       text,
  topic_id          uuid,
  topic_title       text,
  difficulty        public.question_difficulty,
  stem              text,
  options           jsonb,
  correct_option_id text,
  explanation       text,
  author_email      text,
  reviewer_email    text,
  review_note       text,
  submitted_at      timestamptz,
  reviewed_at       timestamptz,
  is_mine           boolean
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
    select qv.id,
           q.id,
           qv.version,
           coalesce(a.state::text, 'imported'),
           q.status,
           (q.status = 'published' and q.published_version = qv.version),
           c.id,
           c.code,
           q.topic_id,
           t.title,
           qv.difficulty,
           qv.body ->> 'stem',
           qv.body -> 'options',
           s.correct_option_ids[1],
           s.explanation ->> 'text',
           au.email::text,
           ru.email::text,
           a.review_note,
           a.submitted_at,
           a.reviewed_at,
           (a.author_id is not null and a.author_id = auth.uid())
    from public.question_versions qv
    join public.questions q on q.id = qv.question_id
    join public.courses c on c.id = q.course_id
    left join public.topics t on t.id = q.topic_id
    left join public.question_version_solutions s on s.question_version_id = qv.id
    left join public.admin_question_versions a on a.question_version_id = qv.id
    left join auth.users au on au.id = a.author_id
    left join auth.users ru on ru.id = a.reviewer_id
    where qv.id = p_version_id;
end
$$;

-- -----------------------------------------------------------------------------
-- 7. Privileges. Every role is revoked by name (this project's default
--    privileges grant new functions and tables to API roles), then the few
--    intended grants are made.
-- -----------------------------------------------------------------------------
alter table public.admin_question_versions enable row level security;
alter table public.admin_activity_log      enable row level security;
-- Deliberately no policies.

revoke all on table public.admin_question_versions, public.admin_activity_log
  from public, anon, authenticated, service_role;
revoke all on sequence public.admin_activity_log_id_seq
  from public, anon, authenticated, service_role;

revoke all on function public.admin_internal_lock_shared()                                  from public, anon, authenticated, service_role;
revoke all on function public.admin_internal_require_role(public.admin_role[])              from public, anon, authenticated, service_role;
revoke all on function public.admin_internal_build_question(text, text[], text, text, public.question_difficulty) from public, anon, authenticated, service_role;
revoke all on function public.admin_internal_log_activity(uuid, public.admin_role, text, text, uuid, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public.admin_qv_guard_trg()                                          from public, anon, authenticated, service_role;
revoke all on function public.admin_question_create_draft(uuid, uuid, text, text[], text, text, public.question_difficulty)  from public, anon, authenticated, service_role;
revoke all on function public.admin_question_create_version(uuid, text, text[], text, text, public.question_difficulty)      from public, anon, authenticated, service_role;
revoke all on function public.admin_question_update_draft(uuid, uuid, text, text[], text, text, public.question_difficulty)  from public, anon, authenticated, service_role;
revoke all on function public.admin_question_submit(uuid)                                   from public, anon, authenticated, service_role;
revoke all on function public.admin_question_discard_draft(uuid)                            from public, anon, authenticated, service_role;
revoke all on function public.admin_question_approve(uuid)                                  from public, anon, authenticated, service_role;
revoke all on function public.admin_question_reject(uuid, text)                             from public, anon, authenticated, service_role;
revoke all on function public.admin_question_retire(uuid, text)                             from public, anon, authenticated, service_role;
revoke all on function public.admin_question_restore(uuid, text)                            from public, anon, authenticated, service_role;
revoke all on function public.admin_question_list(uuid, text, integer, integer)             from public, anon, authenticated, service_role;
revoke all on function public.admin_question_get(uuid)                                      from public, anon, authenticated, service_role;

grant execute on function public.admin_question_create_draft(uuid, uuid, text, text[], text, text, public.question_difficulty)  to authenticated;
grant execute on function public.admin_question_create_version(uuid, text, text[], text, text, public.question_difficulty)      to authenticated;
grant execute on function public.admin_question_update_draft(uuid, uuid, text, text[], text, text, public.question_difficulty)  to authenticated;
grant execute on function public.admin_question_submit(uuid)                                to authenticated;
grant execute on function public.admin_question_discard_draft(uuid)                         to authenticated;
grant execute on function public.admin_question_approve(uuid)                               to authenticated;
grant execute on function public.admin_question_reject(uuid, text)                          to authenticated;
grant execute on function public.admin_question_retire(uuid, text)                          to authenticated;
grant execute on function public.admin_question_restore(uuid, text)                         to authenticated;
grant execute on function public.admin_question_list(uuid, text, integer, integer)          to authenticated;
grant execute on function public.admin_question_get(uuid)                                   to authenticated;

-- -----------------------------------------------------------------------------
-- 8. Self-check: nothing commits unless the privilege model is what this file
--    intends.
-- -----------------------------------------------------------------------------
do $$
declare
  v_new       text[] := array[
    'admin_internal_lock_shared', 'admin_internal_require_role',
    'admin_internal_build_question', 'admin_internal_log_activity', 'admin_qv_guard_trg',
    'admin_question_create_draft', 'admin_question_create_version',
    'admin_question_update_draft', 'admin_question_submit', 'admin_question_discard_draft',
    'admin_question_approve', 'admin_question_reject', 'admin_question_retire',
    'admin_question_restore', 'admin_question_list', 'admin_question_get'];
  v_app       text[] := array[
    'admin_question_create_draft', 'admin_question_create_version',
    'admin_question_update_draft', 'admin_question_submit', 'admin_question_discard_draft',
    'admin_question_approve', 'admin_question_reject', 'admin_question_retire',
    'admin_question_restore', 'admin_question_list', 'admin_question_get'];
  v_invoker   text[] := array['admin_internal_build_question', 'admin_qv_guard_trg'];
  r           record;
  v_t         text;
  v_n         integer := 0;
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
      where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\') <> 37 then
    raise exception 'Self-check failed: expected 37 admin functions in total';
  end if;

  foreach v_t in array array['public.admin_question_versions', 'public.admin_activity_log'] loop
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

notify pgrst, 'reload schema';

commit;