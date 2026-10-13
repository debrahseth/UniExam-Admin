# Architecture

## Boundaries

- UniExam Admin is its own repository and deployment.
- It shares one Supabase project (auth and data) with the student app. There is no second database.
- It must never modify the student app or its repository.
- Admin database objects (tables, functions, policies) will live in migrations in this repository, starting in Milestone 1B.

## Current state (Milestone 1A)

No Supabase connection, no authentication, no data access. Every page is static UI or a placeholder.

### Routes

| Route                                                                                           | Content                                                                                       |
| ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `/`                                                                                             | Redirects to `/admin` in preview mode, otherwise a closed page with a disabled sign-in button |
| `/admin`                                                                                        | Dashboard placeholder                                                                         |
| `/admin/academic`, `/questions`, `/support`, `/analytics`, `/access`, `/audit-log`, `/settings` | Placeholder pages                                                                             |

Route names and which roles will see each item are defined in `src/config/navigation.ts`. Role identifiers there are provisional and will be reconciled with the master spec in 1B. The role hints affect nothing in 1A.

### Preview gate

`src/lib/admin-preview.ts` returns true only when `ADMIN_PREVIEW_ENABLED === "true"`. The `(admin)` layout and `/` call `await connection()` first, so the check runs on every request and is never baked in at build time. When the flag is not exactly `true`, the layout calls `notFound()`.

This gate is a stand-in for authentication. It is not an authorization system. Next.js does not re-run a layout on client-side navigation between its children, so real authorization must be enforced where data is read and written, not in layouts.

### App shell

`(admin)/layout.tsx` composes `SidebarProvider`, `AppSidebar`, `SidebarInset` and `AppHeader`. The header currently shows "Not signed in (preview)". Breadcrumbs are derived from the path and the titles in `navigation.ts`.

### System states

- Loading: `(admin)/loading.tsx`
- Error: `(admin)/error.tsx` (shows only a digest reference, never the error message)
- Not found: `app/not-found.tsx`
- Forbidden: `ForbiddenState` component, not routed yet

## Security invariants (apply from 1B onward)

1. Authorization is enforced on the server and in the database. The UI is never a security boundary.
2. Only the Super Admin can grant, change, suspend or revoke admin access, and revocation takes effect immediately.
3. The Super Admin is a separately provisioned auth identity, linked by exact user ID. There is no public registration, bootstrap endpoint or hardcoded password.
4. The service-role key stays server-side and never appears in browser code or `NEXT_PUBLIC_` variables.
5. Every new table enables row-level security in the same migration that creates it.
6. Every new function revokes `EXECUTE` from `public`, `anon` and `authenticated`, then grants explicitly. The shared database's default privileges otherwise expose new functions.
7. Sensitive actions are written to an append-only audit log.

## Planned: Milestone 1B

Not started. Open decisions before work begins: how the Super Admin is provisioned, whether MFA is required, whether an admin can hold multiple roles or course scopes, how cookies and domains are separated from the student app, and which test tooling to use.
