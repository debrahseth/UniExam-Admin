import type {
  Difficulty,
  QuestionDetail,
  QuestionOption,
  QuestionRow,
  QuestionStatus,
  ReviewState,
} from "./types";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

export function first(
  value: string | string[] | undefined,
): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export const STATE_LABELS: Record<ReviewState, string> = {
  imported: "Imported",
  draft: "Draft",
  submitted: "In review",
  approved: "Approved",
  rejected: "Rejected",
};

export const DIFFICULTY_LABELS: Record<Difficulty, string> = {
  easy: "Easy",
  medium: "Medium",
  hard: "Hard",
};

export function isReviewState(value: unknown): value is ReviewState {
  return (
    value === "imported" ||
    value === "draft" ||
    value === "submitted" ||
    value === "approved" ||
    value === "rejected"
  );
}

function isQuestionStatus(value: unknown): value is QuestionStatus {
  return value === "draft" || value === "published" || value === "retired";
}

function isDifficulty(value: unknown): value is Difficulty {
  return value === "easy" || value === "medium" || value === "hard";
}

function toOptions(value: unknown): QuestionOption[] | null {
  if (!Array.isArray(value)) return null;
  const options: QuestionOption[] = [];
  for (const item of value) {
    if (typeof item !== "object" || item === null) return null;
    const o = item as Record<string, unknown>;
    if (typeof o.id !== "string" || typeof o.text !== "string") return null;
    options.push({ id: o.id, text: o.text });
  }
  return options;
}

function optionalString(value: unknown): string | null | undefined {
  if (value === null || value === undefined) return null;
  return typeof value === "string" ? value : undefined;
}

export function toQuestionRow(row: unknown): QuestionRow | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;

  const topicTitle = optionalString(r.topic_title);
  const authorEmail = optionalString(r.author_email);

  if (
    typeof r.version_id !== "string" ||
    typeof r.question_id !== "string" ||
    typeof r.version !== "number" ||
    !isReviewState(r.review_state) ||
    !isQuestionStatus(r.question_status) ||
    typeof r.is_live !== "boolean" ||
    typeof r.course_code !== "string" ||
    typeof r.stem !== "string" ||
    typeof r.updated_at !== "string" ||
    topicTitle === undefined ||
    authorEmail === undefined ||
    (r.difficulty !== null && !isDifficulty(r.difficulty))
  ) {
    return null;
  }

  return {
    versionId: r.version_id,
    questionId: r.question_id,
    version: r.version,
    reviewState: r.review_state,
    questionStatus: r.question_status,
    isLive: r.is_live,
    courseCode: r.course_code,
    topicTitle,
    stem: r.stem,
    difficulty: r.difficulty as Difficulty | null,
    authorEmail,
    updatedAt: r.updated_at,
  };
}

export function toQuestionDetail(row: unknown): QuestionDetail | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;

  const options = toOptions(r.options);
  const topicId = optionalString(r.topic_id);
  const topicTitle = optionalString(r.topic_title);
  const correct = optionalString(r.correct_option_id);
  const explanation = optionalString(r.explanation);
  const authorEmail = optionalString(r.author_email);
  const reviewerEmail = optionalString(r.reviewer_email);
  const reviewNote = optionalString(r.review_note);
  const submittedAt = optionalString(r.submitted_at);
  const reviewedAt = optionalString(r.reviewed_at);

  if (
    typeof r.version_id !== "string" ||
    typeof r.question_id !== "string" ||
    typeof r.version !== "number" ||
    !isReviewState(r.review_state) ||
    !isQuestionStatus(r.question_status) ||
    typeof r.is_live !== "boolean" ||
    typeof r.course_id !== "string" ||
    typeof r.course_code !== "string" ||
    typeof r.stem !== "string" ||
    typeof r.is_mine !== "boolean" ||
    options === null ||
    topicId === undefined ||
    topicTitle === undefined ||
    correct === undefined ||
    explanation === undefined ||
    authorEmail === undefined ||
    reviewerEmail === undefined ||
    reviewNote === undefined ||
    submittedAt === undefined ||
    reviewedAt === undefined ||
    (r.difficulty !== null && !isDifficulty(r.difficulty))
  ) {
    return null;
  }

  return {
    versionId: r.version_id,
    questionId: r.question_id,
    version: r.version,
    reviewState: r.review_state,
    questionStatus: r.question_status,
    isLive: r.is_live,
    courseId: r.course_id,
    courseCode: r.course_code,
    topicId,
    topicTitle,
    difficulty: r.difficulty as Difficulty | null,
    stem: r.stem,
    options,
    correctOptionId: correct,
    explanation,
    authorEmail,
    reviewerEmail,
    reviewNote,
    submittedAt,
    reviewedAt,
    isMine: r.is_mine,
  };
}
