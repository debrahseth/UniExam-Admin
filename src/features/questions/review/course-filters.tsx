"use client";

import { LoaderCircleIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import { useOptimistic, useTransition } from "react";

import { SelectMenu } from "@/components/shell/select-menu";
import { Label } from "@/components/ui/label";

import type { FilterOption } from "./courses";

export function CourseFilters({
  basePath,
  levels,
  semesters,
  level,
  semester,
}: {
  basePath: string;
  levels: FilterOption[];
  semesters: FilterOption[];
  level: string;
  semester: string;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [levelValue, setLevelValue] = useOptimistic(level);
  const [semesterValue, setSemesterValue] = useOptimistic(semester);

  function go(nextLevel: string, nextSemester: string) {
    const query = new URLSearchParams();
    if (nextLevel) query.set("level", nextLevel);
    if (nextSemester) query.set("semester", nextSemester);
    const text = query.toString();
    router.replace(text ? `${basePath}?${text}` : basePath, { scroll: false });
  }

  return (
    <div
      role="group"
      aria-label="Filter courses"
      aria-busy={pending}
      className="flex flex-col gap-3 sm:flex-row sm:items-end"
    >
      <div className="flex flex-col gap-2 sm:w-56">
        <Label htmlFor="filter-level" className="type-label">
          Level
        </Label>
        <SelectMenu
          id="filter-level"
          value={levelValue}
          onValueChange={(next) =>
            startTransition(() => {
              setLevelValue(next);
              go(next, semesterValue);
            })
          }
          options={[{ value: "", label: "All levels" }, ...levels]}
          placeholder="All levels"
        />
      </div>
      <div className="flex flex-col gap-2 sm:w-56">
        <Label htmlFor="filter-semester" className="type-label">
          Semester
        </Label>
        <SelectMenu
          id="filter-semester"
          value={semesterValue}
          onValueChange={(next) =>
            startTransition(() => {
              setSemesterValue(next);
              go(levelValue, next);
            })
          }
          options={[{ value: "", label: "All semesters" }, ...semesters]}
          placeholder="All semesters"
        />
      </div>
      {pending ? (
        <p
          role="status"
          className="type-helper inline-flex items-center gap-1.5 pb-2 text-muted-foreground"
        >
          <LoaderCircleIcon
            aria-hidden="true"
            className="size-3.5 animate-spin"
          />
          Updating…
        </p>
      ) : null}
    </div>
  );
}
