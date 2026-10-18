import { Badge } from "@/components/ui/badge";

import { STATE_LABELS } from "./helpers";
import type { QuestionStatus, ReviewState } from "./types";

const STATE_STYLES: Record<ReviewState, string> = {
  imported: "border-border bg-transparent text-muted-foreground",
  draft: "bg-secondary text-secondary-foreground",
  submitted: "bg-info-muted text-info-muted-foreground",
  approved: "bg-success-muted text-success-muted-foreground",
  rejected: "bg-destructive-muted text-destructive-muted-foreground",
};

export function QuestionStatusBadges({
  reviewState,
  isLive,
  questionStatus,
}: {
  reviewState: ReviewState;
  isLive: boolean;
  questionStatus: QuestionStatus;
}) {
  return (
    <div className="flex flex-wrap gap-1">
      <Badge
        variant="secondary"
        className={`gap-1.5 ${STATE_STYLES[reviewState]}`}
      >
        <span aria-hidden="true" className="size-1.5 rounded-full bg-current" />
        {STATE_LABELS[reviewState]}
      </Badge>
      {isLive ? <Badge>Live</Badge> : null}
      {questionStatus === "retired" ? (
        <Badge variant="destructive">Retired</Badge>
      ) : null}
    </div>
  );
}
