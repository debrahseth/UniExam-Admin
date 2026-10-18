"use client";

import { SearchIcon } from "lucide-react";
import Form from "next/form";
import Link from "next/link";
import { useRef, useState } from "react";

import { SelectMenu } from "@/components/shell/select-menu";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { InlineMessage } from "@/features/access/inline-message";

import { loadTopics } from "./catalog-actions";
import { CourseCombobox } from "./course-combobox";
import type { CourseOption, TopicOption } from "./editor/catalog";
import type { ListView } from "./search";

const DIFFICULTY_OPTIONS = [
  { value: "", label: "All difficulties" },
  { value: "easy", label: "Easy" },
  { value: "medium", label: "Medium" },
  { value: "hard", label: "Hard" },
];

export function QuestionFilters({
  view,
  initialQuery,
  initialCourse,
  initialTopics,
  initialTopic,
  initialDifficulty,
  clearHref,
  hasFilters,
  queryTooShort,
}: {
  view: ListView;
  initialQuery: string;
  initialCourse: CourseOption | null;
  initialTopics: TopicOption[];
  initialTopic: string;
  initialDifficulty: string;
  clearHref: string;
  hasFilters: boolean;
  queryTooShort: boolean;
}) {
  const [course, setCourse] = useState<CourseOption | null>(initialCourse);
  const [topics, setTopics] = useState<TopicOption[]>(initialTopics);
  const [topic, setTopic] = useState(initialTopic);
  const [difficulty, setDifficulty] = useState(initialDifficulty);
  const [topicsLoading, setTopicsLoading] = useState(false);
  const topicRequest = useRef(0);

  function onCourseChange(next: CourseOption | null) {
    setCourse(next);
    setTopic("");
    setTopics([]);
    const token = ++topicRequest.current;
    if (!next) {
      setTopicsLoading(false);
      return;
    }
    setTopicsLoading(true);
    loadTopics(next.id)
      .then((list) => {
        if (token === topicRequest.current) setTopics(list);
      })
      .catch(() => {
        if (token === topicRequest.current) setTopics([]);
      })
      .finally(() => {
        if (token === topicRequest.current) setTopicsLoading(false);
      });
  }

  const topicOptions = [
    { value: "", label: "All topics" },
    ...topics.map((t) => ({ value: t.id, label: t.title })),
  ];
  const topicPlaceholder = !course
    ? "Choose a course first"
    : topicsLoading
      ? "Loading topics…"
      : "All topics";

  return (
    <Form
      action="/admin/questions"
      role="search"
      aria-label="Search and filter questions"
      className="flex flex-col gap-4"
    >
      <input type="hidden" name="view" value={view} />
      {course ? <input type="hidden" name="course" value={course.id} /> : null}
      {course && topic ? (
        <input type="hidden" name="topic" value={topic} />
      ) : null}
      {difficulty ? (
        <input type="hidden" name="difficulty" value={difficulty} />
      ) : null}

      <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <Label htmlFor="filter-q" className="type-label">
            Search
          </Label>
          <div className="relative">
            <SearchIcon
              aria-hidden="true"
              className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground"
            />
            <Input
              id="filter-q"
              name="q"
              type="search"
              defaultValue={initialQuery}
              maxLength={100}
              autoComplete="off"
              placeholder="Question text or import key"
              className="h-9 pl-8"
            />
          </div>
        </div>
        <Button type="submit" size="lg" className="px-4">
          Search
        </Button>
      </div>

      {queryTooShort ? (
        <InlineMessage tone="neutral">
          Type at least 2 characters to search.
        </InlineMessage>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <div className="flex flex-col gap-2">
          <Label htmlFor="filter-course" className="type-label">
            Course
          </Label>
          <CourseCombobox
            id="filter-course"
            value={course}
            onChange={onCourseChange}
          />
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor="filter-topic" className="type-label">
            Topic
          </Label>
          <SelectMenu
            id="filter-topic"
            value={topic}
            onValueChange={setTopic}
            options={topicOptions}
            placeholder={topicPlaceholder}
            disabled={!course || topicsLoading}
          />
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor="filter-difficulty" className="type-label">
            Difficulty
          </Label>
          <SelectMenu
            id="filter-difficulty"
            value={difficulty}
            onValueChange={setDifficulty}
            options={DIFFICULTY_OPTIONS}
            placeholder="All difficulties"
          />
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <p className="type-helper text-muted-foreground">
          Filters apply when you press Search.
        </p>
        {hasFilters ? (
          <Link
            href={clearHref}
            className={buttonVariants({ variant: "ghost", size: "sm" })}
          >
            Clear search and filters
          </Link>
        ) : null}
      </div>
    </Form>
  );
}
