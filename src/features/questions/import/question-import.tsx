"use client";

import { LoaderCircleIcon } from "lucide-react";
import { useMemo, useState, useTransition, type ChangeEvent } from "react";

import { TextArea } from "@/components/shell/form-fields";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { InlineMessage } from "@/features/access/inline-message";
import type {
  CourseOption,
  TopicOption,
} from "@/features/questions/editor/catalog";

import {
  importQuestions,
  resolveImportCourse,
  type ImportResultRow,
} from "./import-actions";
import { BATCH_SIZE, buildPlan, parseSeed, type SeedFile } from "./seed";

const MAX_FILE_BYTES = 2_000_000;

const ITEM_ERRORS: Record<string, string> = {
  invalid_item: "This entry is not valid.",
  invalid_key: "The key is not valid.",
  invalid_source: "The source is not valid.",
  invalid_course: "The course is not valid or not active.",
  invalid_topic: "The topic does not belong to the course.",
  invalid_stem: "The question text is not valid.",
  invalid_options:
    "The options are not valid (2 to 6, each 1 to 500 characters, all different).",
  invalid_correct: "The correct answer is not valid.",
  invalid_difficulty: "The difficulty is not valid.",
  invalid_explanation: "The explanation is not valid.",
  duplicate_key:
    "Another question with this key was created at the same moment.",
  unexpected_error:
    "The database refused this question. Nothing was saved for it.",
};

function errorText(code: string | null): string {
  return (code && ITEM_ERRORS[code]) || "This question could not be imported.";
}

