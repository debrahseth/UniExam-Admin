# AI Agent Rules — UniExam Admin

These rules apply to every development session on this project.

## Project boundaries

- UniExam Admin is a separate application from the student app (`debrahseth/UniExam`). Never edit the student repo as part of admin work.
- Both apps share one Supabase project. Do not create a second database or duplicate student data.
- No admin migration may change a student table, policy, trigger, function, grant or default privilege. Prove it with the schema fingerprint query in `supabase/verification` before and after every migration: the values must be identical.

## Security invariants (non-negotiable)

- Authorization is enforced on the server and in the database (RLS or permission-checked functions). Hiding links, disabling buttons and layout redirects are not security. Layouts do not re-run on client-side navigation.
- Only the designated Super Admin can grant, change, suspend or revoke administrative access, and revocation takes effect immediately.
- The Super Admin is a separate, explicitly provisioned auth identity, linked by exact user ID. Never trust email, user metadata or JWT claims alone. Role and status are read from `admin_users` by database functions on every call.
- An account with a student profile cannot be an administrator. Only grant access to accounts created for administration, and never sign an administrator account in to the student app.
- Every administrator must pass TOTP (aal2) in a session the database has verified. Never treat an aal2 claim alone as proof.
- No public admin registration route. No bootstrap endpoint. No hardcoded passwords. Provisioning and recovery of the Super Admin are operator-only, run from the SQL editor.
- Never expose the service-role key or any secret to browser code or `NEXT_PUBLIC_` variables. This app does not use the service-role key at all.
- Every new table enables RLS in the same migration.
- Every new database function fixes its `search_path`, revokes EXECUTE from `public`, `anon`, `authenticated` and `service_role` by name, then grants access explicitly. This project's default privileges otherwise make new functions callable by students.
- Sensitive administrative actions are written to the append-only audit log in the same transaction as the change, with a required reason.
- Keep the admin auth cookie name distinct from the student app's. Never change it to the default.

## Working rules

- Work in small batches. Give complete file paths and full file contents.
- Before replacing an existing file, name it and explain why. Ask to see a file before editing it rather than guessing its contents.
- Never claim lint, type-check, build or tests passed unless they were run and the output was seen.
- Never present fake data as real. Placeholders must be visibly marked as not implemented.
- Do not invent database schema. Verify against the live database with read-only queries.
- Ask before making any security-sensitive assumption, and say so plainly when something is unverified.
- No destructive database change without explicit review.

## Database change process

1. Write the migration, a rollback script and a verification script together. Migrations are single transactions with a preflight at the start and a self-check at the end that fails the whole transaction if the privilege model is not what the file intends.
2. The person running it reads the full SQL first. Nothing is applied on the strength of a summary.
3. Confirm the project in the dashboard is the intended development project before running anything.
4. Run the verification queries before, apply once as `postgres`, run them after, and compare the student schema fingerprint.
5. Never run a migration against any other project without a fresh review.
6. After significant audit activity, run `admin_verify_audit_chain()` and store a row ID and its hash outside Supabase.

## Application code rules

- Server actions validate the shape of their input, call a database function, and translate its error codes to plain messages. They contain no authorization logic of their own.
- Every reader of database results validates the shape and fails closed.
- Never show raw errors, SQL or stack traces. A short reference code is fine.
- A page that reads or changes data for a role must authorize in the database, not only in the page.
- Never put a secret, a key or a `.env` value in a prompt, a commit or a screenshot. Share variable names only.

## Current status

- Milestone 1B, local development only: sign-in, mandatory TOTP, database-backed access gate, admin access management and the audit log page are built and working.
- Placeholder pages (academic, questions, support, analytics, settings) read no data.
- Nothing is deployed, and there are no automated tests yet.
- See `ARCHITECTURE.md` for the model, the recovery procedure and the open items.
