import { ArrowRightIcon, ScrollTextIcon } from "lucide-react";

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

import { actionLabel, describeState } from "./labels";
import type { AuditRow, AuditState, Person } from "./types";

const HEAD = "type-meta h-9 px-3 text-muted-foreground";
const CELL = "type-table px-3 py-3 align-top";

function StateLabel({ state }: { state: AuditState | null }) {
  return state ? (
    <span>{describeState(state)}</span>
  ) : (
    <span className="text-muted-foreground">None</span>
  );
}

function PersonName({ person }: { person: Person }) {
  return person.known ? (
    <span className="break-all">{person.label}</span>
  ) : (
    <span className="font-mono text-xs text-muted-foreground">
      {person.label}
    </span>
  );
}

function EmptyState() {
  return (
    <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed px-4 py-10 text-center">
      <ScrollTextIcon
        aria-hidden="true"
        className="size-5 text-muted-foreground"
      />
      <p className="type-body text-muted-foreground">
        There are no entries to show.
      </p>
    </div>
  );
}

export function AuditLogTable({ rows }: { rows: AuditRow[] }) {
  if (rows.length === 0) return <EmptyState />;

  return (
    <div className="overflow-hidden rounded-lg border contain-[inline-size]">
      <Table>
        <TableCaption className="sr-only">
          Changes to administrator access, newest first. Times are UTC.
        </TableCaption>
        <TableHeader className="bg-muted/40">
          <TableRow className="hover:bg-transparent">
            <TableHead className={HEAD}>When</TableHead>
            <TableHead className={HEAD}>Action</TableHead>
            <TableHead className={HEAD}>By</TableHead>
            <TableHead className={HEAD}>Account</TableHead>
            <TableHead className={HEAD}>Change</TableHead>
            <TableHead className={HEAD}>Reason</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => (
            <TableRow key={row.id}>
              <TableCell
                className={`${CELL} text-muted-foreground tabular-nums`}
              >
                <time dateTime={row.occurredAt}>
                  {formatUtc(row.occurredAt)}
                </time>
              </TableCell>
              <TableCell className={CELL}>
                <Badge variant="outline">{actionLabel(row.action)}</Badge>
              </TableCell>
              <TableCell className={CELL}>
                {row.actor ? (
                  <PersonName person={row.actor} />
                ) : (
                  <span className="text-muted-foreground">
                    Database operator
                  </span>
                )}
              </TableCell>
              <TableCell className={CELL}>
                <PersonName person={row.target} />
              </TableCell>
              <TableCell className={`${CELL} min-w-52 whitespace-normal`}>
                <span className="inline-flex flex-wrap items-center gap-x-1.5 gap-y-0.5">
                  <StateLabel state={row.before} />
                  <ArrowRightIcon
                    aria-hidden="true"
                    className="size-3.5 shrink-0 text-muted-foreground"
                  />
                  <span className="sr-only">changed to</span>
                  <StateLabel state={row.after} />
                </span>
              </TableCell>
              <TableCell
                className={`${CELL} max-w-md min-w-56 whitespace-normal`}
              >
                {row.reason}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
