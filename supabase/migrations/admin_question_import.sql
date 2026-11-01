-- =============================================================================
-- UniExam Admin - Milestone 1B, Batch 4: question import
-- File: supabase/migrations/20261031150000_admin_question_import.sql
--
-- Creates exactly ONE new object: the function admin_question_import_batch(jsonb).
-- No table, type, trigger or index is created, and no existing object is changed.
--
-- What it does: takes an array of questions (at most 100) and creates each as a
-- DRAFT through the existing admin_question_create_draft, so every item passes
-- the same validation as the editor form and the student schema's own guards.
-- It then sets questions.external_key and question_versions.source on the rows
-- it just created. Each item runs in its own sub-transaction: one bad item is
-- reported and rolled back without touching the others.
--
-- Result: one row per item, in order:
--   o_outcome  'created' | 'skipped' (the key already exists) | 'failed'
--   o_error    null, or one of: invalid_item, invalid_key, invalid_source,
--              invalid_course, invalid_topic, invalid_stem, invalid_options,
--              invalid_correct, invalid_difficulty, invalid_explanation,
--              duplicate_key, unexpected_error
-- Whole-batch errors (raised, nothing created): not_authorized, invalid_batch,
-- batch_too_large.
--
-- Item shape (all ids are resolved by the app before calling):
--   { "key": text, "source": text|null, "course_id": uuid, "topic_id": uuid,
--     "stem": text, "options": [text, ...], "correct": "a".."f",
--     "explanation": text|null, "difficulty": "easy"|"medium"|"hard" }
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

  if to_regprocedure('public.admin_question_import_batch(jsonb)') is not null then
    raise exception 'admin_question_import_batch already exists. Use the rollback script first.';
  end if;

  if to_regprocedure('public.admin_question_create_draft(uuid, uuid, text, text[], text, text, public.question_difficulty)') is null
     or to_regprocedure('public.admin_internal_require_role(public.admin_role[])') is null
     or to_regprocedure('public.admin_internal_lock_shared()') is null then
    raise exception 'Admin migration 20261014090000 must be applied first.';
  end if;

  perform 1
  from (values ('questions', 'external_key'), ('question_versions', 'source')) as r(t, c)
  where not exists (
    select 1 from pg_attribute a
    where a.attrelid = to_regclass('public.' || r.t)
      and a.attname = r.c
      and not a.attisdropped
  );
  if found then
    raise exception 'Expected columns questions.external_key and question_versions.source are missing. Aborting.';
  end if;

  if to_regclass('public.questions_external_key_key') is null then
    raise exception 'The unique index on questions.external_key is missing. Aborting.';
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- 1. The function
-- -----------------------------------------------------------------------------
create function public.admin_question_import_batch(p_items jsonb)
returns table (
  o_index      integer,
  o_key        text,
  o_outcome    text,
  o_version_id uuid,
  o_error      text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  c_ws   constant text := E' \t\r\n';

  v_item    jsonb;
  v_idx     integer;
  v_key     text;
  v_source  text;
  v_text    text;
  v_course  uuid;
  v_topic   uuid;
  v_options text[];
  v_diff    public.question_difficulty;
  v_version uuid;
  v_outcome text;
  v_code    text;
begin
  perform public.admin_internal_lock_shared();
  perform public.admin_internal_require_role(array['super_admin', 'academic_admin']::public.admin_role[]);

  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array' then
    raise exception 'invalid_batch' using errcode = '22023';
  end if;
  if pg_catalog.jsonb_array_length(p_items) > 100 then
    raise exception 'batch_too_large' using errcode = '22023';
  end if;

  for v_idx, v_item in
    select (t.n)::integer, t.e
    from pg_catalog.jsonb_array_elements(p_items) with ordinality as t(e, n)
    order by t.n
  loop
    v_key := null;
    v_version := null;
    v_outcome := null;
    v_code := null;

    -- Everything for one item happens inside this block. If anything fails, the
    -- block's changes are rolled back and the item is reported as failed.
    begin
      if pg_catalog.jsonb_typeof(v_item) <> 'object' then
        raise exception 'invalid_item' using errcode = '22023';
      end if;

      v_key := v_item ->> 'key';
      if pg_catalog.jsonb_typeof(v_item -> 'key') is distinct from 'string'
         or v_key !~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$' then
        raise exception 'invalid_key' using errcode = '22023';
      end if;

      -- An existing key is skipped before anything else is checked, so a seed
      -- file can be run again safely.
      if exists (select 1 from public.questions q where q.external_key = v_key) then
        v_outcome := 'skipped';
      else
        -- source: optional text, trimmed, blank means none, at most 200 characters.
        if pg_catalog.jsonb_typeof(v_item -> 'source') not in ('string', 'null') then
          raise exception 'invalid_source' using errcode = '22023';
        end if;
        v_source := pg_catalog.btrim(coalesce(v_item ->> 'source', ''), c_ws);
        if v_source = '' then
          v_source := null;
        elsif pg_catalog.char_length(v_source) > 200 or v_source ~ '[[:cntrl:]]' then
          raise exception 'invalid_source' using errcode = '22023';
        end if;

        -- course and topic: ids only. Whether they exist and belong together is
        -- checked by admin_question_create_draft.
        v_text := v_item ->> 'course_id';
        if pg_catalog.jsonb_typeof(v_item -> 'course_id') is distinct from 'string'
           or v_text !~* c_uuid then
          raise exception 'invalid_course' using errcode = '22023';
        end if;
        v_course := v_text::uuid;

        v_text := v_item ->> 'topic_id';
        if pg_catalog.jsonb_typeof(v_item -> 'topic_id') is distinct from 'string'
           or v_text !~* c_uuid then
          raise exception 'invalid_topic' using errcode = '22023';
        end if;
        v_topic := v_text::uuid;

        -- difficulty must be a label of the enum.
        if pg_catalog.jsonb_typeof(v_item -> 'difficulty') is distinct from 'string'
           or not exists (
             select 1 from pg_catalog.pg_enum e
             where e.enumtypid = 'public.question_difficulty'::pg_catalog.regtype
               and e.enumlabel = (v_item ->> 'difficulty')) then
          raise exception 'invalid_difficulty' using errcode = '22023';
        end if;
        v_diff := (v_item ->> 'difficulty')::public.question_difficulty;

        -- Types only. Lengths, counts, duplicates, the correct letter and
        -- control characters are enforced by admin_question_create_draft.
        if pg_catalog.jsonb_typeof(v_item -> 'stem') is distinct from 'string' then
          raise exception 'invalid_stem' using errcode = '22023';
        end if;

        if pg_catalog.jsonb_typeof(v_item -> 'options') is distinct from 'array' then
          raise exception 'invalid_options' using errcode = '22023';
        end if;
        if pg_catalog.jsonb_array_length(v_item -> 'options') > 6 then
          raise exception 'invalid_options' using errcode = '22023';
        end if;
        if exists (select 1 from pg_catalog.jsonb_array_elements(v_item -> 'options') as o
                   where pg_catalog.jsonb_typeof(o) <> 'string') then
          raise exception 'invalid_options' using errcode = '22023';
        end if;
        select coalesce(pg_catalog.array_agg(t.o #>> '{}' order by t.n), array[]::text[])
          into v_options
        from pg_catalog.jsonb_array_elements(v_item -> 'options') with ordinality as t(o, n);

        if pg_catalog.jsonb_typeof(v_item -> 'correct') is distinct from 'string' then
          raise exception 'invalid_correct' using errcode = '22023';
        end if;

        if pg_catalog.jsonb_typeof(v_item -> 'explanation') not in ('string', 'null') then
          raise exception 'invalid_explanation' using errcode = '22023';
        end if;

        v_version := public.admin_question_create_draft(
          v_course, v_topic,
          v_item ->> 'stem', v_options, v_item ->> 'correct',
          v_item ->> 'explanation', v_diff);

        update public.questions as q
           set external_key = v_key
         where q.id = (select qv.question_id
                       from public.question_versions as qv
                       where qv.id = v_version);

        update public.question_versions as qv
           set source = v_source
         where qv.id = v_version;

        v_outcome := 'created';
      end if;
    exception when others then
      v_outcome := 'failed';
      v_version := null;
      v_code := case
        when sqlerrm in ('invalid_item', 'invalid_key', 'invalid_source', 'invalid_course',
                         'invalid_topic', 'invalid_stem', 'invalid_options',
                         'invalid_correct', 'invalid_difficulty', 'invalid_explanation')
          then sqlerrm
        when sqlstate = '23505' then 'duplicate_key'
        else 'unexpected_error'
      end;
    end;

    return query select v_idx, v_key, v_outcome, v_version, v_code;
  end loop;
end
$$;

comment on function public.admin_question_import_batch(jsonb) is
  'Creates up to 100 questions as drafts, one result row per item. Existing keys are skipped. Super Admin and Academic admin only.';

-- -----------------------------------------------------------------------------
-- 2. Privileges. Every role is revoked by name (this project's default
--    privileges grant new functions to API roles), then the one grant is made.
-- -----------------------------------------------------------------------------
revoke all on function public.admin_question_import_batch(jsonb)
  from public, anon, authenticated, service_role;

grant execute on function public.admin_question_import_batch(jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Self-check: nothing commits unless the privilege model is what this file
--    intends. Totals are pinned: 46 admin functions (27 callable) before this
--    migration, 47 (28 callable) after.
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  select p.oid, p.prosecdef, p.proconfig
    into r
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname = 'admin_question_import_batch';

  if not found then
    raise exception 'Self-check failed: the function was not created';
  end if;

  if has_function_privilege('anon', r.oid, 'execute')
     or has_function_privilege('service_role', r.oid, 'execute') then
    raise exception 'Self-check failed: anon or service_role can execute the function';
  end if;

  if not has_function_privilege('authenticated', r.oid, 'execute') then
    raise exception 'Self-check failed: signed-in users cannot execute the function';
  end if;

  if not r.prosecdef then
    raise exception 'Self-check failed: the function is not SECURITY DEFINER';
  end if;

  if r.proconfig is null
     or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
    raise exception 'Self-check failed: the function has no fixed search_path';
  end if;

  if (select count(*) from pg_proc
      where pronamespace = 'public'::regnamespace and proname like 'admin\_%' escape '\') <> 47 then
    raise exception 'Self-check failed: expected 47 admin functions in total';
  end if;

  if (select count(*) from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.proname like 'admin\_%' escape '\'
        and has_function_privilege('authenticated', p.oid, 'execute')) <> 28 then
    raise exception 'Self-check failed: expected 28 admin functions callable by signed-in users';
  end if;
end
$$;

notify pgrst, 'reload schema';

commit;