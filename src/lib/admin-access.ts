import "server-only";

import type { AdminRole } from "@/config/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type AdminAccess =
  | { state: "active"; role: AdminRole }
  | { state: "none" }
  | { state: "suspended" }
  | { state: "mfa_enrollment_required" }
  | { state: "mfa_step_up_required" };

export type AdminContext = { access: AdminAccess; email: string | null };

type SupabaseServerClient = Awaited<
  ReturnType<typeof createSupabaseServerClient>
>;

const ROLES: readonly AdminRole[] = [
  "super_admin",
  "academic_admin",
  "question_reviewer",
  "support_admin",
  "analytics_viewer",
];

const NON_ACTIVE_STATES = [
  "none",
  "suspended",
  "mfa_enrollment_required",
  "mfa_step_up_required",
] as const;

const NO_ACCESS: AdminAccess = { state: "none" };

export async function readContext(
  supabase: SupabaseServerClient,
): Promise<AdminContext> {
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return { access: NO_ACCESS, email: null };

  const email = userData.user.email ?? null;

  const { data, error } = await supabase.rpc("admin_get_my_access");
  if (error || !Array.isArray(data) || data.length !== 1) {
    return { access: NO_ACCESS, email };
  }

  const row: unknown = data[0];
  if (typeof row !== "object" || row === null) {
    return { access: NO_ACCESS, email };
  }

  const { state, role } = row as { state?: unknown; role?: unknown };

  if (state === "active") {
    const valid =
      typeof role === "string" && (ROLES as readonly string[]).includes(role);
    return {
      access: valid ? { state: "active", role: role as AdminRole } : NO_ACCESS,
      email,
    };
  }

  const match = NON_ACTIVE_STATES.find((s) => s === state);
  return { access: match ? { state: match } : NO_ACCESS, email };
}

export async function readAccess(
  supabase: SupabaseServerClient,
): Promise<AdminAccess> {
  return (await readContext(supabase)).access;
}

export async function getMyAccess(): Promise<AdminAccess> {
  return readAccess(await createSupabaseServerClient());
}

export async function getAdminContext(): Promise<AdminContext> {
  return readContext(await createSupabaseServerClient());
}
