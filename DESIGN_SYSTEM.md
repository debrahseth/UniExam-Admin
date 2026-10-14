# Design system

Source of truth: `src/app/globals.css`. Components come from shadcn (base-nova style, Base UI) in `src/components/ui`.

## Principles

- Calm and functional. This is a working tool, not a marketing site.
- Colour carries meaning. Green is the brand and primary action; status colours are reserved for status.
- Never rely on colour alone. Pair status colour with text or an icon.
- Admin status is always shown as a text badge (Active, Suspended, Revoked), never as colour alone.
- Use tokens, never raw hex values, in components.

## Colour tokens

Defined as CSS variables on `:root` and `.dark`, and mapped to Tailwind via `@theme inline`, so they work as `bg-primary`, `text-muted-foreground`, and so on.

| Group    | Tokens                                                                                                 |
| -------- | ------------------------------------------------------------------------------------------------------ |
| Surfaces | `background`, `foreground`, `card`, `popover` (each with `-foreground`)                                |
| Actions  | `primary`, `secondary`, `accent`, `muted` (each with `-foreground`)                                    |
| Danger   | `destructive`, `destructive-foreground`, `destructive-muted`, `destructive-muted-foreground`           |
| Status   | `success`, `warning`, `info`, each with `-foreground`, `-muted`, `-muted-foreground`                   |
| Lines    | `border`, `input`, `ring`                                                                              |
| Sidebar  | `sidebar`, `sidebar-foreground`, `sidebar-primary`, `sidebar-accent`, `sidebar-border`, `sidebar-ring` |

Status pattern: solid (`success`) with text on solid (`success-foreground`), or soft surface (`success-muted`) with text on soft surface (`success-muted-foreground`).

Contrast ratios have not been measured yet. Check them before the design is considered final.

## Typography

Font: Inter, loaded with `next/font` and exposed as `--font-inter`.

| Utility              | Use                              |
| -------------------- | -------------------------------- |
| `type-page-title`    | One per page, via `PageHeader`   |
| `type-section-title` | Section headings, state messages |
| `type-card-title`    | Card headings                    |
| `type-body`          | Default body copy                |
| `type-description`   | Supporting text under titles     |
| `type-label`         | Form labels                      |
| `type-table`         | Table cells                      |
| `type-helper`        | Hints, captions                  |
| `type-meta`          | Small emphasised metadata        |

## Shape and spacing

Base radius `--radius: 0.5rem`, with `rounded-sm`, `md`, `lg` and `xl` derived from it. Use Tailwind's spacing scale. Page content padding is `p-4` on small screens and `p-6` from `md`.

## Components in use

`avatar`, `badge`, `breadcrumb`, `button`, `card`, `dialog`, `dropdown-menu`, `input`, `label`, `separator`, `sheet`, `sidebar`, `skeleton`, `table`, `tooltip`.

shadcn's `select` and `textarea` are not installed. `NativeSelect` and `TextArea` in `src/components/shell/form-fields.tsx` match the `Input` styling and keep native keyboard and screen-reader behaviour.

Project components in `src/components/shell`:

- `PageHeader`: title, description, optional actions
- `PlaceholderPage`: "Not implemented" page for routes without features yet
- `StateMessage`: centred message for not-found, error, forbidden and closed states
- `ForbiddenState`: access-denied message, shown by pages restricted to a role (cosmetic only: the database enforces access)

Base UI uses a `render` prop where Radix-based shadcn uses `asChild`. For links styled as buttons, use `buttonVariants()` on a `Link`.

## Motion

`tw-animate-css` is imported for component transitions. A global `prefers-reduced-motion` rule shortens animations and transitions to near zero.

## Focus

All elements get a visible outline via `outline-ring`. Do not remove outlines without providing an equivalent focus style.

## Dark mode

Dark tokens exist, but nothing switches them on yet. Enabling it needs `next-themes` and `suppressHydrationWarning` on `<html>`. Not part of Milestone 1A.

## Dates and times

Use `formatUtc()` from `src/lib/format.ts`. It uses a fixed locale and the UTC time zone so server and browser render identical text, and labels the result UTC.

## Error copy

Say what happened, what it means, and what the user can do. Never show raw error messages, SQL or stack traces. A reference code (digest) is fine.
