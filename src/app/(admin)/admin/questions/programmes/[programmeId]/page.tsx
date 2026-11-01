import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ForbiddenState } from "@/components/shell/forbidden-state";
import { PageHeader } from "@/components/shell/page-header";
import { buttonVariants } from "@/components/ui/button";
import { getAdminContext } from "@/lib/admin-access";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { InlineMessage } from "@/features/access/inline-message";
import { BackLink } from "@/features/questions/back-link";
import { first, isUuid } from "@/features/questions/helpers";
import { CourseCard } from "@/features/questions/review/course-card";
import { CourseFilters } from "@/features/questions/review/course-filters";
import {
  filterRows,
  groupCourses,
  levelOptions,
  semesterOptions,
  toCourseRow,
  toProgrammeHeader,
  type CourseSlotRow,
} from "@/features/questions/review/courses";

export const metadata: Metadata = { title: "Courses" };

export default async function ProgrammeCoursesPage({
  params,
  searchParams,
}: {
  params: Promise<{ programmeId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { programmeId } = await params;
  if (!isUuid(programmeId)) notFound();

  const { access } = await getAdminContext();
  if (
    access.state !== "active" ||
    (access.role !== "super_admin" &&
      access.role !== "academic_admin" &&
      access.role !== "question_reviewer")
  ) {
    return <ForbiddenState />;
  }

  const back = <BackLink href="/admin/questions">Back to programmes</BackLink>;

  const supabase = await createSupabaseServerClient();
  const [programmeResult, coursesResult] = await Promise.all([
    supabase
      .from("programmes")
      .select("id, code, name, is_active")
      .eq("id", programmeId)
      .maybeSingle(),
    supabase.rpc("admin_catalog_courses", { p_programme_id: programmeId }),
  ]);

  if (!programmeResult.error && programmeResult.data === null) notFound();
  if (coursesResult.error?.message.includes("target_not_found")) notFound();

  const programme = programmeResult.error
    ? null
    : toProgrammeHeader(programmeResult.data);

  if (!programme || coursesResult.error || !Array.isArray(coursesResult.data)) {
    return (
      <div className="space-y-6">
        {back}
        <InlineMessage tone="error" role="alert">
          The courses could not be loaded. Reload the page. If this keeps
          happening, sign out and sign in again.
        </InlineMessage>
      </div>
    );
  }

  const rawRows = coursesResult.data as unknown[];
  const rows = rawRows
    .map(toCourseRow)
    .filter((row): row is CourseSlotRow => row !== null);
  const skipped = rawRows.length - rows.length;
  const truncated = rawRows.length >= 1000;

  const levels = levelOptions(rows);
  const semesters = semesterOptions(rows);

  const query = await searchParams;
  const rawLevel = first(query.level);
  const rawSemester = first(query.semester);
  const level = levels.some((o) => o.value === rawLevel)
    ? (rawLevel ?? "")
    : "";
  const semester = semesters.some((o) => o.value === rawSemester)
    ? (rawSemester ?? "")
    : "";

  const allCount = new Set(rows.map((row) => row.courseId)).size;
  const cards = groupCourses(filterRows(rows, level, semester));
  const filtered = Boolean(level || semester);
  const basePath = `/admin/questions/programmes/${programme.id}`;

  return (
    <div className="space-y-6">
      {back}

      <PageHeader
        title={programme.name}
        description={
          allCount > 0
            ? `${programme.code} · ${allCount} ${allCount === 1 ? "course" : "courses"}`
            : programme.code
        }
      />

      {!programme.isActive ? (
        <InlineMessage tone="warning">
          This programme is inactive.
        </InlineMessage>
      ) : null}

      {skipped > 0 ? (
        <InlineMessage tone="error" role="alert">
          {skipped} {skipped === 1 ? "course entry" : "course entries"} could
          not be displayed.
        </InlineMessage>
      ) : null}

      {truncated ? (
        <InlineMessage tone="warning">
          This programme has more courses than can be loaded at once, so some
          are missing.
        </InlineMessage>
      ) : null}

      {allCount === 0 ? (
        <InlineMessage tone="neutral">
          This programme has no courses yet.
        </InlineMessage>
      ) : (
        <>
          <CourseFilters
            basePath={basePath}
            levels={levels}
            semesters={semesters}
            level={level}
            semester={semester}
          />

          <section aria-labelledby="courses-heading" className="space-y-3">
            <h2 id="courses-heading" className="type-section-title">
              Courses
              <span
                aria-live="polite"
                className="type-body ml-2 font-normal text-muted-foreground tabular-nums"
              >
                {filtered ? `${cards.length} of ${allCount}` : allCount}
              </span>
            </h2>

            {cards.length === 0 ? (
              <div className="flex flex-col items-start gap-3">
                <InlineMessage tone="neutral">
                  No courses match these filters.
                </InlineMessage>
                <Link
                  href={basePath}
                  className={buttonVariants({ variant: "outline" })}
                >
                  Clear filters
                </Link>
              </div>
            ) : (
              <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                {cards.map((course) => (
                  <li key={course.id}>
                    <CourseCard
                      course={course}
                      href={`${basePath}/courses/${course.id}`}
                    />
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}
    </div>
  );
}
