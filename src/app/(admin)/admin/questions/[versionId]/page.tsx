import type { Metadata } from "next";
import { ArrowLeftIcon, LockIcon } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";

import { ForbiddenState } from "@/components/shell/forbidden-state";
import { PageHeader } from "@/components/shell/page-header";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getAdminContext } from "@/lib/admin-access";
import { formatUtc } from "@/lib/format";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { InlineMessage } from "@/features/access/inline-message";
import {
  DIFFICULTY_LABELS,
  isUuid,
  toQuestionDetail,
} from "@/features/questions/helpers";
import { QuestionPreview } from "@/features/questions/question-preview";
import { QuestionStatusBadges } from "@/features/questions/status-badge";
import type { QuestionIntent } from "@/features/questions/types";
import { WorkflowActions } from "@/features/questions/workflow-actions";
import { toHistoryEntry, type HistoryEntry } from "@/features/questions/search";
import { VersionHistory } from "@/features/questions/version-history";

export const metadata: Metadata = { title: "Question" };

function BackLink() {
  return (
    <div>
      <Link
        href="/admin/questions"
        className={buttonVariants({ variant: "ghost", size: "sm" })}
      >
        <ArrowLeftIcon aria-hidden="true" />
        Back to questions
      </Link>
    </div>
  );
}

function DetailRow({
  label,
  children,
  muted = false,
  breakAll = false,
}: {
  label: string;
  children: ReactNode;
  muted?: boolean;
  breakAll?: boolean;
}) {
  return (
    <div className="grid gap-0.5 sm:grid-cols-[7rem_1fr] sm:gap-x-4">
      <dt className="type-body text-muted-foreground">{label}</dt>
      <dd
        className={`type-body ${muted ? "text-muted-foreground" : ""} ${breakAll ? "break-all" : ""}`}
      >
        {children}
      </dd>
    </div>
  );
}

