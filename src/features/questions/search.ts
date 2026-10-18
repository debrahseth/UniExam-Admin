import type { AdminRole } from "@/config/navigation";

import { isReviewState } from "./helpers";
import type { Difficulty, QuestionStatus, ReviewState } from "./types";

export type ListView = "all" | "needs_review" | "mine" | "live" | "retired";

export type ListRole = Extract<
  AdminRole,
  "super_admin" | "academic_admin" | "question_reviewer"
>;

const VIEWS: readonly ListView[] = [
  "all",
  "needs_review",
  "mine",
  "live",
  "retired",
];

export function isListView(value: unknown): value is ListView {
  return (
    typeof value === "string" && (VIEWS as readonly string[]).includes(value)
  );
}

export const VIEW_LABELS: Record<ListView, string> = {
  all: "All",
  needs_review: "Waiting for review",
  mine: "My work",
  live: "Live",
  retired: "Retired",
};

export function listRoleOf(role: AdminRole): ListRole | null {
  return role === "super_admin" ||
    role === "academic_admin" ||
    role === "question_reviewer"
    ? role
    : null;
}

export function viewsFor(role: ListRole): ListView[] {
  const views: ListView[] = [];
  if (role === "super_admin" || role === "question_reviewer") {
    views.push("needs_review");
  }
  if (role === "super_admin" || role === "academic_admin") views.push("mine");
  views.push("all", "live", "retired");
  return views;
}

export function defaultViewFor(role: ListRole): ListView {
  if (role === "question_reviewer") return "needs_review";
  if (role === "academic_admin") return "mine";
  return "all";
}

export type OpenState = "draft" | "submitted" | "rejected";

export type ListItem = {
  questionId: string;
  courseId: string;
  courseCode: string;
  topicId: string | null;
  topicTitle: string | null;
  questionStatus: QuestionStatus;
  stem: string;
  difficulty: Difficulty | null;
  currentVersionId: string;
  currentVersion: number;
  currentIsImported: boolean;
  liveVersionId: string | null;
  liveVersion: number | null;
  openVersionId: string | null;
  openVersion: number | null;
  openState: OpenState | null;
  openAuthorEmail: string | null;
  openSubmittedAt: string | null;
  isLive: boolean;
  isRetired: boolean;
  needsReview: boolean;
  isMine: boolean;
  sortAt: string;
};

export type ListCounts = Record<ListView, number>;

export type HistoryEntry = {
  versionId: string;
  version: number;
  reviewState: ReviewState;
  isLive: boolean;
  wasPublished: boolean;
  authorEmail: string | null;
  updatedAt: string;
};

function isQuestionStatus(value: unknown): value is QuestionStatus {
  return value === "draft" || value === "published" || value === "retired";
}

function isDifficulty(value: unknown): value is Difficulty {
  return value === "easy" || value === "medium" || value === "hard";
}

function isOpenState(value: unknown): value is OpenState {
  return value === "draft" || value === "submitted" || value === "rejected";
}

function optText(value: unknown): string | null | undefined {
  if (value === null || value === undefined) return null;
  return typeof value === "string" ? value : undefined;
}

function optInt(value: unknown): number | null | undefined {
  if (value === null || value === undefined) return null;
  return typeof value === "number" && Number.isInteger(value)
    ? value
    : undefined;
}

export function toListItem(row: unknown): ListItem | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;

  const topicId = optText(r.topic_id);
  const topicTitle = optText(r.topic_title);
  const liveVersionId = optText(r.live_version_id);
  const liveVersion = optInt(r.live_version);
  const openVersionId = optText(r.open_version_id);
  const openVersion = optInt(r.open_version);
  const openAuthorEmail = optText(r.open_author_email);
  const openSubmittedAt = optText(r.open_submitted_at);

  if (
    typeof r.question_id !== "string" ||
    typeof r.course_id !== "string" ||
    typeof r.course_code !== "string" ||
    !isQuestionStatus(r.question_status) ||
    typeof r.stem !== "string" ||
    typeof r.current_version_id !== "string" ||
    typeof r.current_version !== "number" ||
    typeof r.current_is_imported !== "boolean" ||
    typeof r.is_live !== "boolean" ||
    typeof r.is_retired !== "boolean" ||
    typeof r.needs_review !== "boolean" ||
    typeof r.is_mine !== "boolean" ||
    typeof r.sort_at !== "string" ||
    topicId === undefined ||
    topicTitle === undefined ||
    liveVersionId === undefined ||
    liveVersion === undefined ||
    openVersionId === undefined ||
    openVersion === undefined ||
    openAuthorEmail === undefined ||
    openSubmittedAt === undefined ||
    (r.difficulty !== null && !isDifficulty(r.difficulty)) ||
    (r.open_state !== null && !isOpenState(r.open_state))
  ) {
    return null;
  }

  return {
    questionId: r.question_id,
    courseId: r.course_id,
    courseCode: r.course_code,
    topicId,
    topicTitle,
    questionStatus: r.question_status,
    stem: r.stem,
    difficulty: r.difficulty as Difficulty | null,
    currentVersionId: r.current_version_id,
    currentVersion: r.current_version,
    currentIsImported: r.current_is_imported,
    liveVersionId,
    liveVersion,
    openVersionId,
    openVersion,
    openState: r.open_state as OpenState | null,
    openAuthorEmail,
    openSubmittedAt,
    isLive: r.is_live,
    isRetired: r.is_retired,
    needsReview: r.needs_review,
    isMine: r.is_mine,
    sortAt: r.sort_at,
  };
}

function toCount(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && /^\d{1,15}$/.test(value))
    return Number(value);
  return null;
}

export function toCounts(row: unknown): ListCounts | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  const all = toCount(r.all_count);
  const review = toCount(r.needs_review_count);
  const mine = toCount(r.mine_count);
  const live = toCount(r.live_count);
  const retired = toCount(r.retired_count);
  if (
    all === null ||
    review === null ||
    mine === null ||
    live === null ||
    retired === null
  ) {
    return null;
  }
  return { all, needs_review: review, mine, live, retired };
}

export function toHistoryEntry(row: unknown): HistoryEntry | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  const authorEmail = optText(r.author_email);
  if (
    typeof r.version_id !== "string" ||
    typeof r.version !== "number" ||
    !isReviewState(r.review_state) ||
    typeof r.is_live !== "boolean" ||
    typeof r.was_published !== "boolean" ||
    typeof r.updated_at !== "string" ||
    authorEmail === undefined
  ) {
    return null;
  }
  return {
    versionId: r.version_id,
    version: r.version,
    reviewState: r.review_state,
    isLive: r.is_live,
    wasPublished: r.was_published,
    authorEmail,
    updatedAt: r.updated_at,
  };
}

export const CURSOR_AT =
  /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}(:?\d{2})?)$/;

export type ListCursor = { at: string; id: string; dir: "next" | "prev" };

export type ListParams = {
  view?: ListView;
  q?: string;
  course?: string;
  topic?: string;
  difficulty?: string;
  cursor?: ListCursor;
};

export function buildListHref(p: ListParams): string {
  const query = new URLSearchParams();
  if (p.view) query.set("view", p.view);
  if (p.q) query.set("q", p.q);
  if (p.course) query.set("course", p.course);
  if (p.topic) query.set("topic", p.topic);
  if (p.difficulty) query.set("difficulty", p.difficulty);
  if (p.cursor) {
    query.set("at", p.cursor.at);
    query.set("id", p.cursor.id);
    if (p.cursor.dir === "prev") query.set("dir", "prev");
  }
  const text = query.toString();
  return text ? `/admin/questions?${text}` : "/admin/questions";
}
