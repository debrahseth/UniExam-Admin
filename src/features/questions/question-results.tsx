import {
  ChevronLeftIcon,
  ChevronRightIcon,
  ClipboardListIcon,
} from "lucide-react";
import Link from "next/link";

import {
  CardTitleSkeleton,
  SkeletonLine,
  TableSkeleton,
} from "@/components/shell/page-skeletons";
import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { InlineMessage } from "@/features/access/inline-message";

import type { ListFilters } from "./list-data";
import { QuestionTable } from "./question-table";
import {
  VIEW_LABELS,
  buildListHref,
  toListItem,
  type ListCursor,
  type ListItem,
  type ListView,
} from "./search";

const PAGE_SIZE = 25;

const EMPTY_COPY: Record<ListView, string> = {
  all: "There are no questions yet.",
  needs_review: "Nothing is waiting for your review.",
  mine: "You have no drafts or submissions in progress.",
  live: "No live questions match.",
  retired: "No retired questions match.",
};

export function QuestionResultsSkeleton() {
  return (
    <Card
      className="[--card-spacing:--spacing(5)]"
      role="status"
      aria-label="Loading questions"
    >
      <CardHeader>
        <CardTitleSkeleton width="w-28" />
        <SkeletonLine className="w-72 max-w-full" />
      </CardHeader>
      <CardContent>
        <TableSkeleton
          rows={8}
          cellClassName="px-3 py-3 align-top"
          columns={[
            { head: "w-14", cell: "h-9 w-64" },
            { head: "w-12", cell: "h-5 w-24 rounded-full" },
            { head: "w-14", cell: "h-4 w-16" },
            { head: "w-14", cell: "h-4 w-32" },
          ]}
        />
      </CardContent>
    </Card>
  );
}

export async function QuestionResults({
  view,
  filters,
  cursor,
  hasFilters,
}: {
  view: ListView;
  filters: ListFilters;
  cursor: ListCursor | undefined;
  hasFilters: boolean;
}) {
  const dir = cursor?.dir ?? "next";

  const supabase = await createSupabaseServerClient();
  const searchResult = await supabase.rpc("admin_question_search", {
    p_view: view,
    p_query: filters.q ?? null,
    p_course_id: filters.course ?? null,
    p_topic_id: filters.topic ?? null,
    p_difficulty: filters.difficulty ?? null,
    p_cursor_at: cursor?.at ?? null,
    p_cursor_id: cursor?.id ?? null,
    p_dir: dir,
    p_limit: PAGE_SIZE,
  });

  if (searchResult.error || !Array.isArray(searchResult.data)) {
    return (
      <InlineMessage tone="error" role="alert">
        The question list could not be loaded. Reload the page. If this keeps
        happening, sign out and sign in again.
      </InlineMessage>
    );
  }

  const rawRows = searchResult.data as unknown[];
  const hasExtra = rawRows.length > PAGE_SIZE;
  const pageRaw =
    dir === "next"
      ? rawRows.slice(0, PAGE_SIZE)
      : rawRows.slice(Math.max(0, rawRows.length - PAGE_SIZE));
  const items = pageRaw
    .map(toListItem)
    .filter((item): item is ListItem => item !== null);
  const skipped = pageRaw.length - items.length;

  const hasNext = dir === "next" ? hasExtra : true;
  const hasPrev = dir === "next" ? Boolean(cursor) : hasExtra;

  const nextHref =
    hasNext && items.length > 0
      ? buildListHref({
          view,
          ...filters,
          cursor: {
            at: items[items.length - 1].sortAt,
            id: items[items.length - 1].questionId,
            dir: "next",
          },
        })
      : null;
  const prevHref =
    hasPrev && items.length > 0
      ? buildListHref({
          view,
          ...filters,
          cursor: { at: items[0].sortAt, id: items[0].questionId, dir: "prev" },
        })
      : null;

  return (
    <Card className="[--card-spacing:--spacing(5)]">
      <CardHeader>
        <CardTitle className="type-card-title flex items-center gap-2">
          <ClipboardListIcon
            aria-hidden="true"
            className="size-4 text-primary"
          />
          {VIEW_LABELS[view]}
        </CardTitle>
        <CardDescription className="max-w-prose">
          One row per question.{" "}
          {view === "needs_review"
            ? "Oldest submission first."
            : "Newest activity first."}{" "}
          Times are UTC.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {skipped > 0 ? (
          <InlineMessage tone="error" role="alert">
            {skipped} {skipped === 1 ? "question" : "questions"} on this page
            could not be displayed.
          </InlineMessage>
        ) : null}

        {items.length === 0 ? (
          <div className="flex flex-col items-center gap-3 rounded-lg border border-dashed px-4 py-10 text-center">
            <ClipboardListIcon
              aria-hidden="true"
              className="size-5 text-muted-foreground"
            />
            <p className="type-body text-muted-foreground">
              {hasFilters
                ? "No questions match your search and filters."
                : cursor
                  ? "There are no more questions."
                  : EMPTY_COPY[view]}
            </p>
            {hasFilters || cursor ? (
              <Link
                href={buildListHref(
                  hasFilters ? { view } : { view, ...filters },
                )}
                className={buttonVariants({ variant: "outline" })}
              >
                {hasFilters
                  ? "Clear search and filters"
                  : "Back to the first page"}
              </Link>
            ) : null}
          </div>
        ) : (
          <QuestionTable items={items} view={view} />
        )}

        {prevHref || nextHref ? (
          <nav
            aria-label="Question pages"
            className="flex flex-wrap items-center justify-between gap-3"
          >
            <p className="type-helper text-muted-foreground tabular-nums">
              {items.length} on this page
            </p>
            <div className="flex flex-wrap items-center gap-2">
              {prevHref ? (
                <Link
                  href={prevHref}
                  className={buttonVariants({ variant: "outline" })}
                >
                  <ChevronLeftIcon aria-hidden="true" />
                  Previous
                </Link>
              ) : null}
              {nextHref ? (
                <Link
                  href={nextHref}
                  className={buttonVariants({ variant: "outline" })}
                >
                  Next
                  <ChevronRightIcon aria-hidden="true" />
                </Link>
              ) : null}
            </div>
          </nav>
        ) : null}
      </CardContent>
    </Card>
  );
}
