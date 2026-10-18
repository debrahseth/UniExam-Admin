-- =============================================================================
-- UniExam - READ-ONLY preview for the dev reset. Changes nothing.
-- Run each block separately in the SQL editor (result limit: No limit).
-- =============================================================================

-- P1. Which project am I in? EXPECT the definition to contain yzywcnrjlzqpgshutlxf.
select conrelid::regclass as table_name, pg_get_constraintdef(oid) as definition
from pg_constraint where conname = 'profiles_avatar_url_in_bucket';

-- P2. Row counts.
select 'questions' as t, count(*) as n from public.questions
union all select 'question_versions', count(*) from public.question_versions
union all select 'question_version_solutions', count(*) from public.question_version_solutions
union all select 'admin_question_versions', count(*) from public.admin_question_versions
union all select 'admin_activity_log', count(*) from public.admin_activity_log
union all select 'admin_audit_log', count(*) from public.admin_audit_log
union all select 'courses', count(*) from public.courses;

-- P3. What the guards will refuse: published versions, and review rows past draft/rejected.
select (select count(*) from public.question_versions where published_at is not null) as published_versions,
       (select count(*) from public.admin_question_versions where state in ('submitted','approved')) as review_rows_not_deletable;

-- P4. Student attempts that used these questions. Any row here blocks deleting the
--     question versions (foreign key). Only test data should be in here.
select count(*) as attempt_question_rows, count(distinct attempt_id) as attempts
from public.attempt_questions;

-- P5. Audit log: pick where to cut. Only the NEWEST rows can be removed without
--     breaking the hash chain, so choose the last id you want to KEEP.
select * from public.admin_verify_audit_chain();
select id, occurred_at, action, target_user_id, left(reason, 60) as reason
from public.admin_audit_log order by id;

-- P6. Courses and what depends on them (any non-zero count besides questions
--     will block that course from being deleted).
select c.code, c.title,
       (select count(*) from public.questions q          where q.course_id = c.id) as questions,
       (select count(*) from public.exam_attempts a      where a.course_id = c.id) as attempts,
       (select count(*) from public.exam_rooms r         where r.course_id = c.id) as rooms,
       (select count(*) from public.programme_courses p  where p.course_id = c.id) as programme_links,
       (select count(*) from public.topics t             where t.course_id = c.id) as topics
from public.courses c order by c.code;