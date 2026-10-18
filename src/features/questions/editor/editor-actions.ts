"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";

import { isUuid } from "../helpers";

export type SaveResult = { ok: false; message: string };

const GENERIC_ERROR = "The question could not be saved. Nothing was changed.";

const ERRORS: Record<string, string> = {
  not_authorized:
    "Your session no longer has permission to do this. Reload the page or sign in again.",
  not_author: "Only the author of this version can edit it.",
  target_not_found: "That question no longer exists.",
  invalid_stem:
    "The question text must be 1 to 2,000 characters and contain no control characters.",
  invalid_options:
    "Provide 2 to 6 options. Each must be 1 to 500 characters, on one line, and different from the others.",
  invalid_correct: "Choose which option is the correct answer.",
  invalid_difficulty: "Choose a difficulty.",
  invalid_explanation: "The explanation can be up to 4,000 characters.",
  invalid_course: "Choose an active course.",
  invalid_topic: "Choose a topic that belongs to the selected course.",
  topic_locked: "The topic of a published question can't be changed.",
  open_version_exists:
    "This question already has an unfinished version. Finish or discard it first.",
  question_retired:
    "This question is retired. Restore it before creating a new version.",
  invalid_state:
    "This version can no longer be edited. Reload the page to see its status.",
};

const ERROR_KEYS = Object.keys(ERRORS).sort((a, b) => b.length - a.length);

function messageFor(message: string | undefined): string {
  const text = message ?? "";
  for (const key of ERROR_KEYS) {
    if (text.includes(key)) return ERRORS[key];
  }
  return GENERIC_ERROR;
}

function fail(message: string): SaveResult {
  return { ok: false, message };
}

const MODES = ["create", "edit", "new_version"] as const;
type Mode = (typeof MODES)[number];

const DIFFICULTIES: readonly string[] = ["easy", "medium", "hard"];
const LETTERS: readonly string[] = ["a", "b", "c", "d", "e", "f"];

function readUuid(value: FormDataEntryValue | null): string | null {
  return typeof value === "string" && isUuid(value) ? value : null;
}

function readText(
  value: FormDataEntryValue | null,
  max: number,
): string | null {
  return typeof value === "string" && value.length <= max ? value : null;
}

export async function saveQuestion(formData: FormData): Promise<SaveResult> {
  const mode = formData.get("mode");
  if (typeof mode !== "string" || !MODES.includes(mode as Mode)) {
    return fail(GENERIC_ERROR);
  }

  const stem = readText(formData.get("stem"), 10000);
  const explanation = readText(formData.get("explanation"), 20000);
  const correct = formData.get("correct");
  const difficulty = formData.get("difficulty");
  const rawOptions = formData.getAll("option");

  if (
    stem === null ||
    explanation === null ||
    typeof correct !== "string" ||
    typeof difficulty !== "string" ||
    rawOptions.length > 10 ||
    rawOptions.some((o) => typeof o !== "string" || o.length > 5000)
  ) {
    return fail(GENERIC_ERROR);
  }
  if (!LETTERS.includes(correct)) return fail(ERRORS.invalid_correct);
  if (!DIFFICULTIES.includes(difficulty))
    return fail(ERRORS.invalid_difficulty);

  const options = rawOptions as string[];
  const supabase = await createSupabaseServerClient();
  let versionId: string | null = null;

  if (mode === "create") {
    const course = readUuid(formData.get("course"));
    const topic = readUuid(formData.get("topic"));
    if (!course) return fail(ERRORS.invalid_course);
    if (!topic) return fail(ERRORS.invalid_topic);

    const { data, error } = await supabase.rpc("admin_question_create_draft", {
      p_course_id: course,
      p_topic_id: topic,
      p_stem: stem,
      p_options: options,
      p_correct: correct,
      p_explanation: explanation,
      p_difficulty: difficulty,
    });
    if (error) return fail(messageFor(error.message));
    versionId = typeof data === "string" ? data : null;
  } else if (mode === "new_version") {
    const question = readUuid(formData.get("question"));
    if (!question) return fail(GENERIC_ERROR);

    const { data, error } = await supabase.rpc(
      "admin_question_create_version",
      {
        p_question_id: question,
        p_stem: stem,
        p_options: options,
        p_correct: correct,
        p_explanation: explanation,
        p_difficulty: difficulty,
      },
    );
    if (error) return fail(messageFor(error.message));
    versionId = typeof data === "string" ? data : null;
  } else {
    const version = readUuid(formData.get("version"));
    const topic = readUuid(formData.get("topic"));
    if (!version) return fail(GENERIC_ERROR);
    if (!topic) return fail(ERRORS.invalid_topic);

    const { error } = await supabase.rpc("admin_question_update_draft", {
      p_version_id: version,
      p_topic_id: topic,
      p_stem: stem,
      p_options: options,
      p_correct: correct,
      p_explanation: explanation,
      p_difficulty: difficulty,
    });
    if (error) return fail(messageFor(error.message));
    versionId = version;
  }

  revalidatePath("/admin/questions", "layout");

  if (!versionId || !isUuid(versionId)) {
    redirect("/admin/questions");
  }
  redirect(`/admin/questions/${versionId}`);
}
