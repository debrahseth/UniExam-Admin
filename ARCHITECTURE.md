# Architecture

## Boundaries

- UniExam Admin is its own repository and deployment.
- It shares one Supabase project (auth and data) with the student app. There is no second database.
- It must never modify the student app or its repository, and no admin migration may change a student table, policy, trigger, function, grant or default privilege. Each migration is checked with a before-and-after fingerprint of the student schema.
- Admin database objects (tables, functions, policies) live in migrations in this repository.
- The two apps run on separate origins. Locally they share `localhost`, and browsers share cookies across ports, so this app uses its own auth cookie name (`sb-uniexam-admin-auth`). Never change it to the default.

## Current state (Milestone 1B, development only)

Working: sign-in, mandatory TOTP, the database-backed access gate, admin access management and the audit log page. Not deployed anywhere, and exercised against the development Supabase project only.

### Routes

| Route                                                                  | Content                                                                    |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `/`                                                                    | Redirects to `/admin` or `/sign-in` depending on the caller's access state |
| `/sign-in`                                                             | Email and password sign-in. No sign-up route exists.                       |
| `/mfa/enroll`                                                          | First-time authenticator setup (QR code and a confirming code)             |
| `/mfa/verify`                                                          | Second step at sign-in for an account that already has an authenticator    |
| `/admin`                                                               | Dashboard placeholder                                                      |
| `/admin/access`                                                        | Admin management (Super Admin only)                                        |
| `/admin/audit-log`                                                     | Read-only audit log (Super Admin only)                                     |
| `/admin/academic`, `/questions`, `/support`, `/analytics`, `/settings` | Placeholder pages. They read no data and perform no actions.               |

Navigation, and which roles see which item, is defined in `src/config/navigation.ts`. The role lists there only decide what is visible. They are not the permission matrix.

### Request flow

1. `src/proxy.ts` refreshes the Supabase session cookie on every request and marks responses `private, no-store`. It does not authorize anything and fails open if the Supabase variables are missing.
2. The `(admin)` layout calls `admin_get_my_access()` and routes on the result.
3. Pages and server actions call database functions that authorize again, inside the database.

### Access states

`admin_get_my_access()` returns one of five states. The layout and the MFA pages act on it like this:

| State                     | Meaning                                                                | Result                    |
| ------------------------- | ---------------------------------------------------------------------- | ------------------------- |
| `active` (with a role)    | Active admin, no student profile, verified authenticator, aal2 session | Shell renders             |
| `mfa_enrollment_required` | Active admin with no verified authenticator                            | Redirect to `/mfa/enroll` |
| `mfa_step_up_required`    | Active admin with an authenticator but a session below aal2            | Redirect to `/mfa/verify` |
| `suspended`               | Admin record is suspended                                              | Redirect to `/sign-in`    |
| `none`                    | No admin record, revoked, or has a student profile                     | Redirect to `/sign-in`    |

The reader in `src/lib/admin-access.ts` fails closed: any error, malformed reply or unknown value becomes `none`. It validates the token with `getUser()` and never trusts `getSession()` for a decision.

### Layouts are a UX gate only

Next.js does not re-run a layout on client-side navigation between its children. So the layout's redirects improve the experience but are not security. Authorization happens where data is read and written, in the database functions. Pages that show `ForbiddenState` to the wrong role do so for the same reason: it is cosmetic, and the database refuses the call regardless.

Placeholder pages read nothing and therefore carry no per-page check yet. The first page that reads real data for a role other than the Super Admin must add one.

### App shell

`(admin)/layout.tsx` composes `SidebarProvider`, `AppSidebar`, `SidebarInset` and `AppHeader`. The sidebar filters items by the live role (cosmetic) and shows it in the footer. The header shows the signed-in email and a sign-out button. Breadcrumbs derive from the path and the titles in `navigation.ts`.

### System states

- Loading: `(admin)/loading.tsx`
- Error: `(admin)/error.tsx` (shows only a digest reference, never the error message)
- Not found: `app/not-found.tsx`
- Forbidden: `ForbiddenState`, rendered by pages that are restricted to a role

## Security model

