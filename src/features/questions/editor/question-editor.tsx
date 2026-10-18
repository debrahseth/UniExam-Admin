"use client";

import {
  CheckIcon,
  LoaderCircleIcon,
  LockIcon,
  PlusIcon,
  Trash2Icon,
} from "lucide-react";
import Link from "next/link";
import { useRef, useState, useTransition, type FormEvent } from "react";

import { TextArea } from "@/components/shell/form-fields";
import { SelectMenu } from "@/components/shell/select-menu";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { InlineMessage } from "@/features/access/inline-message";

import type { CourseOption, TopicOption } from "./catalog";
import { saveQuestion } from "./editor-actions";
import { QuestionPreview } from "../question-preview";
import { loadTopics } from "../catalog-actions";
import { CourseCombobox } from "../course-combobox";
import type { Difficulty } from "../types";

export type EditorMode = "create" | "edit" | "new_version";

export type EditorInitial = {
  courseId: string;
  topicId: string;
  stem: string;
  options: string[];
  correctIndex: number;
  explanation: string;
  difficulty: Difficulty | "";
};

const LETTERS = ["a", "b", "c", "d", "e", "f"];
const MIN_OPTIONS = 2;
const MAX_OPTIONS = 6;

const DIFFICULTY_OPTIONS = [
  { value: "easy", label: "Easy" },
  { value: "medium", label: "Medium" },
  { value: "hard", label: "Hard" },
];

function Fixed({
  label,
  value,
  note,
}: {
  label: string;
  value: string;
  note?: string;
}) {
  return (
    <div className="flex flex-col gap-2">
      <p className="type-label">{label}</p>
      <div className="type-body flex min-h-9 items-center gap-2 rounded-lg border bg-muted/40 px-2.5 py-1.5">
        <span className="min-w-0 flex-1 wrap-break-word">{value}</span>
        <LockIcon
          aria-hidden="true"
          className="size-3.5 shrink-0 text-muted-foreground"
        />
      </div>
      {note ? (
        <p className="type-helper text-muted-foreground">{note}</p>
      ) : null}
    </div>
  );
}

