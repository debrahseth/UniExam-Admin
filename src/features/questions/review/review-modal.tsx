"use client";

import {
  ChevronLeftIcon,
  ChevronRightIcon,
  ExternalLinkIcon,
} from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";

import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { formatUtc } from "@/lib/format";

import { InlineMessage } from "@/features/access/inline-message";

import { DIFFICULTY_LABELS, STATE_LABELS } from "../helpers";
import { QuestionPreview } from "../question-preview";
import type { HistoryEntry } from "../search";
import { QuestionStatusBadges } from "../status-badge";
import type { QuestionDetail, QuestionIntent } from "../types";
import { WorkflowActions } from "../workflow-actions";
import type { QuestionRole } from "./filters";
import {
  allowedIntents,
  canEdit,
  canStartNewVersion,
  mustBeReviewedByOthers,
} from "./permissions";
import {
  loadReviewQuestion,
  type ReviewQuestionResult,
} from "./review-actions";
import type { ReviewItem } from "./review-items";

type Loaded = { key: string; result: ReviewQuestionResult };

const OPEN_STATES = ["draft", "submitted", "rejected"];
const TOOL_LINK = `${buttonVariants({ variant: "outline", size: "lg" })} px-4`;

function Meta({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-0.5 sm:grid-cols-[6rem_1fr] sm:gap-x-3">
      <dt className="type-helper text-muted-foreground">{label}</dt>
      <dd className="type-body min-w-0 wrap-anywhere">{children}</dd>
    </div>
  );
}

function BodySkeleton() {
  return (
    <div role="status" aria-label="Loading question" className="space-y-4">
      <Skeleton className="h-6 w-56" />
      <Skeleton className="h-20 w-full" />
      <Skeleton className="h-11 w-full" />
      <Skeleton className="h-11 w-full" />
      <Skeleton className="h-11 w-full" />
      <Skeleton className="h-11 w-full" />
    </div>
  );
}

function VersionList({
  history,
  currentVersionId,
  onSelect,
}: {
  history: HistoryEntry[];
  currentVersionId: string;
  onSelect: (versionId: string) => void;
}) {
  return (
    <section aria-labelledby="modal-versions-heading" className="space-y-2">
      <h3 id="modal-versions-heading" className="type-label">
        Versions
      </h3>
      <ol className="flex flex-col divide-y rounded-lg border">
        {history.map((entry) => (
          <li
            key={entry.versionId}
            className="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2"
          >
            <span className="type-body w-8 font-medium tabular-nums">
              v{entry.version}
            </span>
            <QuestionStatusBadges
              reviewState={entry.reviewState}
              isLive={entry.isLive}
              questionStatus="draft"
            />
            <span className="type-helper min-w-0 flex-1 truncate text-muted-foreground">
              {entry.authorEmail ?? "Loaded by script"}
            </span>
            <time
              dateTime={entry.updatedAt}
              className="type-helper text-muted-foreground tabular-nums"
            >
              {formatUtc(entry.updatedAt)}
            </time>
            {entry.versionId === currentVersionId ? (
              <Badge variant="outline">Viewing</Badge>
            ) : (
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => onSelect(entry.versionId)}
              >
                View
              </Button>
            )}
          </li>
        ))}
      </ol>
    </section>
  );
}

