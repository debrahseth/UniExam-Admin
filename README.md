# UniExam Admin

Administration workspace for [UniExam](https://github.com/debrahseth/UniExam), the KNUST examination simulation platform. This is a separate application from the student app. It shares the same Supabase project (auth and data) and has no database of its own.

## Status: Milestone 1B (admin access), local development only

Built and working:

- Design system, app shell and system states (loading, error, not found, forbidden)
- Email and password sign-in with mandatory TOTP authenticator (aal2) for every administrator
- Database-backed access gate: role and status are read live from the database on every request
- Admin access management for the Super Admin: look up an account, grant, change role, suspend, reactivate, revoke, each with a required reason
- Audit log page for the Super Admin: a read-only view of the append-only, hash-chained log
- Separation from student identities: an account with a student profile cannot hold admin access

Not built yet:

- Academic structure, question review, support and analytics pages (placeholders that read no data)
- Automated tests
- Production deployment and a production database procedure
- Dark mode switching

The app has not been deployed anywhere. Everything has been exercised against the development Supabase project only.

## Stack

Next.js 16 (App Router), React 19, TypeScript (strict), Tailwind CSS v4, shadcn/ui (base-nova style, Base UI), lucide icons, Inter via `next/font`, Supabase (`@supabase/supabase-js`, `@supabase/ssr`). Package manager: npm.

## Getting started

```bash
npm install
cp .env.example .env.local   # then fill in the two Supabase values
npm run dev
```

Open `http://localhost:3000` (or the port Next.js prints). You will be sent to `/sign-in`.

There is no sign-up page and no bootstrap endpoint. Administrator accounts are created in Supabase Authentication with a confirmed email, then granted access by the Super Admin from `/admin/access`. The first Super Admin is provisioned once by a database operator; see [`ARCHITECTURE.md`](./ARCHITECTURE.md).

Never sign an administrator account in to the student app.

## Environment

| Variable                        | Purpose                                 |
| ------------------------------- | --------------------------------------- |
| `NEXT_PUBLIC_SUPABASE_URL`      | Supabase project URL. Public by design. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon key. Public by design.    |

Put real values in `.env.local`, which is not committed. Never create a variable for, or paste anywhere in this project, the service-role key. This app does not need it.

## Scripts

| Command             | Does               |
| ------------------- | ------------------ |
| `npm run dev`       | Development server |
| `npm run build`     | Production build   |
| `npm run lint`      | ESLint             |
| `npm run typecheck` | `tsc --noEmit`     |

## Structure

```
src/
  proxy.ts              Refreshes the Supabase session cookie on each request
  app/
    (admin)/            Gated layout, loading, error
      admin/            /admin, /admin/access, /admin/audit-log and placeholder routes
    sign-in/            Sign-in page and actions
    mfa/                Authenticator enrolment and step-up
    page.tsx            Redirects to /admin or /sign-in
    not-found.tsx
  components/
    shell/              Sidebar, header, breadcrumbs, page header, state messages, form fields
    ui/                 shadcn components
  config/               App identity and navigation
  hooks/
  lib/
    supabase/           Server client and cookie configuration
    admin-access.ts     Reads the caller's access state from the database
    admin-roles.ts      Role labels and validators
supabase/
  migrations/           Applied by hand to the development project
  rollbacks/            Kept out of migrations so nothing applies them by accident
  verification/         Read-only checks to run before and after each migration
```

## Database

Admin objects live in migrations in `supabase/migrations`:

- `20261012180000_admin_access_foundation.sql`: roles, status, `admin_users`, the audit log, and the `admin_*` functions
- `20261013230000_admin_student_separation.sql`: student-profile guard and the email lookup

Each migration has a rollback script and is applied once, manually, as the project owner role against the development project after running the verification queries. Do not apply a migration to any other project without reviewing it first.

## Documentation

- [`AI_AGENT_RULES.md`](./AI_AGENT_RULES.md): rules every contributor and AI agent must follow
- [`ARCHITECTURE.md`](./ARCHITECTURE.md): boundaries, routing, security model
- [`DESIGN_SYSTEM.md`](./DESIGN_SYSTEM.md): tokens, typography, components
