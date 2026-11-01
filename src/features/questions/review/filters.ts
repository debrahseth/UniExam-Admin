import type { AdminRole } from "@/config/navigation";

export type TopicFilter = "all" | "needs_review" | "mine" | "live" | "retired";

const FILTERS: readonly TopicFilter[] = [
  "all",
  "needs_review",
  "mine",
  "live",
  "retired",
];

export function isTopicFilter(value: unknown): value is TopicFilter {
  return (
    typeof value === "string" && (FILTERS as readonly string[]).includes(value)
  );
}

export const FILTER_LABELS: Record<TopicFilter, string> = {
  all: "All",
  needs_review: "Waiting for Review",
  mine: "My Work",
  live: "Live Questions",
  retired: "Retired Questions",
};

export const FILTER_HELP: Partial<Record<TopicFilter, string>> = {
  needs_review:
    "Questions with a version waiting for review. Your own submissions are included, but another reviewer has to review them.",
  mine: "Questions with a draft, submitted or rejected version that you wrote.",
};

export type QuestionRole = Extract<
  AdminRole,
  "super_admin" | "academic_admin" | "question_reviewer"
>;

export function questionRoleOf(role: AdminRole): QuestionRole | null {
  return role === "super_admin" ||
    role === "academic_admin" ||
    role === "question_reviewer"
    ? role
    : null;
}

export function filtersFor(role: QuestionRole): TopicFilter[] {
  const list: TopicFilter[] = ["all"];
  if (role === "super_admin" || role === "question_reviewer") {
    list.push("needs_review");
  }
  if (role === "super_admin" || role === "academic_admin") list.push("mine");
  list.push("live", "retired");
  return list;
}
