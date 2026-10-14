"use server";

import { redirect } from "next/navigation";

import { readAccess } from "@/lib/admin-access";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type SignInState = { error: string | null };

const GENERIC_ERROR =
  "Email or password is incorrect, or this account cannot use UniExam Admin.";
const RATE_LIMIT_ERROR = "Too many attempts. Wait a few minutes and try again.";

export async function signIn(
  _previous: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const email = formData.get("email");
  const password = formData.get("password");

  if (
    typeof email !== "string" ||
    typeof password !== "string" ||
    email.length === 0 ||
    email.length > 254 ||
    password.length === 0 ||
    password.length > 1024
  ) {
    return { error: GENERIC_ERROR };
  }

  const supabase = await createSupabaseServerClient();

  const { error } = await supabase.auth.signInWithPassword({
    email: email.trim(),
    password,
  });
  if (error) {
    return { error: error.status === 429 ? RATE_LIMIT_ERROR : GENERIC_ERROR };
  }

  const access = await readAccess(supabase);
  if (access.state === "none" || access.state === "suspended") {
    await supabase.auth.signOut();
    return { error: GENERIC_ERROR };
  }

  if (access.state === "mfa_enrollment_required") redirect("/mfa/enroll");
  if (access.state === "mfa_step_up_required") redirect("/mfa/verify");
  redirect("/admin");
}

export async function signOut(): Promise<void> {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  redirect("/sign-in");
}
