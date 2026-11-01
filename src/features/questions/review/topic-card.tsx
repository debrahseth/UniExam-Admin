import { ChevronRightIcon, ClipboardListIcon, ClockIcon } from "lucide-react";
import Link from "next/link";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

import type { TopicCardData } from "./topics";

function CountChip({
  label,
  count,
  className,
}: {
  label: string;
  count: number;
  className: string;
}) {
  return (
    <Badge variant="secondary" className={cn("gap-1 tabular-nums", className)}>
      {label}
      <span className="font-semibold">{count}</span>
    </Badge>
  );
}

export function TopicCard({
  topic,
  href,
}: {
  topic: TopicCardData;
  href: string | null;
}) {
  const { id, title, total, live, draft, retired, waiting } = topic;

  const card = (
    <Card
      className={cn(
        "h-full [--card-spacing:--spacing(5)] transition-colors",
        href && "group-hover:ring-foreground/25",
      )}
    >
      <CardHeader>
        <div className="flex items-start gap-3">
          <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <ClipboardListIcon aria-hidden="true" className="size-5" />
          </div>
          <div className="min-w-0 flex-1 space-y-1">
            <CardTitle className="type-card-title wrap-break-word">
              {title}
            </CardTitle>
            {id === null ? (
              <p className="type-helper text-muted-foreground">
                Not assigned to a topic
              </p>
            ) : null}
          </div>
          {href ? (
            <ChevronRightIcon
              aria-hidden="true"
              className="mt-1 size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5"
            />
          ) : null}
        </div>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <p className={cn("type-body", total === 0 && "text-muted-foreground")}>
          {total === 0
            ? "No questions"
            : `${total} ${total === 1 ? "question" : "questions"}`}
        </p>

        {total > 0 ? (
          <div className="flex flex-wrap gap-1.5">
            {live > 0 ? (
              <CountChip
                label="Live"
                count={live}
                className="bg-success-muted text-success-muted-foreground"
              />
            ) : null}
            {draft > 0 ? (
              <CountChip
                label="Draft"
                count={draft}
                className="bg-secondary text-secondary-foreground"
              />
            ) : null}
            {retired > 0 ? (
              <CountChip
                label="Retired"
                count={retired}
                className="bg-destructive-muted text-destructive-muted-foreground"
              />
            ) : null}
            {waiting > 0 ? (
              <Badge
                variant="secondary"
                className="gap-1 bg-info-muted text-info-muted-foreground tabular-nums"
              >
                <ClockIcon aria-hidden="true" className="size-3" />
                Waiting for review
                <span className="font-semibold">{waiting}</span>
              </Badge>
            ) : null}
          </div>
        ) : null}
      </CardContent>
    </Card>
  );

  if (!href) return <div className="h-full">{card}</div>;

  return (
    <Link
      href={href}
      scroll={false}
      className="group block h-full rounded-xl outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
    >
      {card}
    </Link>
  );
}
