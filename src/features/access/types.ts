import type { AdminRole } from "@/config/navigation";
import type { AdminStatus } from "@/lib/admin-roles";

export type AdminRow = {
  userId: string;
  email: string;
  role: AdminRole;
  status: AdminStatus;
  createdAt: string;
};

export type FoundUser = {
  userId: string;
  email: string;
  emailConfirmed: boolean;
  isStudent: boolean;
  accessRole: AdminRole | null;
  accessStatus: AdminStatus | null;
  createdAt: string;
  lastSignInAt: string | null;
};

export type ActionResult =
  | { ok: true; message: string }
  | { ok: false; message: string };

export type LookupResult =
  | { ok: true; user: FoundUser | null }
  | { ok: false; message: string };

export type ManageIntent = "change_role" | "suspend" | "reactivate" | "revoke";
