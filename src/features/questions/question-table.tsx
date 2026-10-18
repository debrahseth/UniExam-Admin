import Link from "next/link";

import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatUtc } from "@/lib/format";

import { DIFFICULTY_LABELS } from "./helpers";
import type { ListItem, ListView } from "./search";
import { QuestionStatusBadges } from "./status-badge";

const HEAD = "type-meta h-9 px-3 text-muted-foreground";
const CELL = "type-table px-3 py-3 align-top";

function targetVersion(item: ListItem, view: ListView): string {
  if ((view === "needs_review" || view === "mine") && item.openVersionId) {
    return item.openVersionId;
  }
  return item.liveVersionId ?? item.currentVersionId;
}

export function QuestionTable({
  items,
  view,
}: {
  items: ListItem[];
  view: ListView;
}) {
  const timeLabel = view === "needs_review" ? "Submitted" : "Updated";

  return (
    <div className="overflow-hidden rounded-lg border contain-[inline-size]">
      <Table>
        <TableCaption className="sr-only">
          Questions, one row each.{" "}
          {view === "needs_review"
            ? "Oldest submission first."
            : "Newest activity first."}{" "}
          Times are UTC.
        </TableCaption>
        <TableHeader className="bg-muted/40">
          <TableRow className="hover:bg-transparent">
            <TableHead className={HEAD}>Question</TableHead>
            <TableHead className={HEAD}>Status</TableHead>
            <TableHead className={HEAD}>Difficulty</TableHead>
            <TableHead className={HEAD}>{timeLabel}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {items.map((item) => (
            <TableRow key={item.questionId}>
              <TableCell
                className={`${CELL} max-w-md min-w-64 whitespace-normal`}
              >
                <Link
                  href={`/admin/questions/${targetVersion(item, view)}`}
                  title={item.stem}
                  className="line-clamp-2 font-medium underline-offset-4 wrap-anywhere hover:underline"
                >
                  {item.stem || "(no question text)"}
                </Link>
                <p className="type-helper mt-1 text-muted-foreground">
                  {item.courseCode} · {item.topicTitle ?? "No topic"}
                </p>
              </TableCell>

              <TableCell className={CELL}>
                <div className="flex flex-col items-start gap-1.5">
                  <div className="flex flex-wrap gap-1">
                    {item.isLive ? (
                      <Badge>
                        Live{item.liveVersion ? ` v${item.liveVersion}` : ""}
                      </Badge>
                    ) : null}
                    {item.isRetired ? (
                      <Badge variant="destructive">Retired</Badge>
                    ) : null}
                    {!item.isLive && !item.isRetired ? (
                      <Badge variant="outline">Not published</Badge>
                    ) : null}
                    {item.currentIsImported ? (
                      <Badge variant="outline">Imported</Badge>
                    ) : null}
                  </div>

                  {item.openVersionId && item.openState ? (
                    <div className="flex flex-col gap-0.5">
                      <Link
                        href={`/admin/questions/${item.openVersionId}`}
                        className="inline-flex items-center gap-1.5 underline-offset-4 hover:underline"
                      >
                        <span className="type-helper text-muted-foreground tabular-nums">
                          v{item.openVersion}
                        </span>
                        <QuestionStatusBadges
                          reviewState={item.openState}
                          isLive={false}
                          questionStatus="draft"
                        />
                      </Link>
                      {item.openAuthorEmail ? (
                        <span className="type-helper block max-w-48 truncate text-muted-foreground">
                          by {item.openAuthorEmail}
                        </span>
                      ) : null}
                    </div>
                  ) : null}
                </div>
              </TableCell>

              <TableCell
                className={`${CELL} ${item.difficulty ? "" : "text-muted-foreground"}`}
              >
                {item.difficulty
                  ? DIFFICULTY_LABELS[item.difficulty]
                  : "Not set"}
              </TableCell>

              <TableCell
                className={`${CELL} text-muted-foreground tabular-nums`}
              >
                {formatUtc(
                  view === "needs_review" && item.openSubmittedAt
                    ? item.openSubmittedAt
                    : item.sortAt,
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
