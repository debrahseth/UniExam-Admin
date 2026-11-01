import type { QuestionDetail, QuestionIntent } from "../types";
import type { QuestionRole } from "./filters";

function isAuthorRole(role: QuestionRole): boolean {
  return role === "super_admin" || role === "academic_admin";
}

function isReviewerRole(role: QuestionRole): boolean {
  return role === "super_admin" || role === "question_reviewer";
}

export function allowedIntents(
  role: QuestionRole,
  d: QuestionDetail,
): QuestionIntent[] {
  const list: QuestionIntent[] = [];
  if (d.isMine && isAuthorRole(role) && d.reviewState === "draft") {
    list.push("submit");
  }
  if (
    d.isMine &&
    isAuthorRole(role) &&
    (d.reviewState === "draft" || d.reviewState === "rejected")
  ) {
    list.push("discard");
  }
  if (isReviewerRole(role) && d.reviewState === "submitted" && !d.isMine) {
    list.push("approve", "reject");
  }
  if (isReviewerRole(role) && d.questionStatus === "published" && d.isLive) {
    list.push("retire");
  }
  if (isReviewerRole(role) && d.questionStatus === "retired") {
    list.push("restore");
  }
  return list;
}

export function canEdit(role: QuestionRole, d: QuestionDetail): boolean {
  return (
    d.isMine &&
    isAuthorRole(role) &&
    (d.reviewState === "draft" || d.reviewState === "rejected")
  );
}

export function canStartNewVersion(
  role: QuestionRole,
  d: QuestionDetail,
): boolean {
  return isAuthorRole(role) && d.isLive;
}

export function mustBeReviewedByOthers(
  role: QuestionRole,
  d: QuestionDetail,
): boolean {
  return isReviewerRole(role) && d.isMine && d.reviewState === "submitted";
}
