"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";

import { isUuid } from "./helpers";
import type { ActionResult, QuestionIntent } from "./types";

const GENERIC_ERROR = "The change could not be completed. Nothing was changed.";

const ERRORS: Record<string, string> = {
  not_authorized:
    "Your session no longer has permission to do this. Reload the page or sign in again.",
  not_author: "Only the author of this version can do that.",
  invalid_reason: "Enter a reason of 10 to 500 characters.",
  target_not_found: "That question version no longer exists.",
  invalid_state:
    "This question isn't in a state that allows that. Reload the page to see its current status.",
  cannot_review_own:
    "You wrote this version, so someone else has to review it.",
  question_retired: "This question is retired. Restore it first.",
};

const ERROR_KEYS = Object.keys(ERRORS).sort((a, b) => b.length - a.length);

function messageFor(message: string | undefined): string {
  const text = message ?? "";
  for (const key of ERROR_KEYS) {
    if (text.includes(key)) return ERRORS[key];
  }
  return GENERIC_ERROR;
}

function fail(message: string): ActionResult {
  return { ok: false, message };
}

function readUuid(value: FormDataEntryValue | null): string | null {
  return typeof value === "string" && isUuid(value) ? value : null;
}

function readReason(value: FormDataEntryValue | null): string | null {
  const reason = typeof value === "string" ? value.trim() : "";
  return reason.length >= 10 && reason.length <= 500 ? reason : null;
}

const INTENTS: readonly QuestionIntent[] = [
  "submit",
  "discard",
  "approve",
  "reject",
  "retire",
  "restore",
];

const SUCCESS: Record<Exclude<QuestionIntent, "discard">, string> = {
  submit: "Submitted for review.",
  approve: "Approved and published.",
  reject: "Rejected. The author can see your reason.",
  retire: "Question retired.",
  restore: "Question restored.",
};

export async function runQuestionAction(
  formData: FormData,
): Promise<ActionResult> {
  const intent = formData.get("intent");
  if (
    typeof intent !== "string" ||
    !INTENTS.includes(intent as QuestionIntent)
  ) {
    return fail(GENERIC_ERROR);
  }
  const action = intent as QuestionIntent;

  const needsReason =
    action === "reject" || action === "retire" || action === "restore";
  const needsQuestion = action === "retire" || action === "restore";

  const version = readUuid(formData.get("version"));
  const question = readUuid(formData.get("question"));
  if (needsQuestion ? !question : !version) return fail(GENERIC_ERROR);

  const reason = needsReason ? readReason(formData.get("reason")) : null;
  if (needsReason && !reason) return fail(ERRORS.invalid_reason);

  const supabase = await createSupabaseServerClient();
  let error: { message: string } | null = null;

  switch (action) {
    case "submit":
      ({ error } = await supabase.rpc("admin_question_submit", {
        p_version_id: version,
      }));
      break;
    case "discard":
      ({ error } = await supabase.rpc("admin_question_discard_draft", {
        p_version_id: version,
      }));
      break;
    case "approve":
      ({ error } = await supabase.rpc("admin_question_approve", {
        p_version_id: version,
      }));
      break;
    case "reject":
      ({ error } = await supabase.rpc("admin_question_reject", {
        p_version_id: version,
        p_reason: reason,
      }));
      break;
    case "retire":
      ({ error } = await supabase.rpc("admin_question_retire", {
        p_question_id: question,
        p_reason: reason,
      }));
      break;
    case "restore":
      ({ error } = await supabase.rpc("admin_question_restore", {
        p_question_id: question,
        p_reason: reason,
      }));
      break;
  }

  if (error) return fail(messageFor(error.message));

  revalidatePath("/admin/questions", "layout");

  if (action === "discard") redirect("/admin/questions");

  return { ok: true, message: SUCCESS[action] };
}
