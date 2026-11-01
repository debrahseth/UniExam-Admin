"use server";

import { revalidatePath } from "next/cache";

import { getAdminContext } from "@/lib/admin-access";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import {
  toCourseOption,
  toTopicOption,
  type CourseOption,
  type TopicOption,
} from "@/features/questions/editor/catalog";

const NOT_ALLOWED =
  "Your session no longer has permission to import questions. Reload the page or sign in again.";
const GENERIC =
  "The import could not be completed. Nothing from this request was saved.";

export type CourseLookup =
  | { ok: true; course: CourseOption; topics: TopicOption[] }
  | { ok: false; message: string };

export type ImportOutcome = "created" | "skipped" | "failed";

export type ImportResultRow = {
  index: number;
  key: string | null;
  outcome: ImportOutcome;
  versionId: string | null;
  error: string | null;
};

export type ImportBatchResult =
  | { ok: true; rows: ImportResultRow[] }
  | { ok: false; message: string };

async function isAuthor(): Promise<boolean> {
  const { access } = await getAdminContext();
  return (
    access.state === "active" &&
    (access.role === "super_admin" || access.role === "academic_admin")
  );
}

function isActiveRow(row: unknown): boolean {
  return (
    typeof row === "object" &&
    row !== null &&
    (row as Record<string, unknown>).is_active === true
  );
}

export async function resolveImportCourse(
  courseText: string,
): Promise<CourseLookup> {
  if (!(await isAuthor())) return { ok: false, message: NOT_ALLOWED };

  const text = typeof courseText === "string" ? courseText.trim() : "";
  const match = /^([A-Za-z]{2,8})\s*(\d{2,4}[A-Za-z]?)$/.exec(text);
  if (!match) {
    return {
      ok: false,
      message: `"${text.slice(0, 40)}" is not a recognised course code. Use a code such as CHE 151.`,
    };
  }

  const letters = match[1].toUpperCase();
  const digits = match[2].toUpperCase();

  const supabase = await createSupabaseServerClient();
  const found = await supabase
    .from("courses")
    .select("id, code, title, is_active")
    .in("code", [`${letters}${digits}`, `${letters} ${digits}`]);

  if (found.error || !Array.isArray(found.data)) {
    return {
      ok: false,
      message:
        "The course could not be looked up. Reload the page and try again.",
    };
  }

  const courses = found.data
    .filter(isActiveRow)
    .map(toCourseOption)
    .filter((c): c is CourseOption => c !== null);

  if (courses.length === 0) {
    return {
      ok: false,
      message:
        found.data.length > 0
          ? `The course ${letters} ${digits} exists but is not active.`
          : `No course with the code ${letters} ${digits} exists.`,
    };
  }
  if (courses.length > 1) {
    return {
      ok: false,
      message: `More than one active course matches ${letters} ${digits}. Fix the course codes first.`,
    };
  }

  const course = courses[0];
  const topicResult = await supabase
    .from("topics")
    .select("id, course_id, title")
    .eq("course_id", course.id)
    .order("sort_order")
    .limit(500);

  if (topicResult.error || !Array.isArray(topicResult.data)) {
    return {
      ok: false,
      message: "The topics could not be loaded. Reload the page and try again.",
    };
  }

  const topics = topicResult.data
    .map(toTopicOption)
    .filter((t): t is TopicOption => t !== null);

  return { ok: true, course, topics };
}

function batchMessage(message: string | undefined): string {
  const text = message ?? "";
  if (text.includes("not_authorized")) return NOT_ALLOWED;
  if (text.includes("batch_too_large"))
    return "That is more than 100 questions in one request.";
  if (text.includes("invalid_batch"))
    return "The request was not a list of questions.";
  return GENERIC;
}

function toResultRow(raw: unknown): ImportResultRow | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;

  const outcome = r.o_outcome;
  if (
    typeof r.o_index !== "number" ||
    (outcome !== "created" && outcome !== "skipped" && outcome !== "failed") ||
    (r.o_key !== null && typeof r.o_key !== "string") ||
    (r.o_version_id !== null && typeof r.o_version_id !== "string") ||
    (r.o_error !== null && typeof r.o_error !== "string")
  ) {
    return null;
  }

  return {
    index: r.o_index,
    key: r.o_key,
    outcome,
    versionId: r.o_version_id,
    error: r.o_error,
  };
}

export async function importQuestions(
  items: unknown,
): Promise<ImportBatchResult> {
  if (!(await isAuthor())) return { ok: false, message: NOT_ALLOWED };

  if (!Array.isArray(items) || items.length === 0 || items.length > 100) {
    return {
      ok: false,
      message:
        "There is nothing to import, or more than 100 questions in one request.",
    };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("admin_question_import_batch", {
    p_items: items,
  });
  if (error) return { ok: false, message: batchMessage(error.message) };
  if (!Array.isArray(data)) return { ok: false, message: GENERIC };

  const rows: ImportResultRow[] = [];
  for (const raw of data) {
    const row = toResultRow(raw);
    if (!row) {
      return {
        ok: false,
        message:
          "The answer came back in an unexpected format. Check the questions list before importing again.",
      };
    }
    rows.push(row);
  }
  rows.sort((a, b) => a.index - b.index);

  if (rows.some((row) => row.outcome === "created")) {
    revalidatePath("/admin/questions", "layout");
  }

  return { ok: true, rows };
}
