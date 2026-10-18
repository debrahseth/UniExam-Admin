-- ROLLBACK for 20261015090000_admin_question_search.sql
-- Drops the four question search functions. Destroys no data. Run as postgres.
begin;

drop function if exists public.admin_question_search(text, text, uuid, uuid, public.question_difficulty, timestamptz, uuid, text, integer);
drop function if exists public.admin_question_counts(text, uuid, uuid, public.question_difficulty);
drop function if exists public.admin_question_history(uuid);
drop function if exists public.admin_internal_question_base(uuid, text, uuid, uuid, public.question_difficulty);

notify pgrst, 'reload schema';

commit;