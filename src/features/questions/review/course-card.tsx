import { BookOpenIcon, ChevronRightIcon, ListIcon } from "lucide-react";
import Link from "next/link";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

import type { CourseCardData } from "./courses";

export function CourseCard({
  course,
  href,
}: {
  course: CourseCardData;
  href: string;
}) {
  const { title, code, isActive, topicCount, slots } = course;

  return (
    <Link
      href={href}
      className="group block h-full rounded-xl outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
    >
      <Card className="h-full [--card-spacing:--spacing(5)] transition-colors group-hover:ring-foreground/25">
        <CardHeader>
          <div className="flex items-start gap-3">
            <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
              <BookOpenIcon aria-hidden="true" className="size-5" />
            </div>
            <div className="min-w-0 flex-1 space-y-1">
              <CardTitle className="type-card-title wrap-break-word">
                {title}
              </CardTitle>
              <p className="type-helper text-muted-foreground">{code}</p>
            </div>
            <ChevronRightIcon
              aria-hidden="true"
              className="mt-1 size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5"
            />
          </div>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          <ul className="flex flex-col gap-1">
            {slots.map((slot) => (
              <li
                key={`${slot.levelId}:${slot.semesterId}`}
                className="type-body"
              >
                {slot.levelName} · {slot.semesterName}
              </li>
            ))}
          </ul>
          <div className="flex flex-wrap items-center gap-2">
            <span
              className={`type-body inline-flex items-center gap-1.5 ${
                topicCount === 0 ? "text-muted-foreground" : ""
              }`}
            >
              <ListIcon aria-hidden="true" className="size-4" />
              {topicCount === 0
                ? "No topics"
                : `${topicCount} ${topicCount === 1 ? "topic" : "topics"}`}
            </span>
            {!isActive ? <Badge variant="outline">Inactive</Badge> : null}
          </div>
        </CardContent>
      </Card>
    </Link>
  );
}
