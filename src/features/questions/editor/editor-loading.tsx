import {
  CardTitleSkeleton,
  PageHeaderSkeleton,
  SkeletonLine,
} from "@/components/shell/page-skeletons";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

function SkeletonCard({
  children,
  grid = false,
}: {
  children: React.ReactNode;
  grid?: boolean;
}) {
  return (
    <Card className="[--card-spacing:--spacing(5)]">
      <CardHeader>
        <CardTitleSkeleton width="w-32" />
        <SkeletonLine className="w-72 max-w-full" />
      </CardHeader>
      <CardContent
        className={grid ? "grid gap-4 sm:grid-cols-2" : "flex flex-col gap-3"}
      >
        {children}
      </CardContent>
    </Card>
  );
}

export function EditorLoading() {
  return (
    <div className="space-y-6" role="status" aria-label="Loading editor">
      <Skeleton className="h-7 w-40" />
      <PageHeaderSkeleton />

      <SkeletonCard grid>
        {[0, 1, 2].map((i) => (
          <div key={i} className="flex flex-col gap-2">
            <Skeleton className="h-4 w-20" />
            <Skeleton className="h-9 w-full" />
          </div>
        ))}
      </SkeletonCard>
      <SkeletonCard>
        <Skeleton className="h-24 w-full" />
      </SkeletonCard>
      <SkeletonCard>
        {[0, 1, 2].map((i) => (
          <Skeleton key={i} className="h-12 w-full" />
        ))}
      </SkeletonCard>
      <SkeletonCard>
        <Skeleton className="h-24 w-full" />
      </SkeletonCard>
    </div>
  );
}