function QuestionBody({
  detail,
  history,
  onSelectVersion,
}: {
  detail: QuestionDetail;
  history: HistoryEntry[];
  onSelectVersion: (versionId: string) => void;
}) {
  const openElsewhere = history.find(
    (h) =>
      h.versionId !== detail.versionId && OPEN_STATES.includes(h.reviewState),
  );
  const liveElsewhere = history.find(
    (h) => h.versionId !== detail.versionId && h.isLive,
  );
  const viewingOpen = OPEN_STATES.includes(detail.reviewState);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <QuestionStatusBadges
          reviewState={detail.reviewState}
          isLive={detail.isLive}
          questionStatus={detail.questionStatus}
        />
        {detail.difficulty ? (
          <Badge variant="outline">
            {DIFFICULTY_LABELS[detail.difficulty]}
          </Badge>
        ) : null}
        <span className="type-helper text-muted-foreground tabular-nums">
          Version {detail.version}
        </span>
        <Link
          href={`/admin/questions/${detail.versionId}`}
          className={`${buttonVariants({ variant: "ghost", size: "sm" })} ml-auto`}
        >
          Open full page
          <ExternalLinkIcon aria-hidden="true" />
        </Link>
      </div>

      {!viewingOpen && openElsewhere ? (
        <InlineMessage tone="neutral">
          <span className="flex flex-wrap items-center gap-2">
            Version {openElsewhere.version} is{" "}
            {STATE_LABELS[openElsewhere.reviewState].toLowerCase()}.
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => onSelectVersion(openElsewhere.versionId)}
            >
              Show version {openElsewhere.version}
            </Button>
          </span>
        </InlineMessage>
      ) : null}

      {viewingOpen && liveElsewhere ? (
        <InlineMessage tone="neutral">
          <span className="flex flex-wrap items-center gap-2">
            Version {liveElsewhere.version} is the live version.
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => onSelectVersion(liveElsewhere.versionId)}
            >
              Show live version
            </Button>
          </span>
        </InlineMessage>
      ) : null}

      {detail.reviewNote ? (
        <InlineMessage tone="warning">
          <span className="block font-medium">
            {detail.reviewState === "rejected"
              ? "Why it was rejected"
              : "Reviewer's note"}
          </span>
          <span className="block whitespace-pre-wrap wrap-anywhere">
            {detail.reviewNote}
          </span>
        </InlineMessage>
      ) : null}

      <QuestionPreview
        stem={detail.stem}
        options={detail.options}
        correctId={detail.correctOptionId}
        explanation={detail.explanation}
        show="review"
      />

      <dl className="flex flex-col gap-1.5 rounded-lg border bg-muted/30 p-3">
        <Meta label="Author">
          {detail.authorEmail ??
            (detail.reviewState === "imported"
              ? "Loaded by script"
              : "Unknown")}
        </Meta>
        {detail.submittedAt ? (
          <Meta label="Submitted">
            <time dateTime={detail.submittedAt} className="tabular-nums">
              {formatUtc(detail.submittedAt)}
            </time>
          </Meta>
        ) : null}
        {detail.reviewerEmail ? (
          <Meta label="Reviewer">{detail.reviewerEmail}</Meta>
        ) : null}
        {detail.reviewedAt ? (
          <Meta label="Reviewed">
            <time dateTime={detail.reviewedAt} className="tabular-nums">
              {formatUtc(detail.reviewedAt)}
            </time>
          </Meta>
        ) : null}
      </dl>

      {history.length > 1 ? (
        <VersionList
          history={history}
          currentVersionId={detail.versionId}
          onSelect={onSelectVersion}
        />
      ) : null}
    </div>
  );
}

