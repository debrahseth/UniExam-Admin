"use client";

import { ArrowRightIcon, EyeIcon, ScrollTextIcon } from "lucide-react";
import { useState, type ReactNode } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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

function ChangeLabel({ row }: { row: AuditRow }) {
  return (
    <span className="inline-flex flex-wrap items-center gap-x-1.5 gap-y-0.5">
      <StateLabel state={row.before} />
      <ArrowRightIcon
        aria-hidden="true"
        className="size-3.5 shrink-0 text-muted-foreground"
      />
      <span className="sr-only">changed to</span>
      <StateLabel state={row.after} />
    </span>
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

function DetailRow({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="grid gap-0.5 sm:grid-cols-[6.5rem_1fr] sm:gap-x-4">
      <dt className="type-body text-muted-foreground">{label}</dt>
      <dd className="type-body min-w-0">{children}</dd>
    </div>
  );
}

function PersonDetail({ person }: { person: Person }) {
  return (
    <div className="flex flex-col gap-0.5">
      {person.known ? (
        <span className="break-all">{person.label}</span>
      ) : (
        <span className="text-muted-foreground">Email not available</span>
      )}
      <span className="font-mono text-xs break-all text-muted-foreground select-all">
        {person.id}
      </span>
    </div>
  );
}

function EntryDetails({ row }: { row: AuditRow }) {
  return (
    <>
      <DialogHeader>
        <DialogTitle className="pr-8">{actionLabel(row.action)}</DialogTitle>
        <DialogDescription>Entry {row.id} · Times are UTC.</DialogDescription>
      </DialogHeader>

      <dl className="flex flex-col gap-3">
        <DetailRow label="When">
          <time dateTime={row.occurredAt} className="tabular-nums">
            {formatUtc(row.occurredAt)}
          </time>
        </DetailRow>
        <DetailRow label="Action code">
          <code className="font-mono text-xs break-all">{row.action}</code>
        </DetailRow>
        <DetailRow label="By">
          {row.actor ? (
            <PersonDetail person={row.actor} />
          ) : (
            <span className="text-muted-foreground">Database operator</span>
          )}
        </DetailRow>
        <DetailRow label="Account">
          <PersonDetail person={row.target} />
        </DetailRow>
        <DetailRow label="Change">
          <ChangeLabel row={row} />
        </DetailRow>
        <DetailRow label="Reason">
          <div className="max-h-48 overflow-y-auto rounded-lg border bg-muted/30 p-3 whitespace-pre-wrap wrap-anywhere">
            {row.reason}
          </div>
        </DetailRow>
      </dl>

      <DialogFooter showCloseButton />
    </>
  );
}

export function AuditLogTable({ rows }: { rows: AuditRow[] }) {
  const [selected, setSelected] = useState<AuditRow | null>(null);

  if (rows.length === 0) return <EmptyState />;

  return (
    <>
      <div className="overflow-hidden rounded-lg border contain-[inline-size]">
        <Table>
          <TableCaption className="sr-only">
            Changes to administrator access, newest first. Times are UTC. Select
            a row, or its View details button, to see the full entry.
          </TableCaption>
          <TableHeader className="bg-muted/40">
            <TableRow className="hover:bg-transparent">
              <TableHead className={HEAD}>When</TableHead>
              <TableHead className={HEAD}>Action</TableHead>
              <TableHead className={HEAD}>By</TableHead>
              <TableHead className={HEAD}>Account</TableHead>
              <TableHead className={HEAD}>Change</TableHead>
              <TableHead className={HEAD}>Reason</TableHead>
              <TableHead className="h-9 w-14 px-3">
                <span className="sr-only">Details</span>
              </TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => (
              <TableRow
                key={row.id}
                className="cursor-pointer"
                onClick={() => {
                  if (window.getSelection()?.toString()) return;
                  setSelected(row);
                }}
              >
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
                  <ChangeLabel row={row} />
                </TableCell>
                <TableCell className={CELL}>
                  <span className="block max-w-56 truncate">{row.reason}</span>
                </TableCell>
                <TableCell className="px-3 py-2 text-right align-top">
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    aria-haspopup="dialog"
                    aria-label={`View details for entry ${row.id}`}
                    onClick={(event) => {
                      event.stopPropagation();
                      setSelected(row);
                    }}
                  >
                    <EyeIcon />
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      <Dialog
        open={selected !== null}
        onOpenChange={(open) => {
          if (!open) setSelected(null);
        }}
      >
        <DialogContent className="max-h-[calc(100svh-2rem)] overflow-y-auto sm:max-w-5xl">
          {selected ? <EntryDetails row={selected} /> : null}
        </DialogContent>
      </Dialog>
    </>
  );
}
