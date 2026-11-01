import { PageHeaderSkeleton } from "@/components/shell/page-skeletons";
import { Card, CardFooter, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export default function QuestionsLoading() {
  return (
    <div role="status" aria-label="Loading programmes" className="space-y-6">
      <PageHeaderSkeleton />

      <div className="space-y-8">
        <div className="flex items-center justify-between gap-3">
          <Skeleton className="h-9 w-full sm:max-w-sm" />
          <Skeleton className="hidden h-3 w-24 sm:block" />
        </div>

        <div className="space-y-3">
          <Skeleton className="h-6 w-32" />
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {Array.from({ length: 9 }, (_, i) => (
              <Card key={i} className="[--card-spacing:--spacing(5)]">
                <CardHeader>
                  <div className="flex items-start gap-3.5">
                    <Skeleton className="size-10 shrink-0 rounded-lg" />
                    <div className="flex-1 space-y-2.5">
                      <Skeleton className="h-4 w-3/4" />
                      <Skeleton className="h-3 w-16" />
                    </div>
                  </div>
                </CardHeader>
                <CardFooter className="justify-between py-3">
                  <Skeleton className="h-4 w-24" />
                  <Skeleton className="size-4" />
                </CardFooter>
              </Card>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
