"use client";

import { LoaderCircleIcon } from "lucide-react";
import { useState, useTransition, type FormEvent } from "react";

import { TextArea } from "@/components/shell/form-fields";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { InlineMessage } from "@/features/access/inline-message";

import { runQuestionAction } from "./actions";
import type { QuestionIntent } from "./types";

type Copy = {
  button: string;
  title: string;
  description: string;
  confirm: string;
  reason: boolean;
  variant: "default" | "destructive" | "outline";
};

const COPY: Record<QuestionIntent, Copy> = {
  submit: {
    button: "Submit for review",
    title: "Submit for review",
    description:
      "A reviewer will approve or reject this version. You can't edit it while it is in review.",
    confirm: "Submit",
    reason: false,
    variant: "default",
  },
  discard: {
    button: "Discard draft",
    title: "Discard this draft",
    description:
      "The draft is deleted permanently. Published versions are never affected.",
    confirm: "Discard",
    reason: false,
    variant: "destructive",
  },
  approve: {
    button: "Approve and publish",
    title: "Approve and publish",
    description:
      "This version becomes the live version and students will see it in new exams. Exams already in progress are not affected.",
    confirm: "Approve and publish",
    reason: false,
    variant: "default",
  },
  reject: {
    button: "Reject",
    title: "Reject this version",
    description:
      "The author will see your reason and can edit and resubmit. The reason is saved in the activity log.",
    confirm: "Reject",
    reason: true,
    variant: "destructive",
  },
  retire: {
    button: "Retire question",
    title: "Retire this question",
    description:
      "Students stop seeing this question in new exams. Exams already in progress are not affected. You can restore it later. The reason is saved in the activity log.",
    confirm: "Retire",
    reason: true,
    variant: "destructive",
  },
  restore: {
    button: "Restore question",
    title: "Restore this question",
    description:
      "The question returns to its last published version and is served in new exams again. The reason is saved in the activity log.",
    confirm: "Restore",
    reason: true,
    variant: "outline",
  },
};

function ConfirmForm({
  intent,
  versionId,
  questionId,
  onDone,
}: {
  intent: QuestionIntent;
  versionId: string;
  questionId: string;
  onDone: (message: string) => void;
}) {
  const copy = COPY[intent];
  const [error, setError] = useState<string | null>(null);
  const [busy, startTransition] = useTransition();

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    setError(null);
    startTransition(async () => {
      const result = await runQuestionAction(formData);
      if (result.ok) onDone(result.message);
      else setError(result.message);
    });
  }

  return (
    <form onSubmit={onSubmit} className="grid gap-4" noValidate>
      <DialogHeader>
        <DialogTitle className="pr-8">{copy.title}</DialogTitle>
        <DialogDescription className="leading-relaxed">
          {copy.description}
        </DialogDescription>
      </DialogHeader>

      <input type="hidden" name="intent" value={intent} />
      <input type="hidden" name="version" value={versionId} />
      <input type="hidden" name="question" value={questionId} />

      {copy.reason ? (
        <div className="flex flex-col gap-2">
          <Label htmlFor="workflow-reason" className="type-label">
            Reason
          </Label>
          <TextArea
            id="workflow-reason"
            name="reason"
            minLength={10}
            maxLength={500}
            required
            disabled={busy}
            aria-describedby="workflow-reason-help"
          />
          <p
            id="workflow-reason-help"
            className="type-helper text-muted-foreground"
          >
            10 to 500 characters.
          </p>
        </div>
      ) : null}

      {error ? (
        <InlineMessage tone="error" role="alert">
          {error}
        </InlineMessage>
      ) : null}

      <DialogFooter>
        <DialogClose
          render={<Button type="button" variant="outline" disabled={busy} />}
        >
          Cancel
        </DialogClose>
        <Button
          type="submit"
          variant={copy.variant === "destructive" ? "destructive" : "default"}
          disabled={busy}
          aria-busy={busy}
        >
          {busy ? (
            <LoaderCircleIcon aria-hidden="true" className="animate-spin" />
          ) : null}
          {busy ? "Working…" : copy.confirm}
        </Button>
      </DialogFooter>
    </form>
  );
}

export function WorkflowActions({
  versionId,
  questionId,
  allowed,
}: {
  versionId: string;
  questionId: string;
  allowed: QuestionIntent[];
}) {
  const [active, setActive] = useState<QuestionIntent | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  return (
    <div className="flex flex-col gap-3 sm:items-end">
      <div className="flex flex-wrap gap-2">
        {allowed.map((intent) => (
          <Button
            key={intent}
            type="button"
            size="lg"
            className="px-4"
            variant={COPY[intent].variant}
            onClick={() => {
              setNotice(null);
              setActive(intent);
            }}
          >
            {COPY[intent].button}
          </Button>
        ))}
      </div>

      {notice ? (
        <InlineMessage tone="success" role="status">
          {notice}
        </InlineMessage>
      ) : null}

      <Dialog
        open={active !== null}
        onOpenChange={(open) => {
          if (!open) setActive(null);
        }}
      >
        <DialogContent className="sm:max-w-md">
          {active ? (
            <ConfirmForm
              key={active}
              intent={active}
              versionId={versionId}
              questionId={questionId}
              onDone={(message) => {
                setNotice(message);
                setActive(null);
              }}
            />
          ) : null}
        </DialogContent>
      </Dialog>
    </div>
  );
}
