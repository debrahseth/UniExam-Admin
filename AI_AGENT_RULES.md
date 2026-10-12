# AI Agent Rules — UniExam Admin

These rules apply to every development session on this project.

## Project boundaries

- UniExam Admin is a separate application from the student app (`debrahseth/UniExam`). Never edit the student repo as part of admin work.
- Both apps share one Supabase project. Do not create a second database or duplicate student data.

## Security invariants (non-negotiable)

- Authorization is enforced on the server and in the database (RLS or permission-checked functions). Hiding links or disabling buttons is not security.
- Only the designated Super Admin can grant, change, suspend or revoke administrative access.
- The Super Admin is a separate, explicitly provisioned auth identity, linked by exact user ID. Never trust email, user metadata or JWT claims alone.
- No public admin registration route. No bootstrap endpoint. No hardcoded passwords.
- Never expose the service-role key or any secret to browser code or `NEXT_PUBLIC_` variables.
- Every new table enables RLS in the same migration.
- Every new database function revokes EXECUTE from `public`, `anon` and `authenticated`, then grants access explicitly. This project's default privileges otherwise make new functions callable by students.
- Sensitive administrative actions are written to an append-only audit log.

## Working rules

- Work in small batches. Give complete file paths and full file contents.
- Before replacing an existing file, name it and explain why.
- Never claim lint, type-check, build or tests passed unless they were run and the output was seen.
- Never present fake data as real. Placeholders must be visibly marked as not implemented.
- Do not invent database schema. Verify against the live database or `DATABASE.md`.
- Ask before making any security-sensitive assumption.
- No destructive database change without explicit review.

## Current status

- Milestone 1A (UI foundation): no authentication, no Supabase connection, no migrations.
- The admin UI is hidden unless `ADMIN_PREVIEW_ENABLED=true` is set.
