import {
  CardTitleSkeleton,
  PageHeaderSkeleton,
  SkeletonLine,
  TableSkeleton,
} from "@/components/shell/page-skeletons";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export default function AuditLogLoading() {
  return (
    <div className="space-y-6" role="status" aria-label="Loading audit log">
      <PageHeaderSkeleton />

      <Card className="[--card-spacing:--spacing(5)]">
        <CardHeader>
          <CardTitleSkeleton width="w-36" />
          <div>
            <SkeletonLine className="w-full max-w-prose" />
            <SkeletonLine className="w-1/3 max-w-xs" />
          </div>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <TableSkeleton
            rows={8}
            cellClassName="px-3 py-3 align-top"
            columns={[
              { head: "w-10", cell: "h-4 w-32" },
              { head: "w-12", cell: "h-5 w-24 rounded-full" },
              { head: "w-8", cell: "h-4 w-36" },
              { head: "w-14", cell: "h-4 w-36" },
              { head: "w-14", cell: "h-4 w-40" },
              { head: "w-14", cell: "h-4 w-52" },
            ]}
          />

          <div className="flex flex-wrap items-center justify-between gap-3">
            <Skeleton className="h-3 w-36" />
            <Skeleton className="h-8 w-32" />
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