export function QuestionEditor({
  mode,
  topics,
  initial,
  versionId,
  questionId,
  fixedCourse,
  fixedTopic,
  submitLabel,
  cancelHref,
}: {
  mode: EditorMode;
  topics: TopicOption[];
  initial: EditorInitial;
  versionId?: string;
  questionId?: string;
  fixedCourse?: string;
  fixedTopic?: string;
  submitLabel: string;
  cancelHref: string;
}) {
  const [courseId, setCourseId] = useState(initial.courseId);
  const [topicId, setTopicId] = useState(initial.topicId);
  const [stem, setStem] = useState(initial.stem);
  const [options, setOptions] = useState<string[]>(initial.options);
  const [correctIndex, setCorrectIndex] = useState(initial.correctIndex);
  const [explanation, setExplanation] = useState(initial.explanation);
  const [difficulty, setDifficulty] = useState<Difficulty | "">(
    initial.difficulty,
  );
  const [error, setError] = useState<string | null>(null);
  const [busy, startTransition] = useTransition();

  const [course, setCourse] = useState<CourseOption | null>(null);
  const [topicOptions, setTopicOptions] = useState<TopicOption[]>(topics);
  const [topicsLoading, setTopicsLoading] = useState(false);
  const topicRequest = useRef(0);
  const topicFixed = mode === "new_version" || fixedTopic !== undefined;

  function onCourseChange(next: CourseOption | null) {
    setCourse(next);
    setCourseId(next?.id ?? "");
    setTopicId("");
    setTopicOptions([]);
    const token = ++topicRequest.current;
    if (!next) {
      setTopicsLoading(false);
      return;
    }
    setTopicsLoading(true);
    loadTopics(next.id)
      .then((list) => {
        if (token === topicRequest.current) setTopicOptions(list);
      })
      .catch(() => {
        if (token === topicRequest.current) setTopicOptions([]);
      })
      .finally(() => {
        if (token === topicRequest.current) setTopicsLoading(false);
      });
  }

  function setOption(index: number, value: string) {
    setOptions((prev) => prev.map((o, i) => (i === index ? value : o)));
  }

  function addOption() {
    setOptions((prev) => (prev.length < MAX_OPTIONS ? [...prev, ""] : prev));
  }

  function removeOption(index: number) {
    if (options.length <= MIN_OPTIONS) return;
    setOptions((prev) => prev.filter((_, i) => i !== index));
    setCorrectIndex((prev) =>
      prev === index ? -1 : prev > index ? prev - 1 : prev,
    );
  }

  function collectProblems(): string[] {
    const problems: string[] = [];
    if (mode === "create" && !courseId) problems.push("Choose a course.");
    if (!topicFixed && !topicId) problems.push("Choose a topic.");
    if (!stem.trim()) problems.push("Enter the question text.");
    if (options.some((o) => !o.trim())) {
      problems.push("Fill in every option or remove the empty ones.");
    }
    if (correctIndex < 0) problems.push("Choose the correct answer.");
    if (!difficulty) problems.push("Choose a difficulty.");
    return problems;
  }

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const problems = collectProblems();
    if (problems.length > 0) {
      setError(problems.join(" "));
      return;
    }

    const formData = new FormData();
    formData.set("mode", mode);
    formData.set("version", versionId ?? "");
    formData.set("question", questionId ?? "");
    formData.set("course", courseId);
    formData.set("topic", topicId);
    formData.set("stem", stem);
    for (const option of options) formData.append("option", option);
    formData.set("correct", LETTERS[correctIndex] ?? "");
    formData.set("difficulty", difficulty);
    formData.set("explanation", explanation);

    setError(null);
    startTransition(async () => {
      const result = await saveQuestion(formData);
      setError(result.message);
    });
  }

  const previewOptions = options.map((text, i) => ({
    id: LETTERS[i],
    text: text.trim() || "(empty option)",
  }));

  const topicDisabled =
    busy ||
    (mode === "create" && !courseId) ||
    topicsLoading ||
    topicOptions.length === 0;
  const topicPlaceholder =
    mode === "create" && !courseId
      ? "Choose a course first"
      : topicsLoading
        ? "Loading topics…"
        : topicOptions.length === 0
          ? "No topics for this course"
          : "Choose a topic";

  return (
    <div className="flex flex-col gap-8">
      <form onSubmit={onSubmit} className="flex flex-col gap-6" noValidate>
        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title">Where it belongs</CardTitle>
            <CardDescription>
              Difficulty and topic decide which exams can include the question.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 sm:grid-cols-2">
            {mode === "create" ? (
              <div className="flex flex-col gap-2">
                <Label htmlFor="editor-course" className="type-label">
                  Course
                </Label>
                <CourseCombobox
                  id="editor-course"
                  value={course}
                  onChange={onCourseChange}
                  activeOnly
                  disabled={busy}
                />
              </div>
            ) : (
              <Fixed label="Course" value={fixedCourse ?? ""} />
            )}

            {topicFixed ? (
              <Fixed
                label="Topic"
                value={fixedTopic ?? "No topic"}
                note="Locked once published."
              />
            ) : (
              <div className="flex flex-col gap-2">
                <Label htmlFor="editor-topic" className="type-label">
                  Topic
                </Label>
                <SelectMenu
                  id="editor-topic"
                  value={topicId}
                  onValueChange={setTopicId}
                  options={topicOptions.map((t) => ({
                    value: t.id,
                    label: t.title,
                  }))}
                  placeholder={topicPlaceholder}
                  disabled={topicDisabled}
                />
              </div>
            )}

            <div className="flex flex-col gap-2">
              <Label htmlFor="editor-difficulty" className="type-label">
                Difficulty
              </Label>
              <SelectMenu
                id="editor-difficulty"
                value={difficulty}
                onValueChange={(next) =>
                  setDifficulty(
                    next === "easy" || next === "medium" || next === "hard"
                      ? next
                      : "",
                  )
                }
                options={DIFFICULTY_OPTIONS}
                placeholder="Choose a difficulty"
                disabled={busy}
              />
            </div>
          </CardContent>
        </Card>

        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title">Question</CardTitle>
            <CardDescription className="max-w-prose">
              Plain text only. Line breaks show in the review but not during the
              exam, so don&apos;t rely on them.
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            <Label htmlFor="editor-stem" className="type-label">
              Question text
            </Label>
            <TextArea
              id="editor-stem"
              rows={4}
              maxLength={2000}
              value={stem}
              onChange={(event) => setStem(event.target.value)}
              disabled={busy}
              aria-describedby="editor-stem-count"
            />
            <p
              id="editor-stem-count"
              className="type-helper text-right text-muted-foreground tabular-nums"
            >
              {stem.length} / 2,000
            </p>
          </CardContent>
        </Card>

        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title">Answers</CardTitle>
            <CardDescription className="max-w-prose">
              2 to 6 options, one per line. Select the circle next to the
              correct answer. Each option is 1 to 500 characters and must be
              different from the others.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <fieldset className="flex flex-col gap-3" disabled={busy}>
              <legend className="sr-only">Options and correct answer</legend>
              {options.map((option, i) => {
                const letter = LETTERS[i].toUpperCase();
                const isCorrect = correctIndex === i;
                return (
                  <div
                    key={i}
                    className={`flex items-center gap-3 rounded-lg border p-2 transition-colors ${
                      isCorrect ? "border-primary/40 bg-accent/60" : "bg-card"
                    }`}
                  >
                    <input
                      type="radio"
                      name="correct"
                      checked={isCorrect}
                      onChange={() => setCorrectIndex(i)}
                      aria-label={`Option ${letter} is the correct answer`}
                      className="size-5 shrink-0 accent-primary"
                    />
                    <span
                      aria-hidden="true"
                      className="w-4 shrink-0 text-sm font-medium text-muted-foreground"
                    >
                      {letter}
                    </span>
                    <Input
                      value={option}
                      maxLength={500}
                      onChange={(event) => setOption(i, event.target.value)}
                      aria-label={`Text of option ${letter}`}
                      className="h-9 min-w-0 flex-1"
                    />
                    {isCorrect ? (
                      <span className="hidden shrink-0 items-center gap-1 text-xs font-medium text-accent-foreground sm:inline-flex">
                        <CheckIcon aria-hidden="true" className="size-3.5" />
                        Correct
                      </span>
                    ) : null}
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      onClick={() => removeOption(i)}
                      disabled={options.length <= MIN_OPTIONS}
                      aria-label={`Remove option ${letter}`}
                    >
                      <Trash2Icon />
                    </Button>
                  </div>
                );
              })}
              <div>
                <Button
                  type="button"
                  variant="outline"
                  size="lg"
                  className="px-3"
                  onClick={addOption}
                  disabled={options.length >= MAX_OPTIONS}
                >
                  <PlusIcon />
                  Add option
                </Button>
              </div>
            </fieldset>
          </CardContent>
        </Card>

        <Card className="[--card-spacing:--spacing(5)]">
          <CardHeader>
            <CardTitle className="type-card-title">Explanation</CardTitle>
            <CardDescription>
              Optional. Students see it in the review after the exam.
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            <Label htmlFor="editor-explanation" className="type-label">
              Explanation
            </Label>
            <TextArea
              id="editor-explanation"
              rows={4}
              maxLength={4000}
              value={explanation}
              onChange={(event) => setExplanation(event.target.value)}
              disabled={busy}
              aria-describedby="editor-explanation-count"
            />
            <p
              id="editor-explanation-count"
              className="type-helper text-right text-muted-foreground tabular-nums"
            >
              {explanation.length} / 4,000
            </p>
          </CardContent>
        </Card>

        {error ? (
          <InlineMessage tone="error" role="alert">
            {error}
          </InlineMessage>
        ) : null}

        <div className="flex flex-wrap gap-2">
          <Button
            type="submit"
            size="lg"
            className="px-4"
            disabled={busy}
            aria-busy={busy}
          >
            {busy ? (
              <LoaderCircleIcon aria-hidden="true" className="animate-spin" />
            ) : null}
            {busy ? "Saving…" : submitLabel}
          </Button>
          <Link
            href={cancelHref}
            className={buttonVariants({ variant: "outline", size: "lg" })}
          >
            Cancel
          </Link>
        </div>
      </form>

      <section aria-labelledby="editor-preview-heading" className="space-y-3">
        <div className="space-y-1">
          <h2 id="editor-preview-heading" className="type-section-title">
            Preview
          </h2>
          <p className="type-description text-muted-foreground">
            Updates as you type.
          </p>
        </div>
        <QuestionPreview
          stem={stem.trim() || "(no question text yet)"}
          options={previewOptions}
          correctId={correctIndex >= 0 ? LETTERS[correctIndex] : null}
          explanation={explanation.trim() || null}
        />
      </section>
    </div>
  );
}
