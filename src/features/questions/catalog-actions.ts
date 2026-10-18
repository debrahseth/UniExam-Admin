"use server";

import { getAdminContext } from "@/lib/admin-access";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import {
  toCourseOption,
  toTopicOption,
  type CourseOption,
  type TopicOption,
} from "./editor/catalog";
import { isUuid } from "./helpers";

const LIMIT = 20;

async function isQuestionAdmin(): Promise<boolean> {
  const { access } = await getAdminContext();
  return (
    access.state === "active" &&
    (access.role === "super_admin" ||
      access.role === "academic_admin" ||
      access.role === "question_reviewer")
  );
}

function likePattern(text: string): string {
  return `%${text.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
}

export async function searchCourses(
  query: string,
  activeOnly: boolean,
): Promise<CourseOption[]> {
  if (!(await isQuestionAdmin())) return [];

  const text = typeof query === "string" ? query.trim().slice(0, 100) : "";
  const supabase = await createSupabaseServerClient();

  const build = (column: "code" | "title") => {
    let request = supabase.from("courses").select("id, code, title");
    if (activeOnly) request = request.eq("is_active", true);
    if (text) request = request.ilike(column, likePattern(text));
    return request.order("code").limit(LIMIT);
  };

  const results = await Promise.all(
    text ? [build("code"), build("title")] : [build("code")],
  );

  const found = new Map<string, CourseOption>();
  for (const result of results) {
    if (result.error || !Array.isArray(result.data)) continue;
    for (const row of result.data) {
      const course = toCourseOption(row);
      if (course) found.set(course.id, course);
    }
  }

  return [...found.values()]
    .sort((a, b) => a.code.localeCompare(b.code))
    .slice(0, LIMIT);
}

export async function loadTopics(courseId: string): Promise<TopicOption[]> {
  if (!isUuid(courseId) || !(await isQuestionAdmin())) return [];

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("topics")
    .select("id, course_id, title")
    .eq("course_id", courseId)
    .order("sort_order")
    .limit(500);

  if (error || !Array.isArray(data)) return [];
  return data.map(toTopicOption).filter((t): t is TopicOption => t !== null);
}
