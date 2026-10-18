import { HistoryIcon } from "lucide-react";
import Link from "next/link";

import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { formatUtc } from "@/lib/format";

import type { HistoryEntry } from "./search";
import { QuestionStatusBadges } from "./status-badge";

export function VersionHistory({
  entries,
  currentVersionId,
}: {
  entries: HistoryEntry[];
  currentVersionId: string;
}) {
  return (
    <Card className="[--card-spacing:--spacing(5)]">
      <CardHeader>
        <CardTitle className="type-card-title flex items-center gap-2">
          <HistoryIcon aria-hidden="true" className="size-4 text-primary" />
          Versions
        </CardTitle>
        <CardDescription>
          Every version of this question, newest first. Times are UTC.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ol className="flex flex-col divide-y rounded-lg border">
          {entries.map((entry) => {
            const current = entry.versionId === currentVersionId;
            return (
              <li
                key={entry.versionId}
                className="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2.5"
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
                {current ? (
                  <Badge variant="outline">Viewing</Badge>
                ) : (
                  <Link
                    href={`/admin/questions/${entry.versionId}`}
                    className="type-helper underline underline-offset-4"
                  >
                    Open
                  </Link>
                )}
              </li>
            );
          })}
        </ol>
      </CardContent>
    </Card>
  );
}
