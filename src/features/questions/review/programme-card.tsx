import {
  BookOpenIcon,
  ChevronRightIcon,
  GraduationCapIcon,
} from "lucide-react";
import Link from "next/link";

import { Badge } from "@/components/ui/badge";
import { Card, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";

import type { Programme } from "./programmes";

function monogramOf(code: string): string {
  return code
    .replace(/[^A-Za-z0-9]/g, "")
    .slice(0, 2)
    .toUpperCase();
}

export function ProgrammeCard({ programme }: { programme: Programme }) {
  const { id, code, name, isActive, courseCount } = programme;
  const monogram = monogramOf(code);

  return (
    <Link
      href={`/admin/questions/programmes/${id}`}
      className="group block h-full rounded-xl outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
    >
      <Card className="h-full [--card-spacing:--spacing(5)] transition-shadow group-hover:shadow-sm group-hover:ring-foreground/25">
        <CardHeader className="flex-1">
          <div className="flex items-start gap-3.5">
            <div
              aria-hidden="true"
              className={`flex size-10 shrink-0 items-center justify-center rounded-lg text-sm font-semibold tracking-wide transition-colors ${
                isActive
                  ? "bg-primary/10 text-primary group-hover:bg-primary group-hover:text-primary-foreground"
                  : "bg-muted text-muted-foreground"
              }`}
            >
              {monogram || <GraduationCapIcon className="size-5" />}
            </div>
            <div className="min-w-0 flex-1 space-y-1.5">
              <CardTitle className="type-card-title line-clamp-2 wrap-break-word">
                {name}
              </CardTitle>
              <div className="flex flex-wrap items-center gap-2">
                <span className="type-helper font-mono text-muted-foreground">
                  {code}
                </span>
                {!isActive ? <Badge variant="outline">Inactive</Badge> : null}
              </div>
            </div>
          </div>
        </CardHeader>

        <CardFooter className="justify-between py-3">
          <span
            className={`type-body inline-flex items-center gap-1.5 ${
              courseCount === 0 ? "text-muted-foreground" : "font-medium"
            }`}
          >
            <BookOpenIcon
              aria-hidden="true"
              className="size-4 text-muted-foreground"
            />
            {courseCount === 0
              ? "No courses"
              : `${courseCount} ${courseCount === 1 ? "course" : "courses"}`}
          </span>
          <ChevronRightIcon
            aria-hidden="true"
            className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5 group-hover:text-foreground"
          />
        </CardFooter>
      </Card>
    </Link>
  );
}
