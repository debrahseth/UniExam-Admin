import {
  CardTitleSkeleton,
  PageHeaderSkeleton,
  SkeletonLine,
} from "@/components/shell/page-skeletons";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

function SkeletonCard({
  children,
  title = "w-24",
}: {
  children: React.ReactNode;
  title?: string;
}) {
  return (
    <Card className="[--card-spacing:--spacing(5)]">
      <CardHeader>
        <CardTitleSkeleton width={title} />
        <SkeletonLine className="w-40" />
      </CardHeader>
      <CardContent className="flex flex-col gap-3">{children}</CardContent>
    </Card>
  );
}

export default function QuestionDetailLoading() {
  return (
    <div className="space-y-6" role="status" aria-label="Loading question">
      <Skeleton className="h-7 w-40" />
      <PageHeaderSkeleton />
      <div className="flex gap-2">
        <Skeleton className="h-5 w-20 rounded-full" />
        <Skeleton className="h-5 w-16 rounded-full" />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <SkeletonCard>
          {[0, 1, 2, 3].map((i) => (
            <SkeletonLine key={i} className="w-3/4" />
          ))}
        </SkeletonCard>
        <SkeletonCard title="w-28">
          <Skeleton className="h-11 w-full" />
        </SkeletonCard>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        {[0, 1].map((card) => (
          <SkeletonCard key={card} title="w-36">
            <Skeleton className="h-6 w-5/6" />
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-12 w-full" />
            ))}
          </SkeletonCard>
        ))}
      </div>
    </div>
  );
}
