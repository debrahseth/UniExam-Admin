"use client";

import { SearchIcon, XIcon } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

import { ProgrammeCard } from "./programme-card";
import type { Programme } from "./programmes";

const SEARCH_THRESHOLD = 6;

function Group({
  id,
  title,
  programmes,
}: {
  id: string;
  title: string;
  programmes: Programme[];
}) {
  if (programmes.length === 0) return null;

  return (
    <section aria-labelledby={id} className="space-y-3">
      <h2 id={id} className="type-section-title">
        {title}
        <span className="type-body ml-2 font-normal text-muted-foreground tabular-nums">
          {programmes.length}
        </span>
      </h2>
      <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {programmes.map((programme) => (
          <li key={programme.id}>
            <ProgrammeCard programme={programme} />
          </li>
        ))}
      </ul>
    </section>
  );
}

export function ProgrammeBrowser({ programmes }: { programmes: Programme[] }) {
  const [query, setQuery] = useState("");
  const showSearch = programmes.length > SEARCH_THRESHOLD;

  const needle = query.trim().toLowerCase();
  const visible = needle
    ? programmes.filter(
        (p) =>
          p.name.toLowerCase().includes(needle) ||
          p.code.toLowerCase().includes(needle),
      )
    : programmes;

  const active = visible.filter((p) => p.isActive);
  const inactive = visible.filter((p) => !p.isActive);

  return (
    <div className="space-y-8">
      {showSearch ? (
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div className="relative w-full sm:max-w-sm">
            <SearchIcon
              aria-hidden="true"
              className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
            />
            <Input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              aria-label="Search programmes"
              placeholder="Search by name or code"
              autoComplete="off"
              maxLength={100}
              className="h-9 pl-9"
            />
          </div>
          <p
            aria-live="polite"
            className="type-helper text-muted-foreground tabular-nums"
          >
            {needle
              ? `${visible.length} of ${programmes.length} programmes`
              : `${programmes.length} programmes`}
          </p>
        </div>
      ) : null}

      {visible.length === 0 ? (
        <div className="flex flex-col items-center gap-3 rounded-lg border border-dashed px-4 py-10 text-center">
          <SearchIcon
            aria-hidden="true"
            className="size-5 text-muted-foreground"
          />
          <p className="type-body text-muted-foreground">
            No programmes match your search.
          </p>
          <Button variant="outline" onClick={() => setQuery("")}>
            <XIcon aria-hidden="true" />
            Clear search
          </Button>
        </div>
      ) : (
        <>
          <Group
            id="programmes-active"
            title="Programmes"
            programmes={active}
          />
          <Group
            id="programmes-inactive"
            title="Inactive programmes"
            programmes={inactive}
          />
        </>
      )}
    </div>
  );
}
