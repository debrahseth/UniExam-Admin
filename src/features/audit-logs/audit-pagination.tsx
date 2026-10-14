import { ChevronLeftIcon, ChevronRightIcon } from "lucide-react";
import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";

type AuditPaginationProps = {
  count: number;
  showBack: boolean;
  nextBefore: number | null;
};

export function AuditPagination({
  count,
  showBack,
  nextBefore,
}: AuditPaginationProps) {
  return (
    <nav
      aria-label="Audit log pages"
      className="flex flex-wrap items-center justify-between gap-3"
    >
      <p className="type-helper text-muted-foreground tabular-nums">
        {count} {count === 1 ? "entry" : "entries"} on this page
      </p>
      <div className="flex flex-wrap items-center gap-2">
        {showBack ? (
          <Link
            href="/admin/audit-log"
            className={buttonVariants({ variant: "outline" })}
          >
            <ChevronLeftIcon aria-hidden="true" />
            Back to newest
          </Link>
        ) : null}
        {nextBefore !== null ? (
          <Link
            href={`/admin/audit-log?before=${nextBefore}`}
            className={buttonVariants({ variant: "outline" })}
          >
            Older entries
            <ChevronRightIcon aria-hidden="true" />
          </Link>
        ) : null}
      </div>
    </nav>
  );
}
