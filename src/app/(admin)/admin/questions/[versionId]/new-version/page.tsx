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
import {
  STATE_LABELS,
  isUuid,
  toQuestionDetail,
} from "@/features/questions/helpers";
import { QuestionEditor } from "@/features/questions/editor/question-editor";
import { toHistoryEntry, type HistoryEntry } from "@/features/questions/search";

export const metadata: Metadata = { title: "New Version" };

export default async function NewVersionPage({
  params,
}: {
  params: Promise<{ versionId: string }>;
}) {
  const { versionId } = await params;
  if (!isUuid(versionId)) notFound();

  const { access } = await getAdminContext();
  if (
    access.state !== "active" ||
    (access.role !== "super_admin" && access.role !== "academic_admin")
  ) {
    return <ForbiddenState />;
  }

  const back = (
    <BackLink href={`/admin/questions/${versionId}`}>
      Back to the question
    </BackLink>
  );

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("admin_question_get", {
    p_version_id: versionId,
  });

  if (error) {
    return (
      <div className="space-y-6">
        {back}
        <InlineMessage tone="error" role="alert">
          This question could not be loaded. Reload the page. If this keeps
          happening, sign out and sign in again.
        </InlineMessage>
      </div>
    );
  }
  if (!Array.isArray(data) || data.length === 0) notFound();

  const d = toQuestionDetail(data[0]);
  if (!d) {
    return (
      <div className="space-y-6">
        {back}
        <InlineMessage tone="error" role="alert">
          This question came back in an unexpected format and cannot be edited.
        </InlineMessage>
      </div>
    );
  }

  if (!d.isLive || d.questionStatus !== "published") {
    return (
      <div className="space-y-6">
        {back}
        <InlineMessage tone="warning">
          A new version can only be started from the live version of a published
          question. If this question is retired, restore it first.
        </InlineMessage>
      </div>
    );
  }

  if (d.options.length > 6) {
    return (
      <div className="space-y-6">
        {back}
        <InlineMessage tone="warning">
          This question has more than 6 options, which the exam screen cannot
          show, so it can&apos;t be copied into the editor.
        </InlineMessage>
      </div>
    );
  }

  const historyResult = await supabase.rpc("admin_question_history", {
    p_question_id: d.questionId,
  });
  const history: HistoryEntry[] = Array.isArray(historyResult.data)
    ? historyResult.data
        .map(toHistoryEntry)
        .filter((e): e is HistoryEntry => e !== null)
    : [];
  const open = history.find(
    (e) =>
      e.reviewState === "draft" ||
      e.reviewState === "submitted" ||
      e.reviewState === "rejected",
  );

  if (open) {
    return (
      <div className="space-y-6">
        {back}
        <InlineMessage tone="warning">
          This question already has an unfinished version (version{" "}
          {open.version}, {STATE_LABELS[open.reviewState].toLowerCase()}).
          Finish or discard it before starting another.
        </InlineMessage>
        <div>
          <Link
            href={`/admin/questions/${open.versionId}`}
            className={buttonVariants({ variant: "outline" })}
          >
            Open version {open.version}
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {back}

      <PageHeader
        title="New version"
        description={`${d.courseCode} · Starting from version ${d.version}. Students keep seeing version ${d.version} until the new one is approved.`}
      />
      <QuestionEditor
        mode="new_version"
        topics={[]}
        questionId={d.questionId}
        fixedCourse={d.courseCode}
        fixedTopic={d.topicTitle ?? "No topic"}
        initial={{
          courseId: d.courseId,
          topicId: d.topicId ?? "",
          stem: d.stem,
          options: d.options.map((o) => o.text),
          correctIndex: d.options.findIndex((o) => o.id === d.correctOptionId),
          explanation: d.explanation ?? "",
          difficulty: d.difficulty ?? "",
        }}
        submitLabel="Save as draft"
        cancelHref={`/admin/questions/${d.versionId}`}
      />
    </div>
  );
}
