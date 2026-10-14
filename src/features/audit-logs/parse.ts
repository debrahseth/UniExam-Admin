import { isAdminRole, isAdminStatus } from "@/lib/admin-roles";

import type { AuditEntry, AuditState } from "./types";

function parseState(value: unknown): AuditState | null {
  if (typeof value !== "object" || value === null) return null;
  const v = value as Record<string, unknown>;
  const role = isAdminRole(v.role) ? v.role : null;
  const status = isAdminStatus(v.status) ? v.status : null;
  return role || status ? { role, status } : null;
}

function parseId(value: unknown): number | null {
  if (typeof value === "number" && Number.isSafeInteger(value)) return value;
  if (typeof value === "string" && /^\d{1,15}$/.test(value)) {
    return Number(value);
  }
  return null;
}

export function toEntry(row: unknown): AuditEntry | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  const id = parseId(r.id);

  if (
    id === null ||
    typeof r.occurred_at !== "string" ||
    (r.actor_kind !== "admin" && r.actor_kind !== "operator") ||
    typeof r.action !== "string" ||
    typeof r.target_user_id !== "string" ||
    typeof r.reason !== "string" ||
    (r.actor_user_id !== null && typeof r.actor_user_id !== "string")
  ) {
    return null;
  }

  return {
    id,
    occurredAt: r.occurred_at,
    actorKind: r.actor_kind,
    actorUserId: r.actor_user_id as string | null,
    action: r.action,
    targetUserId: r.target_user_id,
    before: parseState(r.before_state),
    after: parseState(r.after_state),
    reason: r.reason,
  };
}

export function parseBefore(
  value: string | string[] | undefined,
): number | null {
  const raw = Array.isArray(value) ? value[0] : value;
  return raw && /^\d{1,15}$/.test(raw) ? Number(raw) : null;
}
