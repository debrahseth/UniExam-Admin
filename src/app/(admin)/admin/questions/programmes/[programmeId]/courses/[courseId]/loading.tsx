import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export default function CourseTopicsLoading() {
  return (
    <div role="status" aria-label="Loading topics" className="space-y-6">
      <Skeleton className="h-8 w-36" />
      <div className="space-y-2">
        <Skeleton className="h-8 w-72 max-w-full" />
        <Skeleton className="h-4 w-48" />
      </div>
      <Skeleton className="h-4 w-56" />
      <Skeleton className="h-10 w-full max-w-md rounded-lg" />
      <div className="space-y-3">
        <Skeleton className="h-6 w-24" />
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {Array.from({ length: 6 }, (_, i) => (
            <Card key={i} className="[--card-spacing:--spacing(5)]">
              <CardHeader>
                <div className="flex items-start gap-3">
                  <Skeleton className="size-9 rounded-lg" />
                  <Skeleton className="h-5 w-2/3" />
                </div>
              </CardHeader>
              <CardContent className="space-y-3">
                <Skeleton className="h-4 w-24" />
                <div className="flex gap-1.5">
                  <Skeleton className="h-5 w-16 rounded-full" />
                  <Skeleton className="h-5 w-16 rounded-full" />
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}
