# UniExam Admin

Administration workspace for [UniExam](https://github.com/debrahseth/UniExam), the KNUST examination simulation platform. This is a separate application from the student app. It will share the same Supabase project (auth and data) and has no database of its own.

## Status: Milestone 1A (UI foundation)

Built so far: design system, app shell, placeholder routes and system states.

Not built yet, and deliberately absent:

- Supabase connection, migrations and any data access
- Authentication and the Super Admin identity
- Role assignment, authorization checks and the audit log

These belong to Milestone 1B. Until then, the admin UI only renders when the preview flag is on, and no page reads or changes data.

## Stack

Next.js 16 (App Router), React 19, TypeScript (strict), Tailwind CSS v4, shadcn/ui (base-nova style, Base UI), lucide icons, Inter via `next/font`. Package manager: npm.

## Getting started

```bash
npm install
cp .env.example .env.local   # then set ADMIN_PREVIEW_ENABLED=true for local preview
npm run dev
```

Open `http://localhost:3000`. With the preview flag on, `/` redirects to `/admin`. With the flag off or missing, the app shows a closed page and every `/admin` route returns 404.

## Environment

| Variable                | Purpose                                                                                                         |
| ----------------------- | --------------------------------------------------------------------------------------------------------------- |
| `ADMIN_PREVIEW_ENABLED` | Server-only. Must be exactly `true` to render the admin UI. Leave unset or `false` in any deployed environment. |

Milestone 1A needs no secrets. Never put a service-role key in a `NEXT_PUBLIC_` variable.

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
  app/
    (admin)/            Admin route group: gated layout, loading, error
      admin/            /admin and placeholder routes
    page.tsx            Entry: redirect in preview, closed page otherwise
    not-found.tsx
  components/
    shell/              Sidebar, header, breadcrumbs, page header, state messages
    ui/                 shadcn components
  config/               App identity and navigation
  hooks/
  lib/
```

## Documentation

- [`AI_AGENT_RULES.md`](./AI_AGENT_RULES.md): rules every contributor and AI agent must follow
- [`ARCHITECTURE.md`](./ARCHITECTURE.md): boundaries, routing, security model
- [`DESIGN_SYSTEM.md`](./DESIGN_SYSTEM.md): tokens, typography, components