1. **Authorization lives in the database.** The UI is never a security boundary. Every admin function re-checks, on every call, that the caller is an active admin in a session that passed the MFA checks.
2. **Role and status are read live.** They are stored only in `admin_users` and never taken from the JWT, user metadata or browser state, so a suspension or revocation applies on the next call.
3. **Only the Super Admin changes admin access.** Grant, change role, suspend, reactivate and revoke all require the `super_admin` role inside the function. A Super Admin cannot target themselves, cannot modify the Super Admin record, and cannot assign `super_admin` through the app.
4. **Exactly one active Super Admin.** A partial unique index enforces it, and a global advisory lock serialises every admin mutation and audit write, so concurrent requests cannot create a second one.
5. **One role per admin.** `admin_users` has a single `role` column. There are no multiple roles or course scopes. Changing this later needs a migration.
6. **MFA is checked in the database.** Two separate facts are required: the account has a verified TOTP factor, and the current session is aal2 according to both the token and the live `auth.sessions` row. An aal2 claim alone is not trusted, because a factor removed after step-up would otherwise keep working until the token expires.
7. **Identity separation from students.** An account with a row in `public.profiles` cannot be granted admin access, and an existing admin who later gets a student profile immediately loses access (the state becomes `none`). A preflight in the migration proves that `profiles.id` is a foreign key to `auth.users.id`. This does not detect an account that has been used in the student app but has no profile row yet, so only grant access to accounts created for administration.
8. **Privileges.** The shared project's default privileges would otherwise let students call new functions. So every admin function is revoked from `public`, `anon`, `authenticated` and `service_role` by name, then granted explicitly. Tables have RLS on, no policies and no grants for any API role. There are 21 admin functions, of which 9 are callable by signed-in users: `admin_get_my_access`, `admin_grant_role`, `admin_change_role`, `admin_suspend`, `admin_reactivate`, `admin_revoke`, `admin_list_admins`, `admin_list_audit` and `admin_find_user_by_email`. All of them have a fixed `search_path`. Each migration ends with a self-check that fails the whole transaction if any of this is wrong.
9. **Secrets.** The service-role key is not used by this app and must never appear in browser code, a `NEXT_PUBLIC_` variable or the repository. Only the project URL and anon key are configured.
10. **No public admin registration.** There is no sign-up route and no bootstrap endpoint. Sign-ups are open on the shared project for students, so `admin_users` is the real gate: a stranger who signs up gets `none`, and the sign-in action signs non-admins out immediately with the same generic error as a wrong password.
11. **No redirect parameter on sign-in.** Sign-in always goes to `/admin`.

## Audit log

- Every administrative access change writes a row in the same transaction, enforced by a deferred constraint trigger: a change to `admin_users` without an audit row for that user cannot commit.
- A reason of 10 to 500 characters is required for every change.
- `UPDATE`, `DELETE` and `TRUNCATE` on the log are blocked by triggers.
- Rows form a hash chain: each row's hash includes the previous row's hash. `admin_verify_audit_chain()` recomputes it. It is operator-only and run from the SQL editor, not from the app.
- `target_user_id` is deliberately not a foreign key, so the log outlives deleted users.
- The log is tamper-evident, not tamper-proof. The database owner can disable the triggers and rewrite the table and its hashes. The defence is to store a row ID and its `row_hash` outside Supabase (for example in a password manager) after significant activity, and compare later. If the stored hash differs from that row's hash, or the row is gone, the log has been altered.

## Provisioning and recovery (operator only)

All of this runs in the Supabase SQL editor as `postgres`. The functions refuse any session that carries an end-user identity, and API roles cannot execute them.

- **First Super Admin.** Create the account in Supabase Authentication with a confirmed email. It must never have been used in the student app. Check it has no profile row. Then call `admin_bootstrap_super_admin(user_id, reason, false)`.
- **Reserve identity.** A second account is created and confirmed but is not added to `admin_users`. It exists so recovery can start quickly. It cannot be a second active Super Admin.
- **Replacing a lost Super Admin.** Call `admin_bootstrap_super_admin(reserve_user_id, reason, true)`. The old Super Admin is revoked in the same transaction and both steps are audited. The reserve identity must then sign in and enrol its own authenticator.
- **Lost authenticator.** The Super Admin cannot pass step-up. The operator can remove the account's TOTP factor so it can enrol again, or replace the Super Admin as above. The exact removal method has not been rehearsed. Test it on the development project before relying on it.
- **Anyone with `postgres` access is effectively root.** The Supabase dashboard login must have MFA and its own recovery method.

None of these recovery procedures has been rehearsed end to end.

## Decisions

| Date       | Decision                                                                                                |
| ---------- | ------------------------------------------------------------------------------------------------------- |
| 2026-10-13 | Admin access state is always read from `admin_users` by database functions, never from the JWT          |
| 2026-10-13 | Email and password with mandatory TOTP. No magic links.                                                 |
| 2026-10-13 | One role per admin                                                                                      |
| 2026-10-13 | The Super Admin is provisioned only by a database operator. It cannot be assigned from the app.         |
| 2026-10-13 | The admin app uses its own auth cookie name because both apps share one Supabase project on `localhost` |
| 2026-10-13 | An account with a student profile is ineligible for admin access, at grant time and on every request    |
| 2026-10-13 | The temporary preview flag was removed once real authorization existed                                  |

## Open items

- Permission matrix for roles other than the Super Admin, and the database functions that will enforce it
- Automated tests. None exist yet, and no test tooling has been chosen.
- Production: whether it uses a separate Supabase project, how migrations are applied there, separate domains so cookies never overlap, and the `secure` cookie flag (already on when `NODE_ENV` is `production`)
- Rehearsal of the recovery procedures above
- Session lifetime and any Supabase-level MFA or password settings
- Dark mode (tokens exist, switching does not)