export function ReviewModal({
  title,
  subtitle,
  items,
  role,
  closeHref,
  truncated,
}: {
  title: string;
  subtitle: string;
  items: ReviewItem[];
  role: QuestionRole;
  closeHref: string;
  truncated: boolean;
}) {
  const router = useRouter();
  const [index, setIndex] = useState(0);
  const [override, setOverride] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const position = Math.min(index, Math.max(items.length - 1, 0));
  const item = items[position];
  const versionId = override ?? item?.versionId ?? null;
  const questionId = item?.questionId ?? null;
  const key = versionId ? `${versionId}:${attempt}` : null;

  useEffect(() => {
    if (!versionId || !questionId || !key) return;
    let cancelled = false;
    loadReviewQuestion(versionId, questionId)
      .then((result) => {
        if (!cancelled) setLoaded({ key, result });
      })
      .catch(() => {
        if (!cancelled) {
          setLoaded({
            key,
            result: { ok: false, message: "The question could not be loaded." },
          });
        }
      });
    return () => {
      cancelled = true;
    };
  }, [versionId, questionId, key]);

  const current = loaded && loaded.key === key ? loaded.result : null;
  const detail = current?.ok ? current.detail : null;

  const intents = detail ? allowedIntents(role, detail) : [];
  const showEdit = detail ? canEdit(role, detail) : false;
  const showNewVersion = detail ? canStartNewVersion(role, detail) : false;
  const ownNote = detail ? mustBeReviewedByOthers(role, detail) : false;
  const hasTools = intents.length > 0 || showEdit || showNewVersion;

  function close() {
    router.replace(closeHref, { scroll: false });
  }

  function go(next: number) {
    if (next < 0 || next >= items.length) return;
    setIndex(next);
    setOverride(null);
    setNotice(null);
  }

  function selectVersion(next: string) {
    setOverride(next === item?.versionId ? null : next);
  }

  function onActionSuccess(intent: QuestionIntent, message: string) {
    setNotice(message);
    if (intent === "discard") {
      setLoaded(null);
    } else {
      setAttempt((n) => n + 1);
    }
  }

  function onActionFailure() {
    setAttempt((n) => n + 1);
  }

  let body: ReactNode;
  if (items.length === 0) {
    body = (
      <InlineMessage tone="neutral">
        No questions in this topic match this filter.
      </InlineMessage>
    );
  } else if (!current) {
    body = <BodySkeleton />;
  } else if (!current.ok) {
    body = (
      <div className="flex flex-col items-start gap-3">
        <InlineMessage tone="error" role="alert">
          {current.message}
        </InlineMessage>
        <Button
          type="button"
          variant="outline"
          onClick={() => setAttempt((n) => n + 1)}
        >
          Try again
        </Button>
      </div>
    );
  } else {
    body = (
      <QuestionBody
        detail={current.detail}
        history={current.history}
        onSelectVersion={selectVersion}
      />
    );
  }

  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open) close();
      }}
    >
      <DialogContent className="flex max-h-[calc(100dvh-2rem)] flex-col gap-0 overflow-hidden p-0 sm:max-w-4xl">
        <DialogHeader className="border-b p-4 pr-12">
          <DialogTitle className="wrap-break-word">{title}</DialogTitle>
          <DialogDescription>{subtitle}</DialogDescription>
        </DialogHeader>

        {detail && (hasTools || ownNote) ? (
          <div className="flex flex-col gap-2 border-b px-4 py-3">
            {hasTools ? (
              <div className="flex flex-wrap items-start gap-2">
                {showEdit ? (
                  <Link
                    href={`/admin/questions/${detail.versionId}/edit`}
                    className={TOOL_LINK}
                  >
                    Edit
                  </Link>
                ) : null}
                {showNewVersion ? (
                  <Link
                    href={`/admin/questions/${detail.versionId}/new-version`}
                    className={TOOL_LINK}
                  >
                    New version
                  </Link>
                ) : null}
                {intents.length > 0 ? (
                  <WorkflowActions
                    versionId={detail.versionId}
                    questionId={detail.questionId}
                    allowed={intents}
                    after="stay"
                    onSuccess={onActionSuccess}
                    onFailure={onActionFailure}
                  />
                ) : null}
              </div>
            ) : null}
            {ownNote ? (
              <InlineMessage tone="neutral">
                You wrote this version, so another reviewer has to approve or
                reject it.
              </InlineMessage>
            ) : null}
          </div>
        ) : null}

        {notice ? (
          <div className="border-b px-4 py-3">
            <InlineMessage tone="success" role="status">
              {notice}
            </InlineMessage>
          </div>
        ) : null}

        <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-4">
          {truncated ? (
            <InlineMessage tone="warning">
              This topic has more questions than can be loaded at once, so only
              the first 1,000 are shown.
            </InlineMessage>
          ) : null}
          {body}
        </div>

        <div className="flex items-center justify-between gap-3 border-t bg-muted/50 p-4">
          {items.length === 0 ? (
            <Button type="button" variant="outline" size="lg" onClick={close}>
              Close
            </Button>
          ) : (
            <>
              <Button
                type="button"
                variant="outline"
                size="lg"
                onClick={() => go(position - 1)}
                disabled={position === 0}
              >
                <ChevronLeftIcon aria-hidden="true" />
                Previous
              </Button>
              <p
                aria-live="polite"
                aria-atomic="true"
                className="type-body font-medium tabular-nums"
              >
                {position + 1} of {items.length}
              </p>
              <Button
                type="button"
                size="lg"
                onClick={() => go(position + 1)}
                disabled={position === items.length - 1}
              >
                Next
                <ChevronRightIcon aria-hidden="true" />
              </Button>
            </>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
