import type { AdminRole } from "@/config/navigation";

export type ReviewState =
  | "imported"
  | "draft"
  | "submitted"
  | "approved"
  | "rejected";

export type QuestionStatus = "draft" | "published" | "retired";
export type Difficulty = "easy" | "medium" | "hard";

export type QuestionIntent =
  | "submit"
  | "discard"
  | "approve"
  | "reject"
  | "retire"
  | "restore";

export type QuestionOption = { id: string; text: string };

export type QuestionRow = {
  versionId: string;
  questionId: string;
  version: number;
  reviewState: ReviewState;
  questionStatus: QuestionStatus;
  isLive: boolean;
  courseCode: string;
  topicTitle: string | null;
  stem: string;
  difficulty: Difficulty | null;
  authorEmail: string | null;
  updatedAt: string;
};

export type QuestionDetail = {
  versionId: string;
  questionId: string;
  version: number;
  reviewState: ReviewState;
  questionStatus: QuestionStatus;
  isLive: boolean;
  courseId: string;
  courseCode: string;
  topicId: string | null;
  topicTitle: string | null;
  difficulty: Difficulty | null;
  stem: string;
  options: QuestionOption[];
  correctOptionId: string | null;
  explanation: string | null;
  authorEmail: string | null;
  reviewerEmail: string | null;
  reviewNote: string | null;
  submittedAt: string | null;
  reviewedAt: string | null;
  isMine: boolean;
};

export type ActionResult =
  | { ok: true; message: string }
  | { ok: false; message: string };

export type ViewRole = Extract<
  AdminRole,
  "super_admin" | "academic_admin" | "question_reviewer"
>;
