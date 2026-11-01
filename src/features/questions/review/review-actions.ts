"use server";

import { getAdminContext } from "@/lib/admin-access";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { isUuid, toQuestionDetail } from "../helpers";
import { toHistoryEntry, type HistoryEntry } from "../search";
import type { QuestionDetail } from "../types";
import { questionRoleOf } from "./filters";

export type ReviewQuestionResult =
  | { ok: true; detail: QuestionDetail; history: HistoryEntry[] }
  | { ok: false; message: string };

const GENERIC = "The question could not be loaded.";
const NOT_ALLOWED =
  "Your session no longer has permission to view this. Reload the page or sign in again.";

function fail(message: string): ReviewQuestionResult {
  return { ok: false, message };
}

export async function loadReviewQuestion(
  versionId: string,
  questionId: string,
): Promise<ReviewQuestionResult> {
  if (!isUuid(versionId) || !isUuid(questionId)) return fail(GENERIC);

  const { access } = await getAdminContext();
  if (access.state !== "active" || !questionRoleOf(access.role)) {
    return fail(NOT_ALLOWED);
  }

  const supabase = await createSupabaseServerClient();
  const [detailResult, historyResult] = await Promise.all([
    supabase.rpc("admin_question_get", { p_version_id: versionId }),
    supabase.rpc("admin_question_history", { p_question_id: questionId }),
  ]);

  if (detailResult.error) {
    return fail(
      detailResult.error.message.includes("not_authorized")
        ? NOT_ALLOWED
        : GENERIC,
    );
  }
  if (!Array.isArray(detailResult.data) || detailResult.data.length === 0) {
    return fail("This question version no longer exists.");
  }

  const detail = toQuestionDetail(detailResult.data[0]);
  if (!detail || detail.questionId !== questionId) return fail(GENERIC);

  const history =
    !historyResult.error && Array.isArray(historyResult.data)
      ? historyResult.data
          .map(toHistoryEntry)
          .filter((e): e is HistoryEntry => e !== null)
      : [];

  return { ok: true, detail, history };
}
