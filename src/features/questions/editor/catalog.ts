export type CourseOption = { id: string; code: string; title: string };
export type TopicOption = { id: string; courseId: string; title: string };

export function toCourseOption(row: unknown): CourseOption | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  if (
    typeof r.id !== "string" ||
    typeof r.code !== "string" ||
    typeof r.title !== "string"
  ) {
    return null;
  }
  return { id: r.id, code: r.code, title: r.title };
}

export function toTopicOption(row: unknown): TopicOption | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  if (
    typeof r.id !== "string" ||
    typeof r.course_id !== "string" ||
    typeof r.title !== "string"
  ) {
    return null;
  }
  return { id: r.id, courseId: r.course_id, title: r.title };
}
