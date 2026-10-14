--- Run each line separately

select user_id, role, status from public.admin_users order by created_at;
select count(*) from public.admin_audit_log;
select ok, rows_checked from public.admin_verify_audit_chain();
select count(*) from auth.users where email like '%@uniexam-test.invalid';