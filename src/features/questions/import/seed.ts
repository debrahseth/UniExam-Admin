import type { TopicOption } from "@/features/questions/editor/catalog";
import type { Difficulty } from "@/features/questions/types";

export const LETTERS: readonly string[] = ["a", "b", "c", "d", "e", "f"];
export const BATCH_SIZE = 100;

const KEY_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$/;
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/;
const MAX_FILE_CHARS = 2_000_000;
const MAX_QUESTIONS = 500;
const DIFFICULTIES: readonly string[] = ["easy", "medium", "hard"];

const POSITION_DEPENDENT =
  /\b(all|none|both|neither)\s+of\s+the\s+(above|below|these)\b|\b(all|none)\s+(the\s+)?above\b|\boptions?\s+[a-f]\b|\b(both|neither)\s+[a-f]\b/i;

export type ParsedQuestion = {
  key: string;
  topicTitle: string;
  difficulty: Difficulty;
  source: string | null;
  stem: string;
  options: string[];
  correctIndex: number;
  explanation: string | null;
};

export type SeedRow = {
  index: number;
  key: string | null;
  stemPreview: string;
  topicTitle: string;
  question: ParsedQuestion | null;
  problems: string[];
};

export type SeedFile = { course: string; rows: SeedRow[] };

export type ParseResult =
  | { ok: true; file: SeedFile }
  | { ok: false; message: string };

export type ImportItem = {
  key: string;
  source: string | null;
  course_id: string;
  topic_id: string;
  stem: string;
  options: string[];
  correct: string;
  explanation: string | null;
  difficulty: Difficulty;
};

export type PlanRow = {
  index: number;
  key: string | null;
  stemPreview: string;
  topicTitle: string;
  problems: string[];
  item: ImportItem | null;
  correctLetter: string | null;
  keptOrder: boolean;
};

function trimWs(text: string): string {
  return text.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, "");
}

function hasControl(text: string, allowLayout: boolean): boolean {
  return CONTROL.test(allowLayout ? text.replace(/[\t\n\r]/g, "") : text);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function validateRow(raw: unknown, index: number): SeedRow {
  if (!isRecord(raw)) {
    return {
      index,
      key: null,
      stemPreview: "",
      topicTitle: "",
      question: null,
      problems: ["This entry is not an object."],
    };
  }

  const problems: string[] = [];

  const key = typeof raw.key === "string" ? raw.key : null;
  if (key === null || !KEY_PATTERN.test(key)) {
    problems.push(
      "The key must be 3 to 100 characters (letters, digits, dots, dashes, underscores), starting with a letter or digit.",
    );
  }

  const topicTitle = typeof raw.topic === "string" ? trimWs(raw.topic) : "";
  if (!topicTitle) problems.push("The topic is missing.");

  const difficulty =
    typeof raw.difficulty === "string" && DIFFICULTIES.includes(raw.difficulty)
      ? (raw.difficulty as Difficulty)
      : null;
  if (!difficulty)
    problems.push("The difficulty must be easy, medium or hard.");

  let source: string | null = null;
  if (raw.source !== undefined && raw.source !== null) {
    if (typeof raw.source !== "string") {
      problems.push("The source must be text.");
    } else {
      const text = trimWs(raw.source);
      if (text.length > 200 || hasControl(text, false)) {
        problems.push("The source must be at most 200 characters on one line.");
      } else {
        source = text === "" ? null : text;
      }
    }
  }

  const stem = typeof raw.stem === "string" ? trimWs(raw.stem) : "";
  if (stem.length < 1 || stem.length > 2000 || hasControl(stem, true)) {
    problems.push(
      "The question text must be 1 to 2,000 characters with no control characters.",
    );
  }

  const optionTexts: string[] = [];
  let optionsProblem: string | null = null;
  if (!Array.isArray(raw.options)) {
    optionsProblem = "The options are missing.";
  } else if (raw.options.length < 2 || raw.options.length > 6) {
    optionsProblem = "Provide 2 to 6 options.";
  } else {
    const list: unknown[] = raw.options;
    const seen = new Set<string>();
    for (let i = 0; i < list.length; i += 1) {
      const item = list[i];
      if (!isRecord(item) || typeof item.text !== "string") {
        optionsProblem = `Option ${i + 1} is not valid.`;
        break;
      }
      if (item.id !== undefined && item.id !== LETTERS[i]) {
        optionsProblem = `Option ${i + 1} must have the id "${LETTERS[i]}"; ids run a, b, c in order.`;
        break;
      }
      const text = trimWs(item.text);
      if (text.length < 1 || text.length > 500 || hasControl(text, false)) {
        optionsProblem = `Option ${LETTERS[i].toUpperCase()} must be 1 to 500 characters on one line.`;
        break;
      }
      const folded = text.toLowerCase();
      if (seen.has(folded)) {
        optionsProblem = `Option ${LETTERS[i].toUpperCase()} repeats another option.`;
        break;
      }
      seen.add(folded);
      optionTexts.push(text);
    }
  }
  if (optionsProblem) problems.push(optionsProblem);

  let correctIndex = -1;
  const rawCorrect = raw.correct;
  const correctId =
    typeof rawCorrect === "string"
      ? rawCorrect
      : Array.isArray(rawCorrect) &&
          rawCorrect.length === 1 &&
          typeof rawCorrect[0] === "string"
        ? (rawCorrect[0] as string)
        : null;
  if (correctId === null) {
    problems.push("Exactly one correct option is required.");
  } else if (!optionsProblem) {
    correctIndex = LETTERS.indexOf(correctId);
    if (correctIndex < 0 || correctIndex >= optionTexts.length) {
      problems.push(
        `The correct option "${correctId.slice(0, 10)}" does not match any option.`,
      );
      correctIndex = -1;
    }
  }

  let explanation: string | null = null;
  if (raw.explanation !== undefined && raw.explanation !== null) {
    if (typeof raw.explanation !== "string") {
      problems.push("The explanation must be text.");
    } else {
      const text = trimWs(raw.explanation);
      if (text.length > 4000 || hasControl(text, true)) {
        problems.push(
          "The explanation can be up to 4,000 characters with no control characters.",
        );
      } else {
        explanation = text === "" ? null : text;
      }
    }
  }

  const stemPreview =
    typeof raw.stem === "string"
      ? trimWs(raw.stem).replace(/\s+/g, " ").slice(0, 90)
      : "";

  if (problems.length > 0 || key === null || difficulty === null) {
    return { index, key, stemPreview, topicTitle, question: null, problems };
  }

  return {
    index,
    key,
    stemPreview,
    topicTitle,
    question: {
      key,
      topicTitle,
      difficulty,
      source,
      stem,
      options: optionTexts,
      correctIndex,
      explanation,
    },
    problems: [],
  };
}

export function parseSeed(text: string): ParseResult {
  if (trimWs(text) === "") {
    return { ok: false, message: "Paste the JSON or choose a file first." };
  }
  if (text.length > MAX_FILE_CHARS) {
    return {
      ok: false,
      message: "The file is too large (the limit is about 2 MB).",
    };
  }

  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return {
      ok: false,
      message:
        "This is not valid JSON. Check for a missing comma, quote or bracket.",
    };
  }

  if (!isRecord(data)) {
    return {
      ok: false,
      message:
        'The file must be an object with a "course" and a "questions" list.',
    };
  }

  const course = typeof data.course === "string" ? trimWs(data.course) : "";
  if (!course || course.length > 40) {
    return {
      ok: false,
      message: 'The file needs a "course" such as "CHE 151".',
    };
  }

  if (!Array.isArray(data.questions) || data.questions.length === 0) {
    return {
      ok: false,
      message: 'The file needs a non-empty "questions" list.',
    };
  }
  if (data.questions.length > MAX_QUESTIONS) {
    return {
      ok: false,
      message: `The file has more than ${MAX_QUESTIONS} questions. Split it into smaller files.`,
    };
  }

  const list: unknown[] = data.questions;
  const rows = list.map((raw, i) => validateRow(raw, i + 1));

  const firstSeen = new Set<string>();
  const checked = rows.map((row): SeedRow => {
    if (row.key === null) return row;
    if (!firstSeen.has(row.key)) {
      firstSeen.add(row.key);
      return row;
    }
    return {
      ...row,
      question: null,
      problems: [
        ...row.problems,
        "This key already appears earlier in the file.",
      ],
    };
  });

  return { ok: true, file: { course, rows: checked } };
}

