"use client";

import { Combobox } from "@base-ui/react/combobox";
import { CheckIcon, ChevronDownIcon, XIcon } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import { searchCourses } from "./catalog-actions";
import type { CourseOption } from "./editor/catalog";

function labelOf(course: CourseOption): string {
  return `${course.code} · ${course.title}`;
}

const ICON_BUTTON =
  "flex size-7 items-center justify-center rounded-md text-muted-foreground outline-none hover:bg-muted hover:text-foreground focus-visible:ring-3 focus-visible:ring-ring/50";

export function CourseCombobox({
  id,
  value,
  onChange,
  activeOnly = false,
  disabled,
  placeholder = "Search courses",
}: {
  id: string;
  value: CourseOption | null;
  onChange: (course: CourseOption | null) => void;
  activeOnly?: boolean;
  disabled?: boolean;
  placeholder?: string;
}) {
  const [query, setQuery] = useState("");
  const [options, setOptions] = useState<CourseOption[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const requestId = useRef(0);

  useEffect(() => {
    if (!open) return;
    const token = ++requestId.current;
    const timer = setTimeout(
      () => {
        setLoading(true);
        searchCourses(query, activeOnly)
          .then((result) => {
            if (token === requestId.current) setOptions(result);
          })
          .catch(() => {
            if (token === requestId.current) setOptions([]);
          })
          .finally(() => {
            if (token === requestId.current) setLoading(false);
          });
      },
      query ? 250 : 0,
    );
    return () => clearTimeout(timer);
  }, [query, activeOnly, open]);

  return (
    <Combobox.Root
      items={options}
      value={value}
      open={open}
      onOpenChange={setOpen}
      onValueChange={(next) => onChange(next)}
      onInputValueChange={(text) =>
        setQuery(value && text === labelOf(value) ? "" : text)
      }
      itemToStringLabel={labelOf}
      isItemEqualToValue={(a, b) => a.id === b.id}
      filter={null}
      disabled={disabled}
    >
      <div className="relative">
        <Combobox.Input
          id={id}
          placeholder={placeholder}
          autoComplete="off"
          className="h-9 w-full min-w-0 rounded-lg border border-input bg-transparent pr-16 pl-2.5 text-base transition-colors outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 md:text-sm dark:bg-input/30"
        />
        <div className="absolute inset-y-0 right-1 flex items-center gap-0.5">
          {value ? (
            <Combobox.Clear aria-label="Clear course" className={ICON_BUTTON}>
              <XIcon aria-hidden="true" className="size-3.5" />
            </Combobox.Clear>
          ) : null}
          <Combobox.Trigger aria-label="Show courses" className={ICON_BUTTON}>
            <ChevronDownIcon aria-hidden="true" className="size-4" />
          </Combobox.Trigger>
        </div>
      </div>

      <Combobox.Portal>
        <Combobox.Positioner
          sideOffset={4}
          className="isolate z-50 outline-none"
        >
          <Combobox.Popup className="max-h-72 w-(--anchor-width) min-w-48 overflow-y-auto rounded-lg bg-popover p-1 text-popover-foreground shadow-md ring-1 ring-foreground/10 outline-none">
            <Combobox.Empty className="px-3 py-2 text-sm text-muted-foreground">
              {loading ? "Searching…" : "No courses found."}
            </Combobox.Empty>
            <Combobox.List>
              {(course: CourseOption) => (
                <Combobox.Item
                  key={course.id}
                  value={course}
                  className="flex cursor-default items-center gap-2 rounded-md px-2 py-1.5 text-sm outline-hidden select-none data-highlighted:bg-accent data-highlighted:text-accent-foreground"
                >
                  <span className="min-w-0 flex-1 wrap-break-word">
                    {labelOf(course)}
                  </span>
                  <Combobox.ItemIndicator>
                    <CheckIcon aria-hidden="true" className="size-4" />
                  </Combobox.ItemIndicator>
                </Combobox.Item>
              )}
            </Combobox.List>
          </Combobox.Popup>
        </Combobox.Positioner>
      </Combobox.Portal>
    </Combobox.Root>
  );
}
