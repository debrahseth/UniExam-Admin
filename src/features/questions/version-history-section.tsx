import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import {
  CardTitleSkeleton,
  SkeletonLine,
} from "@/components/shell/page-skeletons";

import { toHistoryEntry, type HistoryEntry } from "./search";
import { VersionHistory } from "./version-history";

export function VersionHistorySkeleton() {
  return (
    <Card className="[--card-spacing:--spacing(5)]" aria-hidden="true">
      <CardHeader>
        <CardTitleSkeleton width="w-20" />
        <SkeletonLine className="w-72 max-w-full" />
      </CardHeader>
      <CardContent>
        <Skeleton className="h-24 w-full" />
      </CardContent>
    </Card>
  );
}

export async function VersionHistorySection({
  questionId,
  currentVersionId,
}: {
  questionId: string;
  currentVersionId: string;
}) {
  const supabase = await createSupabaseServerClient();
  const result = await supabase.rpc("admin_question_history", {
    p_question_id: questionId,
  });
  const history: HistoryEntry[] = Array.isArray(result.data)
    ? result.data
        .map(toHistoryEntry)
        .filter((e): e is HistoryEntry => e !== null)
    : [];

  return history.length > 1 ? (
    <VersionHistory entries={history} currentVersionId={currentVersionId} />
  ) : null;
}