function normaliseTitle(title: string): string {
  return title.replace(/\s+/g, " ").trim().toLowerCase();
}

function hash32(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i += 1) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

function mulberry32(seed: number): () => number {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffledOrder(key: string, count: number): number[] {
  const order = Array.from({ length: count }, (_, i) => i);
  const random = mulberry32(hash32(key));
  for (let i = count - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  return order;
}

export function buildPlan(
  file: SeedFile,
  courseId: string,
  topics: readonly TopicOption[],
  shuffle: boolean,
): PlanRow[] {
  const byTitle = new Map<string, TopicOption[]>();
  for (const topic of topics) {
    const name = normaliseTitle(topic.title);
    byTitle.set(name, [...(byTitle.get(name) ?? []), topic]);
  }

  return file.rows.map((row): PlanRow => {
    const base = {
      index: row.index,
      key: row.key,
      stemPreview: row.stemPreview,
      topicTitle: row.topicTitle,
    };

    const q = row.question;
    if (!q) {
      return {
        ...base,
        problems: row.problems,
        item: null,
        correctLetter: null,
        keptOrder: false,
      };
    }

    const matches = byTitle.get(normaliseTitle(q.topicTitle)) ?? [];
    if (matches.length !== 1) {
      return {
        ...base,
        problems: [
          matches.length === 0
            ? `The topic "${q.topicTitle}" does not exist in this course.`
            : `More than one topic in this course is called "${q.topicTitle}".`,
        ],
        item: null,
        correctLetter: null,
        keptOrder: false,
      };
    }

    const canShuffle =
      shuffle && !q.options.some((o) => POSITION_DEPENDENT.test(o));
    const order = canShuffle
      ? shuffledOrder(q.key, q.options.length)
      : q.options.map((_, i) => i);
    const options = order.map((i) => q.options[i]);
    const correctLetter = LETTERS[order.indexOf(q.correctIndex)];

    return {
      ...base,
      problems: [],
      correctLetter,
      keptOrder: shuffle && !canShuffle,
      item: {
        key: q.key,
        source: q.source,
        course_id: courseId,
        topic_id: matches[0].id,
        stem: q.stem,
        options,
        correct: correctLetter,
        explanation: q.explanation,
        difficulty: q.difficulty,
      },
    };
  });
}
