import type { AdminRole } from "@/config/navigation";
import type { AdminStatus } from "@/lib/admin-roles";

export type AuditState = { role: AdminRole | null; status: AdminStatus | null };

export type AuditEntry = {
  id: number;
  occurredAt: string;
  actorKind: "admin" | "operator";
  actorUserId: string | null;
  action: string;
  targetUserId: string;
  before: AuditState | null;
  after: AuditState | null;
  reason: string;
};

export type Person = { label: string; known: boolean };

export type AuditRow = {
  id: number;
  occurredAt: string;
  action: string;
  actor: Person | null;
  target: Person;
  before: AuditState | null;
  after: AuditState | null;
  reason: string;
};
