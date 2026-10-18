import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { ForbiddenState } from "@/components/shell/forbidden-state";
import { PageHeader } from "@/components/shell/page-header";
import { buttonVariants } from "@/components/ui/button";
import { getAdminContext } from "@/lib/admin-access";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import {
  toCourseOption,
  toTopicOption,
  type TopicOption,
} from "@/features/questions/editor/catalog";
import { first, isUuid } from "@/features/questions/helpers";
import { loadCounts, type ListFilters } from "@/features/questions/list-data";
import { QuestionFilters } from "@/features/questions/question-filters";
import {
  QuestionResults,
  QuestionResultsSkeleton,
} from "@/features/questions/question-results";
import {
  CURSOR_AT,
  buildListHref,
  defaultViewFor,
  isListView,
  listRoleOf,
  viewsFor,
  type ListView,
} from "@/features/questions/search";
import { ViewTabs, ViewTabsFallback } from "@/features/questions/view-tabs";

export const metadata: Metadata = { title: "Questions" };

export default async function QuestionsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { access } = await getAdminContext();
  const listRole = access.state === "active" ? listRoleOf(access.role) : null;
  if (!listRole) return <ForbiddenState />;

  const canAuthor = listRole === "super_admin" || listRole === "academic_admin";
  const tabs = viewsFor(listRole);

  const params = await searchParams;

  const rawView = first(params.view);
  const view: ListView =
    isListView(rawView) && tabs.includes(rawView)
      ? rawView
      : defaultViewFor(listRole);

  const rawQuery = (first(params.q) ?? "").trim().slice(0, 100);
  const searchText = rawQuery.length >= 2 ? rawQuery : undefined;
  const queryTooShort = rawQuery.length === 1;

  const rawCourse = first(params.course);
  const course = rawCourse && isUuid(rawCourse) ? rawCourse : undefined;
  const rawTopic = first(params.topic);
  const topic = course && rawTopic && isUuid(rawTopic) ? rawTopic : undefined;
  const rawDifficulty = first(params.difficulty);
  const difficulty =
    rawDifficulty === "easy" ||
    rawDifficulty === "medium" ||
    rawDifficulty === "hard"
      ? rawDifficulty
      : undefined;

  const rawAt = first(params.at);
  const rawId = first(params.id);
  const cursor =
    rawAt && CURSOR_AT.test(rawAt) && rawId && isUuid(rawId)
      ? {
          at: rawAt,
          id: rawId,
          dir:
            first(params.dir) === "prev"
              ? ("prev" as const)
              : ("next" as const),
        }
      : undefined;

  const filters: ListFilters = { q: searchText, course, topic, difficulty };
  const hasFilters = Boolean(rawQuery || course || topic || difficulty);

  const countsPromise = loadCounts(filters);

  const supabase = await createSupabaseServerClient();
  const [courseResult, topicResult] = await Promise.all([
    course
      ? supabase
          .from("courses")
          .select("id, code, title")
          .eq("id", course)
          .maybeSingle()
      : null,
    course
      ? supabase
          .from("topics")
          .select("id, course_id, title")
          .eq("course_id", course)
          .order("sort_order")
          .limit(500)
      : null,
  ]);

  const selectedCourse =
    courseResult && !courseResult.error
      ? toCourseOption(courseResult.data)
      : null;
  const topics: TopicOption[] =
    topicResult && !topicResult.error && Array.isArray(topicResult.data)
      ? topicResult.data
          .map(toTopicOption)
          .filter((t): t is TopicOption => t !== null)
      : [];

  const listKey = buildListHref({ view, ...filters, cursor });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Questions"
        description="Search, review and manage the question bank."
        actions={
          canAuthor ? (
            <Link href="/admin/questions/new" className={buttonVariants()}>
              New question
            </Link>
          ) : undefined
        }
      />

      <QuestionFilters
        view={view}
        initialQuery={rawQuery}
        initialCourse={selectedCourse}
        initialTopics={topics}
        initialTopic={topic ?? ""}
        initialDifficulty={difficulty ?? ""}
        clearHref={buildListHref({ view })}
        hasFilters={hasFilters}
        queryTooShort={queryTooShort}
      />

      <Suspense
        key={`tabs:${listKey}`}
        fallback={
          <ViewTabsFallback tabs={tabs} view={view} filters={filters} />
        }
      >
        <ViewTabs
          tabs={tabs}
          view={view}
          filters={filters}
          countsPromise={countsPromise}
        />
      </Suspense>

      <Suspense
        key={`results:${listKey}`}
        fallback={<QuestionResultsSkeleton />}
      >
        <QuestionResults
          view={view}
          filters={filters}
          cursor={cursor}
          hasFilters={hasFilters}
        />
      </Suspense>
    </div>
  );
}
