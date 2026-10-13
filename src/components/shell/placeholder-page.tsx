import type { LucideIcon } from "lucide-react";

import { PageHeader } from "@/components/shell/page-header";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

type PlaceholderPageProps = {
  title: string;
  description: string;
  icon: LucideIcon;
  /** Where this area is planned, e.g. "Milestone 1B" or "a later milestone". */
  planned: string;
};

export function PlaceholderPage({
  title,
  description,
  icon: Icon,
  planned,
}: PlaceholderPageProps) {
  return (
    <div className="space-y-6">
      <PageHeader title={title} description={description} />
      <Card>
        <CardHeader>
          <div className="flex items-center gap-3">
            <div className="bg-muted text-muted-foreground flex size-9 items-center justify-center rounded-md">
              <Icon className="size-5" aria-hidden="true" />
            </div>
            <div className="space-y-1">
              <CardTitle className="type-card-title">Not implemented</CardTitle>
              <CardDescription>Planned for {planned}.</CardDescription>
            </div>
            <Badge variant="outline" className="ml-auto">
              Preview
            </Badge>
          </div>
        </CardHeader>
        <CardContent className="type-body text-muted-foreground">
          This page is a placeholder. It reads no data and performs no actions.
        </CardContent>
      </Card>
    </div>
  );
}
