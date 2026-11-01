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
import {
  groupCourses,
  toCourseRow,
  toProgrammeHeader,
  type CourseSlotRow,
} from "@/features/questions/review/courses";
import {
  FILTER_HELP,
  FILTER_LABELS,
  filtersFor,
  isTopicFilter,
  questionRoleOf,
  type TopicFilter,
} from "@/features/questions/review/filters";
import {
  toReviewItem,
  type ReviewItem,
} from "@/features/questions/review/review-items";
import { ReviewModal } from "@/features/questions/review/review-modal";
import { TopicCard } from "@/features/questions/review/topic-card";
import { TopicFilterTabs } from "@/features/questions/review/topic-filter-tabs";
import {
  toTopicCard,
  type TopicCardData,
} from "@/features/questions/review/topics";

export const metadata: Metadata = { title: "Topics" };

function topicHref(
  basePath: string,
  filter: TopicFilter,
  topicId: string | null,
): string {
  const query = new URLSearchParams();
  if (filter !== "all") query.set("filter", filter);
  query.set("topic", topicId ?? "none");
  return `${basePath}?${query.toString()}`;
}

export default async function CourseTopicsPage({
  params,
  searchParams,
}: {
  params: Promise<{ programmeId: string; courseId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { programmeId, courseId } = await params;
  if (!isUuid(programmeId) || !isUuid(courseId)) notFound();

  const { access } = await getAdminContext();
  const role = access.state === "active" ? questionRoleOf(access.role) : null;
  if (!role) return <ForbiddenState />;

  const query = await searchParams;
  const available = filtersFor(role);
  const rawFilter = first(query.filter);
  const filter: TopicFilter =
    isTopicFilter(rawFilter) && available.includes(rawFilter)
      ? rawFilter
      : "all";

  const rawTopic = first(query.topic);
  const modalTopic =
    rawTopic === "none"
      ? "none"
      : rawTopic && isUuid(rawTopic)
        ? rawTopic
        : null;

  const back = (
    <BackLink href={`/admin/questions/programmes/${programmeId}`}>
      Back to courses
    </BackLink>
  );

  const supabase = await createSupabaseServerClient();
  const [programmeResult, coursesResult, topicsResult, listResult] =
    await Promise.all([
      supabase
        .from("programmes")
        .select("id, code, name, is_active")
        .eq("id", programmeId)
        .maybeSingle(),
      supabase.rpc("admin_catalog_courses", { p_programme_id: programmeId }),
      supabase.rpc("admin_catalog_topics", {
        p_course_id: courseId,
        p_filter: filter,
      }),
      modalTopic
        ? supabase.rpc("admin_topic_questions", {
            p_course_id: courseId,
            p_topic_id: modalTopic === "none" ? null : modalTopic,
            p_filter: filter,
          })
        : null,
    ]);

  if (!programmeResult.error && programmeResult.data === null) notFound();
  if (coursesResult.error?.message.includes("target_not_found")) notFound();
  if (topicsResult.error?.message.includes("target_not_found")) notFound();

  const programme = programmeResult.error
    ? null
    : toProgrammeHeader(programmeResult.data);

  if (
    !programme ||
    coursesResult.error ||
    !Array.isArray(coursesResult.data) ||
    topicsResult.error ||
    !Array.isArray(topicsResult.data)
  ) {
    return (
      <div className="space-y-6">
        {back}
        <InlineMessage tone="error" role="alert">
          The topics could not be loaded. Reload the page. If this keeps
          happening, sign out and sign in again.
        </InlineMessage>
      </div>
    );
  }

  const courseRows = (coursesResult.data as unknown[])
    .map(toCourseRow)
    .filter(
      (row): row is CourseSlotRow => row !== null && row.courseId === courseId,
    );
  const course = groupCourses(courseRows)[0];
  if (!course) notFound();

  const rawTopics = topicsResult.data as unknown[];
  const topics = rawTopics
    .map(toTopicCard)
    .filter((t): t is TopicCardData => t !== null);
  const skipped = rawTopics.length - topics.length;

  const basePath = `/admin/questions/programmes/${programmeId}/courses/${courseId}`;
  const closeHref =
    filter === "all" ? basePath : `${basePath}?filter=${filter}`;
  const slotText = course.slots
    .map((slot) => `${slot.levelName} · ${slot.semesterName}`)
    .join("; ");

  let modalItems: ReviewItem[] | null = null;
  let modalFailed = false;
  let modalSkipped = 0;
  let modalTruncated = false;
  if (modalTopic && listResult) {
    if (listResult.error || !Array.isArray(listResult.data)) {
      modalFailed = true;
    } else {
      const rawItems = listResult.data as unknown[];
      modalItems = rawItems
        .map(toReviewItem)
        .filter((i): i is ReviewItem => i !== null);
      modalSkipped = rawItems.length - modalItems.length;
      modalTruncated = rawItems.length >= 1000;
    }
  }
  const modalTitle =
    modalTopic === "none"
      ? "No topic"
      : (topics.find((t) => t.id === modalTopic)?.title ?? "Topic");

  return (
    <div className="space-y-6">
      {back}

      <PageHeader
        title={course.title}
        description={`${course.code} · ${programme.name}`}
      />

      <p className="type-body text-muted-foreground">{slotText}</p>

      {!course.isActive ? (
        <InlineMessage tone="warning">This course is inactive.</InlineMessage>
      ) : null}

      <div className="space-y-2">
        <TopicFilterTabs
          filters={available}
          active={filter}
          basePath={basePath}
        />
        {FILTER_HELP[filter] ? (
          <p className="type-helper max-w-prose text-muted-foreground">
            {FILTER_HELP[filter]}
          </p>
        ) : null}
      </div>

      {skipped > 0 ? (
        <InlineMessage tone="error" role="alert">
          {skipped} {skipped === 1 ? "topic" : "topics"} could not be displayed.
        </InlineMessage>
      ) : null}

      {modalFailed ? (
        <InlineMessage tone="error" role="alert">
          The questions for that topic could not be loaded. Choose a topic below
          to try again.
        </InlineMessage>
      ) : null}

      {modalSkipped > 0 ? (
        <InlineMessage tone="error" role="alert">
          {modalSkipped} {modalSkipped === 1 ? "question" : "questions"} in that
          topic could not be displayed.
        </InlineMessage>
      ) : null}

      {topics.length === 0 ? (
        <div className="flex flex-col items-start gap-3">
          <InlineMessage tone="neutral">
            {filter === "all"
              ? "This course has no topics yet."
              : "No questions match this filter."}
          </InlineMessage>
          {filter !== "all" ? (
            <Link
              href={basePath}
              className={buttonVariants({ variant: "outline" })}
            >
              Show all questions
            </Link>
          ) : null}
        </div>
      ) : (
        <section aria-labelledby="topics-heading" className="space-y-3">
          <h2 id="topics-heading" className="type-section-title">
            Topics
            <span className="type-body ml-2 font-normal text-muted-foreground tabular-nums">
              {topics.length}
            </span>
          </h2>
          <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {topics.map((topic) => (
              <li key={topic.id ?? "none"}>
                <TopicCard
                  topic={topic}
                  href={
                    topic.total > 0
                      ? topicHref(basePath, filter, topic.id)
                      : null
                  }
                />
              </li>
            ))}
          </ul>
        </section>
      )}

      {modalItems ? (
        <ReviewModal
          key={`${modalTopic}:${filter}`}
          title={modalTitle}
          subtitle={`${course.code} · ${FILTER_LABELS[filter]}`}
          items={modalItems}
          role={role}
          closeHref={closeHref}
          truncated={modalTruncated}
        />
      ) : null}
    </div>
  );
}
