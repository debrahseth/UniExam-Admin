"use server";

import { revalidatePath } from "next/cache";

import type { AdminRole } from "@/config/navigation";
import {
  isAdminRole,
  isAdminStatus,
  isAssignableRole,
  type AdminStatus,
} from "@/lib/admin-roles";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import type {
  ActionResult,
  FoundUser,
  LookupResult,
  ManageIntent,
} from "./types";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const GENERIC_ERROR = "The change could not be completed. Nothing was changed.";

const ERRORS: Record<string, string> = {
  not_authorized:
    "Your session no longer has permission to do this. Reload the page or sign in again.",
  invalid_reason: "Enter a reason of 10 to 500 characters.",
  target_not_found:
    "That account was not found, or its email has not been confirmed.",
  cannot_target_self: "You cannot change your own access.",
  role_not_assignable: "That role cannot be assigned here.",
  target_is_student:
    "This account has a student profile and cannot be an administrator.",
  invalid_state:
    "This account is not in a state that allows that change. Reload the page to see its current status.",
  cannot_modify_super_admin: "The Super Admin account cannot be changed here.",
};

function messageFor(message: string | undefined): string {
  const text = message ?? "";
  for (const key of Object.keys(ERRORS)) {
    if (text.includes(key)) return ERRORS[key];
  }
  return GENERIC_ERROR;
}

function text(value: FormDataEntryValue | null, max: number): string | null {
  return typeof value === "string" && value.length <= max ? value : null;
}

function readTarget(formData: FormData): string | null {
  const target = text(formData.get("target"), 36);
  return target && UUID.test(target) ? target : null;
}

function readReason(formData: FormData): string | null {
  const reason = text(formData.get("reason"), 2000)?.trim() ?? "";
  return reason.length >= 10 && reason.length <= 500 ? reason : null;
}

function fail(message: string): ActionResult {
  return { ok: false, message };
}

function toFoundUser(row: unknown): FoundUser | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;

  if (
    typeof r.user_id !== "string" ||
    typeof r.email !== "string" ||
    typeof r.email_confirmed !== "boolean" ||
    typeof r.is_student !== "boolean" ||
    typeof r.created_at !== "string"
  ) {
    return null;
  }
  if (r.access_role !== null && !isAdminRole(r.access_role)) return null;
  if (r.access_status !== null && !isAdminStatus(r.access_status)) return null;

  return {
    userId: r.user_id,
    email: r.email,
    emailConfirmed: r.email_confirmed,
    isStudent: r.is_student,
    accessRole: r.access_role as AdminRole | null,
    accessStatus: r.access_status as AdminStatus | null,
    createdAt: r.created_at,
    lastSignInAt:
      typeof r.last_sign_in_at === "string" ? r.last_sign_in_at : null,
  };
}

export async function findUser(formData: FormData): Promise<LookupResult> {
  const email = text(formData.get("email"), 254)?.trim() ?? "";
  if (email.length < 3) {
    return { ok: false, message: "Enter the email address of the account." };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("admin_find_user_by_email", {
    p_email: email,
  });
  if (error) return { ok: false, message: messageFor(error.message) };
  if (!Array.isArray(data) || data.length === 0)
    return { ok: true, user: null };

  const user = toFoundUser(data[0]);
  return user ? { ok: true, user } : { ok: false, message: GENERIC_ERROR };
}

export async function grantAdmin(formData: FormData): Promise<ActionResult> {
  const target = readTarget(formData);
  const role = formData.get("role");
  if (!target || !isAssignableRole(role)) return fail(GENERIC_ERROR);

  const reason = readReason(formData);
  if (!reason) return fail(ERRORS.invalid_reason);

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("admin_grant_role", {
    p_target: target,
    p_role: role,
    p_reason: reason,
  });
  if (error) return fail(messageFor(error.message));

  revalidatePath("/admin/access");
  return {
    ok: true,
    message:
      "Access granted. They will set up an authenticator the first time they sign in.",
  };
}

const INTENTS: readonly ManageIntent[] = [
  "change_role",
  "suspend",
  "reactivate",
  "revoke",
];

const SUCCESS: Record<ManageIntent, string> = {
  change_role: "Role changed.",
  suspend: "Access suspended.",
  reactivate: "Access reactivated.",
  revoke: "Access revoked.",
};

export async function manageAdmin(formData: FormData): Promise<ActionResult> {
  const intent = formData.get("intent");
  const target = readTarget(formData);
  if (!target || !INTENTS.includes(intent as ManageIntent)) {
    return fail(GENERIC_ERROR);
  }
  const action = intent as ManageIntent;

  const reason = readReason(formData);
  if (!reason) return fail(ERRORS.invalid_reason);

  const supabase = await createSupabaseServerClient();
  let error: { message: string } | null;

  if (action === "change_role") {
    const role = formData.get("role");
    if (!isAssignableRole(role)) return fail(GENERIC_ERROR);
    ({ error } = await supabase.rpc("admin_change_role", {
      p_target: target,
      p_new_role: role,
      p_reason: reason,
    }));
  } else {
    const fn =
      action === "suspend"
        ? "admin_suspend"
        : action === "reactivate"
          ? "admin_reactivate"
          : "admin_revoke";
    ({ error } = await supabase.rpc(fn, {
      p_target: target,
      p_reason: reason,
    }));
  }

  if (error) return fail(messageFor(error.message));

  revalidatePath("/admin/access");
  return { ok: true, message: SUCCESS[action] };
}
