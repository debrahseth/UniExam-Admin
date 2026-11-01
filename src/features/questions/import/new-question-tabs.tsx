"use client";

import { useId, useState, type KeyboardEvent, type ReactNode } from "react";

type TabId = "single" | "import";

const TABS: { id: TabId; label: string }[] = [
  { id: "single", label: "Single question" },
  { id: "import", label: "Import from JSON" },
];

export function NewQuestionTabs({
  single,
  importer,
}: {
  single: ReactNode;
  importer: ReactNode;
}) {
  const [active, setActive] = useState<TabId>("single");
  const base = useId();

  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
    event.preventDefault();
    const step = event.key === "ArrowRight" ? 1 : TABS.length - 1;
    const next = TABS[(index + step) % TABS.length];
    setActive(next.id);
    document.getElementById(`${base}-tab-${next.id}`)?.focus();
  }

  return (
    <div className="space-y-6">
      <div
        role="tablist"
        aria-label="How to add questions"
        className="flex gap-1 border-b"
      >
        {TABS.map((tab, index) => {
          const selected = active === tab.id;
          return (
            <button
              key={tab.id}
              id={`${base}-tab-${tab.id}`}
              type="button"
              role="tab"
              aria-selected={selected}
              aria-controls={`${base}-panel-${tab.id}`}
              tabIndex={selected ? 0 : -1}
              onClick={() => setActive(tab.id)}
              onKeyDown={(event) => onKeyDown(event, index)}
              className={`-mb-px border-b-2 px-3 py-2 text-sm font-medium transition-colors ${
                selected
                  ? "border-primary text-foreground"
                  : "border-transparent text-muted-foreground hover:text-foreground"
              }`}
            >
              {tab.label}
            </button>
          );
        })}
      </div>

      <div
        role="tabpanel"
        id={`${base}-panel-single`}
        aria-labelledby={`${base}-tab-single`}
        hidden={active !== "single"}
      >
        {single}
      </div>
      <div
        role="tabpanel"
        id={`${base}-panel-import`}
        aria-labelledby={`${base}-tab-import`}
        hidden={active !== "import"}
      >
        {importer}
      </div>
    </div>
  );
}
