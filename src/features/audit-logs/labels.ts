import { ROLE_LABELS } from "@/lib/admin-roles";

import type { AuditState } from "./types";

const ACTION_LABELS: Record<string, string> = {
  "admin.granted": "Access granted",
  "admin.role_changed": "Role changed",
  "admin.suspended": "Access suspended",
  "admin.reactivated": "Access reactivated",
  "admin.revoked": "Access revoked",
  "super_admin.bootstrapped": "Super Admin provisioned",
  "super_admin.replaced": "Super Admin replaced",
};

export function actionLabel(action: string): string {
  return ACTION_LABELS[action] ?? action;
}

export function describeState(state: AuditState | null): string {
  if (!state) return "None";
  const role = state.role ? ROLE_LABELS[state.role] : null;
  return [role, state.status].filter(Boolean).join(" · ");
}

export function shortId(id: string): string {
  return `${id.slice(0, 8)}…`;
}
