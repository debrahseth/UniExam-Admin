import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { ForbiddenState } from "@/components/shell/forbidden-state";
import { PageHeader } from "@/components/shell/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getAdminContext } from "@/lib/admin-access";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { InlineMessage } from "@/features/access/inline-message";
import { BackLink } from "@/features/questions/back-link";
import {
  toTopicOption,
  type TopicOption,
} from "@/features/questions/editor/catalog";
import { isUuid, toQuestionDetail } from "@/features/questions/helpers";
import { QuestionEditor } from "@/features/questions/editor/question-editor";

export const metadata: Metadata = { title: "Edit Question" };

export default async function EditQuestionPage({
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

  const editable =
    d.isMine && (d.reviewState === "draft" || d.reviewState === "rejected");
  if (!editable) {
    return (
      <div className="space-y-6">
        {back}
        <InlineMessage tone="warning">
          This version can&apos;t be edited. Only the author can edit a draft or
          a rejected version.
        </InlineMessage>
      </div>
    );
  }

  const topicLocked = d.questionStatus !== "draft";
  let topics: TopicOption[] = [];
  if (!topicLocked) {
    const result = await supabase
      .from("topics")
      .select("id, course_id, title")
      .eq("course_id", d.courseId)
      .order("sort_order");
    if (result.error || !Array.isArray(result.data)) {
      return (
        <div className="space-y-6">
          {back}
          <InlineMessage tone="error" role="alert">
            The topics could not be loaded. Reload the page.
          </InlineMessage>
        </div>
      );
    }
    topics = result.data
      .map(toTopicOption)
      .filter((t): t is TopicOption => t !== null);
  }

  return (
    <div className="space-y-6">
      {back}

      <PageHeader
        title="Edit question"
        description={`${d.courseCode} · Version ${d.version}. Saving keeps it as a draft.`}
      />

      {d.reviewState === "rejected" && d.reviewNote ? (
        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title">
              Why it was rejected
            </CardTitle>
          </CardHeader>
          <CardContent className="type-body whitespace-pre-wrap wrap-anywhere">
            {d.reviewNote}
          </CardContent>
        </Card>
      ) : null}

      <QuestionEditor
        mode="edit"
        topics={topics}
        versionId={d.versionId}
        questionId={d.questionId}
        fixedCourse={d.courseCode}
        fixedTopic={topicLocked ? (d.topicTitle ?? "No topic") : undefined}
        initial={{
          courseId: d.courseId,
          topicId: d.topicId ?? "",
          stem: d.stem,
          options: d.options.map((o) => o.text),
          correctIndex: d.options.findIndex((o) => o.id === d.correctOptionId),
          explanation: d.explanation ?? "",
          difficulty: d.difficulty ?? "",
        }}
        submitLabel="Save draft"
        cancelHref={`/admin/questions/${d.versionId}`}
      />
    </div>
  );
}
