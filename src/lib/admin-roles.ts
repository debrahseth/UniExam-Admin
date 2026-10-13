import type { AdminRole } from "@/config/navigation";

export type AdminStatus = "active" | "suspended" | "revoked";

export const ROLE_LABELS: Record<AdminRole, string> = {
  super_admin: "Super Admin",
  academic_admin: "Academic admin",
  question_reviewer: "Question reviewer",
  support_admin: "Support admin",
  analytics_viewer: "Analytics viewer",
};

export const ASSIGNABLE_ROLES = [
  "academic_admin",
  "question_reviewer",
  "support_admin",
  "analytics_viewer",
] as const;

export type AssignableRole = (typeof ASSIGNABLE_ROLES)[number];

const ALL_ROLES = Object.keys(ROLE_LABELS);

export function isAdminRole(value: unknown): value is AdminRole {
  return typeof value === "string" && ALL_ROLES.includes(value);
}

export function isAssignableRole(value: unknown): value is AssignableRole {
  return (
    typeof value === "string" &&
    (ASSIGNABLE_ROLES as readonly string[]).includes(value)
  );
}

export function isAdminStatus(value: unknown): value is AdminStatus {
  return value === "active" || value === "suspended" || value === "revoked";
}
