-- ROLLBACK for 20261016120000_admin_review_catalog.sql
-- Drops the five reviewer catalog functions. Destroys no data. Run as postgres.
begin;

drop function if exists public.admin_topic_questions(uuid, uuid, text);
drop function if exists public.admin_catalog_topics(uuid, text);
drop function if exists public.admin_catalog_courses(uuid);
drop function if exists public.admin_catalog_programmes();
drop function if exists public.admin_internal_filter_match(text, text, boolean, boolean, boolean);

notify pgrst, 'reload schema';

commit;