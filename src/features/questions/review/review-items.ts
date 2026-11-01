import { isReviewState } from "../helpers";
import type { ReviewState } from "../types";

export type ReviewItem = {
  questionId: string;
  versionId: string;
  version: number;
  reviewState: ReviewState;
};

export function toReviewItem(row: unknown): ReviewItem | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;

  if (
    typeof r.question_id !== "string" ||
    typeof r.version_id !== "string" ||
    typeof r.version !== "number" ||
    !Number.isInteger(r.version) ||
    !isReviewState(r.review_state)
  ) {
    return null;
  }

  return {
    questionId: r.question_id,
    versionId: r.version_id,
    version: r.version,
    reviewState: r.review_state,
  };
}
