"use server";

import { redirect } from "next/navigation";

import { readAccess } from "@/lib/admin-access";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type CodeState = { error: string | null };

export type EnrollmentStart =
  | { status: "idle" }
  | { status: "ready"; factorId: string; qrCode: string; secret: string }
  | { status: "error"; message: string };

const CODE_ERROR =
  "That code is incorrect or has expired. Check your authenticator app and try again.";
const RATE_LIMIT_ERROR = "Too many attempts. Wait a few minutes and try again.";
const SETUP_ERROR =
  "Authenticator setup is not available right now. Try again.";

function parseCode(value: FormDataEntryValue | null): string | null {
  if (typeof value !== "string") return null;
  const code = value.replace(/\s+/g, "");
  return /^\d{6}$/.test(code) ? code : null;
}

export async function startEnrollment(): Promise<EnrollmentStart> {
  const supabase = await createSupabaseServerClient();

  const access = await readAccess(supabase);
  if (access.state !== "mfa_enrollment_required") {
    return { status: "error", message: SETUP_ERROR };
  }

  const { data: factors, error: listError } =
    await supabase.auth.mfa.listFactors();
  if (listError || !factors) return { status: "error", message: SETUP_ERROR };

  for (const factor of factors.all) {
    if (factor.factor_type === "totp" && factor.status === "unverified") {
      await supabase.auth.mfa.unenroll({ factorId: factor.id });
    }
  }

  const { data, error } = await supabase.auth.mfa.enroll({
    factorType: "totp",
    friendlyName: "UniExam Admin",
    issuer: "UniExam Admin",
  });
  if (error || !data) return { status: "error", message: SETUP_ERROR };

  return {
    status: "ready",
    factorId: data.id,
    qrCode: data.totp.qr_code,
    secret: data.totp.secret,
  };
}

export async function verifyEnrollment(
  _previous: CodeState,
  formData: FormData,
): Promise<CodeState> {
  const code = parseCode(formData.get("code"));
  const factorId = formData.get("factorId");
  if (!code || typeof factorId !== "string" || factorId.length > 64) {
    return { error: CODE_ERROR };
  }

  const supabase = await createSupabaseServerClient();

  const access = await readAccess(supabase);
  if (access.state !== "mfa_enrollment_required") {
    return { error: SETUP_ERROR };
  }

  const { data: factors, error: listError } =
    await supabase.auth.mfa.listFactors();
  const factor = factors?.all.find(
    (f) =>
      f.id === factorId &&
      f.factor_type === "totp" &&
      f.status === "unverified",
  );
  if (listError || !factor) {
    return {
      error: "This setup has expired. Choose Start over and scan the new code.",
    };
  }

  const { error } = await supabase.auth.mfa.challengeAndVerify({
    factorId,
    code,
  });
  if (error) {
    return { error: error.status === 429 ? RATE_LIMIT_ERROR : CODE_ERROR };
  }

  redirect("/admin");
}

export async function verifyStepUp(
  _previous: CodeState,
  formData: FormData,
): Promise<CodeState> {
  const code = parseCode(formData.get("code"));
  if (!code) return { error: CODE_ERROR };

  const supabase = await createSupabaseServerClient();

  const access = await readAccess(supabase);
  if (access.state === "active") redirect("/admin");
  if (access.state !== "mfa_step_up_required") redirect("/sign-in");

  const { data: factors, error: listError } =
    await supabase.auth.mfa.listFactors();
  const factor = factors?.totp[0];
  if (listError || !factor) return { error: SETUP_ERROR };

  const { error } = await supabase.auth.mfa.challengeAndVerify({
    factorId: factor.id,
    code,
  });
  if (error) {
    return { error: error.status === 429 ? RATE_LIMIT_ERROR : CODE_ERROR };
  }

  redirect("/admin");
}
