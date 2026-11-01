import Link from "next/link";

import { cn } from "@/lib/utils";

import { FILTER_LABELS, type TopicFilter } from "./filters";

export function TopicFilterTabs({
  filters,
  active,
  basePath,
}: {
  filters: TopicFilter[];
  active: TopicFilter;
  basePath: string;
}) {
  return (
    <nav
      aria-label="Filter questions"
      className="flex w-fit max-w-full gap-1 overflow-x-auto rounded-lg bg-muted p-1"
    >
      {filters.map((filter) => {
        const isActive = filter === active;
        return (
          <Link
            key={filter}
            href={filter === "all" ? basePath : `${basePath}?filter=${filter}`}
            aria-current={isActive ? "page" : undefined}
            className={cn(
              "type-label inline-flex h-8 shrink-0 items-center rounded-md px-3 whitespace-nowrap transition-colors outline-none focus-visible:ring-3 focus-visible:ring-ring/50",
              isActive
                ? "bg-background text-foreground shadow-xs"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            {FILTER_LABELS[filter]}
          </Link>
        );
      })}
    </nav>
  );
}
