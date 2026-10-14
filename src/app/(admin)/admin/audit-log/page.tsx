import type { Metadata } from "next";
import { ScrollTextIcon } from "lucide-react";

import { ForbiddenState } from "@/components/shell/forbidden-state";
import { PageHeader } from "@/components/shell/page-header";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getAdminContext } from "@/lib/admin-access";

import { InlineMessage } from "@/features/access/inline-message";
import { AuditLogTable } from "@/features/audit-logs/audit-log-table";
import { AuditPagination } from "@/features/audit-logs/audit-pagination";
import { loadAuditPage } from "@/features/audit-logs/data";
import { parseBefore } from "@/features/audit-logs/parse";

export const metadata: Metadata = { title: "Audit log" };

export default async function AuditLogPage({
  searchParams,
}: {
  searchParams: Promise<{ before?: string | string[] }>;
}) {
  const { access } = await getAdminContext();
  if (access.state !== "active" || access.role !== "super_admin") {
    return <ForbiddenState />;
  }

  const before = parseBefore((await searchParams).before);
  const result = await loadAuditPage(before);

  if (result.status === "error") {
    return (
      <div className="space-y-6">
        <PageHeader
          title="Audit log"
          description="A record of every change to administrator access."
        />
        <InlineMessage tone="error" role="alert">
          The audit log could not be loaded. Reload the page. If this keeps
          happening, sign out and sign in again.
        </InlineMessage>
      </div>
    );
  }

  const { rows, skipped, nextBefore } = result;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Audit log"
        description="A record of every change to administrator access. Entries cannot be edited or deleted."
      />

      <Card className="[--card-spacing:--spacing(5)]">
        <CardHeader>
          <CardTitle className="type-card-title flex items-center gap-2">
            <ScrollTextIcon
              aria-hidden="true"
              className="size-4 text-primary"
            />
            Access changes
          </CardTitle>
          <CardDescription className="max-w-prose">
            Newest first. Times are UTC. Accounts without a known email show a
            short ID.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {skipped > 0 ? (
            <InlineMessage tone="error" role="alert">
              {skipped} {skipped === 1 ? "entry" : "entries"} on this page could
              not be displayed. Check the log in the database.
            </InlineMessage>
          ) : null}

          <AuditLogTable rows={rows} />

          <AuditPagination
            count={rows.length}
            showBack={before !== null}
            nextBefore={nextBefore}
          />
        </CardContent>
      </Card>
    </div>
  );
}
