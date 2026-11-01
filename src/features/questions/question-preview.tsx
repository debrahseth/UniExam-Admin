import { CheckIcon } from "lucide-react";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { cn } from "@/lib/utils";

import type { QuestionOption } from "./types";

const LETTERS = ["A", "B", "C", "D", "E", "F"];

export function QuestionPreview({
  stem,
  options,
  correctId,
  explanation,
  show = "both",
}: {
  stem: string;
  options: QuestionOption[];
  correctId: string | null;
  explanation: string | null;
  show?: "both" | "review";
}) {
  return (
    <div className={cn("grid gap-4", show === "both" && "lg:grid-cols-2")}>
      {show === "both" ? (
        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title">During the exam</CardTitle>
            <CardDescription>
              Options are labelled by position. Line breaks in the question are
              not shown.
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <p className="text-lg leading-relaxed font-medium wrap-anywhere">
              {stem}
            </p>
            <div className="flex flex-col gap-3">
              {options.map((option, i) => (
                <div
                  key={option.id}
                  className="flex items-start gap-3 rounded-lg border bg-card p-4"
                >
                  <span
                    aria-hidden="true"
                    className="flex size-6 shrink-0 items-center justify-center rounded-full border text-xs font-semibold text-muted-foreground"
                  >
                    {LETTERS[i] ?? "?"}
                  </span>
                  <span className="text-base leading-relaxed wrap-anywhere">
                    <span className="sr-only">
                      Option {LETTERS[i] ?? "?"}:{" "}
                    </span>
                    {option.text}
                  </span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      ) : null}

      <Card className="[--card-spacing:--spacing(5)]">
        <CardHeader>
          <CardTitle className="type-card-title">
            In the review afterwards
          </CardTitle>
          <CardDescription>
            Shows the correct answer and the explanation. Line breaks are kept.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <p className="text-base whitespace-pre-wrap wrap-anywhere">{stem}</p>
          <ul className="flex flex-col gap-2">
            {options.map((option) => {
              const isCorrect = option.id === correctId;
              return (
                <li
                  key={option.id}
                  className={cn(
                    "flex items-start gap-3 rounded-lg border px-3 py-2.5 text-sm",
                    isCorrect ? "border-primary/40 bg-accent" : "bg-card",
                  )}
                >
                  <span className="mt-0.5 w-5 shrink-0 font-medium text-muted-foreground uppercase">
                    {option.id}
                  </span>
                  <span className="min-w-0 flex-1 wrap-anywhere">
                    {option.text}
                  </span>
                  {isCorrect ? (
                    <span className="inline-flex shrink-0 items-center gap-1 text-xs font-medium text-accent-foreground">
                      <CheckIcon aria-hidden="true" className="size-3.5" />
                      Correct answer
                    </span>
                  ) : null}
                </li>
              );
            })}
          </ul>
          {explanation ? (
            <div className="rounded-lg border bg-muted/40 p-3 text-sm">
              <p className="mb-1 font-medium">Explanation</p>
              <p className="whitespace-pre-wrap text-muted-foreground wrap-anywhere">
                {explanation}
              </p>
            </div>
          ) : (
            <p className="type-helper text-muted-foreground">No explanation.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
