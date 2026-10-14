import {
  CardTitleSkeleton,
  PageHeaderSkeleton,
  SkeletonLine,
  TableSkeleton,
} from "@/components/shell/page-skeletons";
import {
  Card,
  CardAction,
  CardContent,
  CardHeader,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export default function AccessLoading() {
  return (
    <div className="space-y-6" role="status" aria-label="Loading admin access">
      <PageHeaderSkeleton />

      <Card className="[--card-spacing:--spacing(5)]">
        <CardHeader>
          <CardTitleSkeleton width="w-44" />
          <div>
            <SkeletonLine className="w-full max-w-prose" />
            <SkeletonLine className="w-full max-w-prose" />
            <SkeletonLine className="w-1/2 max-w-xs" />
          </div>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div className="flex flex-1 flex-col gap-2">
              <div className="flex h-5 items-center">
                <Skeleton className="h-3.5 w-24" />
              </div>
              <Skeleton className="h-9 w-full" />
            </div>
            <Skeleton className="h-9 w-full sm:w-28" />
          </div>
        </CardContent>
      </Card>

      <Card className="[--card-spacing:--spacing(5)]">
        <CardHeader>
          <CardTitleSkeleton width="w-32" />
          <SkeletonLine className="w-64 max-w-full" />
          <CardAction>
            <Skeleton className="h-3 w-14" />
          </CardAction>
        </CardHeader>
        <CardContent>
          <TableSkeleton
            rows={5}
            columns={[
              { head: "w-12", cell: "h-4 w-44" },
              { head: "w-10", cell: "h-4 w-24" },
              { head: "w-12", cell: "h-5 w-20 rounded-full" },
              { head: "w-12", cell: "h-4 w-36" },
              { head: null, cell: "ml-auto size-8" },
            ]}
          />
        </CardContent>
      </Card>
    </div>
  );
}