export function QuestionImport() {
  const [text, setText] = useState("");
  const [fileName, setFileName] = useState<string | null>(null);
  const [shuffle, setShuffle] = useState(true);
  const [file, setFile] = useState<SeedFile | null>(null);
  const [catalog, setCatalog] = useState<{
    course: CourseOption;
    topics: TopicOption[];
  } | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [results, setResults] = useState<Record<string, ImportResultRow>>({});
  const [progress, setProgress] = useState<string | null>(null);
  const [importing, setImporting] = useState(false);
  const [checking, startChecking] = useTransition();

  const busy = checking || importing;

  const plan = useMemo(
    () =>
      file && catalog
        ? buildPlan(file, catalog.course.id, catalog.topics, shuffle)
        : null,
    [file, catalog, shuffle],
  );

  function reset() {
    setFile(null);
    setCatalog(null);
    setResults({});
    setMessage(null);
    setProgress(null);
  }

  async function onFile(event: ChangeEvent<HTMLInputElement>) {
    const chosen = event.target.files?.[0];
    if (!chosen) return;
    reset();
    if (chosen.size > MAX_FILE_BYTES) {
      setMessage("That file is too large (the limit is about 2 MB).");
      return;
    }
    try {
      setText(await chosen.text());
      setFileName(chosen.name);
    } catch {
      setMessage("The file could not be read.");
    }
  }

  function onCheck() {
    reset();
    const parsed = parseSeed(text);
    if (!parsed.ok) {
      setMessage(parsed.message);
      return;
    }
    startChecking(async () => {
      const found = await resolveImportCourse(parsed.file.course);
      if (!found.ok) {
        setMessage(found.message);
        return;
      }
      setFile(parsed.file);
      setCatalog({ course: found.course, topics: found.topics });
    });
  }

  const ready = plan ? plan.filter((row) => row.item !== null) : [];
  const withProblems = plan ? plan.length - ready.length : 0;

  const pending = ready.filter((row) => {
    const result = row.key ? results[row.key] : undefined;
    return !result || result.outcome === "failed";
  });

  const counts = { created: 0, skipped: 0, failed: 0 };
  for (const row of Object.values(results)) counts[row.outcome] += 1;
  const attempted = Object.keys(results).length > 0;

  async function runImport() {
    setImporting(true);
    setMessage(null);

    const items = pending.flatMap((row) => (row.item ? [row.item] : []));
    for (let start = 0; start < items.length; start += BATCH_SIZE) {
      const chunk = items.slice(start, start + BATCH_SIZE);
      setProgress(
        `Importing ${Math.min(start + chunk.length, items.length)} of ${items.length}…`,
      );
      const result = await importQuestions(chunk);
      if (!result.ok) {
        setMessage(result.message);
        break;
      }
      setResults((previous) => {
        const next = { ...previous };
        for (const row of result.rows) {
          if (row.key) next[row.key] = row;
        }
        return next;
      });
    }

    setProgress(null);
    setImporting(false);
  }

  return (
    <div className="flex flex-col gap-6">
      <Card className="[--card-spacing:--spacing(5)]">
        <CardHeader>
          <CardTitle className="type-card-title">Seed file</CardTitle>
          <CardDescription className="max-w-prose">
            A JSON file with a course and a list of questions. Every question is
            saved as a draft under your name. Questions whose key already exists
            are skipped, so running the same file twice is safe.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <div className="flex flex-col gap-2">
            <Label htmlFor="import-file" className="type-label">
              Choose a .json file
            </Label>
            <input
              id="import-file"
              type="file"
              accept=".json,application/json"
              onChange={onFile}
              disabled={busy}
              className="type-body"
            />
            {fileName ? (
              <p className="type-helper text-muted-foreground">
                Loaded {fileName}.
              </p>
            ) : null}
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="import-text" className="type-label">
              Or paste the JSON
            </Label>
            <TextArea
              id="import-text"
              rows={8}
              value={text}
              onChange={(event) => {
                setText(event.target.value);
                setFileName(null);
                reset();
              }}
              disabled={busy}
              spellCheck={false}
              className="font-mono"
            />
          </div>

          <label className="type-body flex items-start gap-2">
            <input
              type="checkbox"
              checked={shuffle}
              onChange={(event) => setShuffle(event.target.checked)}
              disabled={importing}
              className="mt-1 size-4 shrink-0 accent-primary"
            />
            <span>
              Shuffle the answer order
              <span className="type-helper block text-muted-foreground">
                Recommended: it stops the correct answer clustering in one
                position. The order is fixed per question key, and questions
                with options such as &ldquo;All of the above&rdquo; keep their
                order.
              </span>
            </span>
          </label>

          <div>
            <Button
              type="button"
              size="lg"
              className="px-4"
              onClick={onCheck}
              disabled={busy || text.trim() === ""}
              aria-busy={checking}
            >
              {checking ? (
                <LoaderCircleIcon aria-hidden="true" className="animate-spin" />
              ) : null}
              {checking ? "Checking…" : "Check file"}
            </Button>
          </div>
        </CardContent>
      </Card>

      {message ? (
        <InlineMessage tone="error" role="alert">
          {message}
        </InlineMessage>
      ) : null}

      {plan && catalog ? (
        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title">
              {catalog.course.code} · {catalog.course.title}
            </CardTitle>
            <CardDescription>
              {plan.length} {plan.length === 1 ? "question" : "questions"} in
              the file: {ready.length} ready
              {withProblems > 0
                ? `, ${withProblems} with problems (not sent)`
                : ""}
              .
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <div role="status" aria-live="polite" className="type-body">
              {progress ? (
                <span className="inline-flex items-center gap-2">
                  <LoaderCircleIcon
                    aria-hidden="true"
                    className="size-4 animate-spin"
                  />
                  {progress}
                </span>
              ) : attempted ? (
                <span>
                  {counts.created} created, {counts.skipped} skipped (already
                  exist), {counts.failed} failed.
                </span>
              ) : null}
            </div>

            <div className="overflow-x-auto rounded-lg border">
              <table className="type-body w-full min-w-176 text-left">
                <caption className="sr-only">Questions in the file</caption>
                <thead className="border-b bg-muted/40 text-muted-foreground">
                  <tr>
                    <th scope="col" className="px-3 py-2 font-medium">
                      #
                    </th>
                    <th scope="col" className="px-3 py-2 font-medium">
                      Key
                    </th>
                    <th scope="col" className="px-3 py-2 font-medium">
                      Question
                    </th>
                    <th scope="col" className="px-3 py-2 font-medium">
                      Topic
                    </th>
                    <th scope="col" className="px-3 py-2 font-medium">
                      Answer
                    </th>
                    <th scope="col" className="px-3 py-2 font-medium">
                      Status
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {plan.map((row) => {
                    const result = row.key ? results[row.key] : undefined;
                    let status: string;
                    if (result) {
                      status =
                        result.outcome === "created"
                          ? "Created as a draft"
                          : result.outcome === "skipped"
                            ? "Already exists, skipped"
                            : errorText(result.error);
                    } else if (row.problems.length > 0) {
                      status = row.problems.join(" ");
                    } else {
                      status = "Ready";
                    }
                    const isProblem =
                      row.problems.length > 0 || result?.outcome === "failed";
                    return (
                      <tr
                        key={row.index}
                        className="border-b last:border-b-0 align-top"
                      >
                        <td className="px-3 py-2 tabular-nums">{row.index}</td>
                        <td className="px-3 py-2 break-all">
                          {row.key ?? "—"}
                        </td>
                        <td className="px-3 py-2 wrap-anywhere">
                          {row.stemPreview || "—"}
                        </td>
                        <td className="px-3 py-2">{row.topicTitle || "—"}</td>
                        <td className="px-3 py-2">
                          {row.correctLetter
                            ? row.correctLetter.toUpperCase()
                            : "—"}
                          {row.keptOrder ? (
                            <span className="type-helper block text-muted-foreground">
                              order kept
                            </span>
                          ) : null}
                        </td>
                        <td
                          className={`px-3 py-2 ${isProblem ? "text-destructive" : ""}`}
                        >
                          {status}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <Button
                type="button"
                size="lg"
                className="px-4"
                onClick={runImport}
                disabled={busy || pending.length === 0}
                aria-busy={importing}
              >
                {importing ? (
                  <LoaderCircleIcon
                    aria-hidden="true"
                    className="animate-spin"
                  />
                ) : null}
                {importing
                  ? "Importing…"
                  : attempted
                    ? `Import the ${pending.length} not yet done`
                    : `Import ${pending.length} ${pending.length === 1 ? "question" : "questions"}`}
              </Button>
              {withProblems > 0 && !attempted ? (
                <p className="type-helper text-muted-foreground">
                  Questions with problems are left out. Fix them in the file and
                  run it again; the ones already imported will be skipped.
                </p>
              ) : null}
            </div>
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}