export default async function QuestionDetailPage({
  params,
}: {
  params: Promise<{ versionId: string }>;
}) {
  const { versionId } = await params;
  if (!isUuid(versionId)) notFound();

  const { access } = await getAdminContext();
  if (
    access.state !== "active" ||
    (access.role !== "super_admin" &&
      access.role !== "academic_admin" &&
      access.role !== "question_reviewer")
  ) {
    return <ForbiddenState />;
  }
  const role = access.role;

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("admin_question_get", {
    p_version_id: versionId,
  });

  if (error) {
    return (
      <div className="space-y-6">
        <BackLink />
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
        <BackLink />
        <InlineMessage tone="error" role="alert">
          This question came back in an unexpected format and cannot be shown.
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

  const isAuthorRole = role === "super_admin" || role === "academic_admin";
  const isReviewerRole = role === "super_admin" || role === "question_reviewer";

  const allowed: QuestionIntent[] = [];
  if (d.isMine && isAuthorRole && d.reviewState === "draft") {
    allowed.push("submit");
  }
  if (
    d.isMine &&
    isAuthorRole &&
    (d.reviewState === "draft" || d.reviewState === "rejected")
  ) {
    allowed.push("discard");
  }
  if (isReviewerRole && d.reviewState === "submitted" && !d.isMine) {
    allowed.push("approve", "reject");
  }
  if (isReviewerRole && d.questionStatus === "published" && d.isLive) {
    allowed.push("retire");
  }
  if (isReviewerRole && d.questionStatus === "retired") {
    allowed.push("restore");
  }

  const canEdit =
    d.isMine &&
    isAuthorRole &&
    (d.reviewState === "draft" || d.reviewState === "rejected");
  const canNewVersion = isAuthorRole && d.isLive;
  const correct = d.options.find((o) => o.id === d.correctOptionId) ?? null;
  const author =
    d.authorEmail ??
    (d.reviewState === "imported" ? "Loaded by script" : "Unknown");

  return (
    <div className="space-y-6">
      <BackLink />

      <PageHeader
        title={`${d.courseCode} question`}
        description={`Version ${d.version}${d.topicTitle ? ` · ${d.topicTitle}` : ""}`}
        actions={
          canEdit || canNewVersion || allowed.length > 0 ? (
            <div className="flex flex-wrap items-start gap-2 sm:justify-end">
              {canEdit ? (
                <Link
                  href={`/admin/questions/${d.versionId}/edit`}
                  className={buttonVariants({ variant: "outline" })}
                >
                  Edit
                </Link>
              ) : null}
              {canNewVersion ? (
                <Link
                  href={`/admin/questions/${d.versionId}/new-version`}
                  className={buttonVariants({ variant: "outline" })}
                >
                  New version
                </Link>
              ) : null}
              {allowed.length > 0 ? (
                <WorkflowActions
                  versionId={d.versionId}
                  questionId={d.questionId}
                  allowed={allowed}
                />
              ) : null}
            </div>
          ) : undefined
        }
      />

      <div className="flex flex-wrap items-center gap-2">
        <QuestionStatusBadges
          reviewState={d.reviewState}
          isLive={d.isLive}
          questionStatus={d.questionStatus}
        />
        {d.difficulty ? (
          <Badge variant="outline">{DIFFICULTY_LABELS[d.difficulty]}</Badge>
        ) : null}
      </div>

      {d.isMine && isReviewerRole && d.reviewState === "submitted" ? (
        <InlineMessage tone="neutral">
          You wrote this version, so another reviewer has to approve or reject
          it.
        </InlineMessage>
      ) : null}

      {d.reviewNote ? (
        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title">
              {d.reviewState === "rejected"
                ? "Why it was rejected"
                : "Reviewer's note"}
            </CardTitle>
          </CardHeader>
          <CardContent className="type-body whitespace-pre-wrap wrap-anywhere">
            {d.reviewNote}
          </CardContent>
        </Card>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title">Details</CardTitle>
            <CardDescription>Times are UTC.</CardDescription>
          </CardHeader>
          <CardContent>
            <dl className="flex flex-col gap-3 sm:gap-2">
              <DetailRow label="Author" muted={!d.authorEmail} breakAll>
                {author}
              </DetailRow>
              <DetailRow label="Submitted" muted={!d.submittedAt}>
                {d.submittedAt ? (
                  <time dateTime={d.submittedAt} className="tabular-nums">
                    {formatUtc(d.submittedAt)}
                  </time>
                ) : (
                  "Not submitted"
                )}
              </DetailRow>
              <DetailRow label="Reviewer" muted={!d.reviewerEmail} breakAll>
                {d.reviewerEmail ?? "Not reviewed"}
              </DetailRow>
              <DetailRow label="Reviewed" muted={!d.reviewedAt}>
                {d.reviewedAt ? (
                  <time dateTime={d.reviewedAt} className="tabular-nums">
                    {formatUtc(d.reviewedAt)}
                  </time>
                ) : (
                  "Not reviewed"
                )}
              </DetailRow>
            </dl>
          </CardContent>
        </Card>

        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title flex items-center gap-2">
              <LockIcon aria-hidden="true" className="size-4 text-primary" />
              Answer key
            </CardTitle>
            <CardDescription>Only admins can see this.</CardDescription>
          </CardHeader>
          <CardContent>
            {correct ? (
              <div className="flex items-start gap-3 rounded-lg border border-primary/40 bg-accent px-3 py-2.5">
                <span
                  aria-hidden="true"
                  className="flex size-6 shrink-0 items-center justify-center rounded-md bg-primary text-xs font-semibold text-primary-foreground uppercase"
                >
                  {correct.id}
                </span>
                <span className="type-body min-w-0 wrap-anywhere">
                  <span className="sr-only">Correct option {correct.id}: </span>
                  {correct.text}
                </span>
              </div>
            ) : (
              <InlineMessage tone="error">
                No answer key was found for this version.
              </InlineMessage>
            )}
          </CardContent>
        </Card>
      </div>

      {history.length > 1 ? (
        <VersionHistory entries={history} currentVersionId={d.versionId} />
      ) : null}

      <QuestionPreview
        stem={d.stem}
        options={d.options}
        correctId={d.correctOptionId}
        explanation={d.explanation}
      />
    </div>
  );
}
