import Link from "next/link";

import { cn } from "@/lib/utils";

import type { ListFilters } from "./list-data";
import {
  VIEW_LABELS,
  buildListHref,
  type ListCounts,
  type ListView,
} from "./search";

type TabsProps = {
  tabs: ListView[];
  view: ListView;
  filters: ListFilters;
};

function Tabs({
  tabs,
  view,
  filters,
  counts,
}: TabsProps & { counts: ListCounts | null }) {
  return (
    <nav
      aria-label="Question views"
      className="flex w-fit max-w-full gap-1 overflow-x-auto rounded-lg bg-muted p-1"
    >
      {tabs.map((key) => {
        const active = key === view;
        const count = counts?.[key];
        return (
          <Link
            key={key}
            href={buildListHref({ view: key, ...filters })}
            aria-current={active ? "page" : undefined}
            className={cn(
              "type-label inline-flex h-8 shrink-0 items-center gap-1.5 rounded-md px-3 whitespace-nowrap transition-colors outline-none focus-visible:ring-3 focus-visible:ring-ring/50",
              active
                ? "bg-background text-foreground shadow-xs"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            {VIEW_LABELS[key]}
            {count !== undefined ? (
              <span className="text-muted-foreground tabular-nums">
                {count}
              </span>
            ) : null}
          </Link>
        );
      })}
    </nav>
  );
}

export function ViewTabsFallback(props: TabsProps) {
  return <Tabs {...props} counts={null} />;
}

export async function ViewTabs({
  countsPromise,
  ...props
}: TabsProps & { countsPromise: Promise<ListCounts | null> }) {
  const counts = await countsPromise;
  return <Tabs {...props} counts={counts} />;
}
