export type ProgrammeHeader = {
  id: string;
  code: string;
  name: string;
  isActive: boolean;
};

export type CourseSlotRow = {
  courseId: string;
  code: string;
  title: string;
  isActive: boolean;
  topicCount: number;
  levelId: string;
  levelName: string;
  levelSort: number;
  semesterId: string;
  semesterName: string;
  semesterSort: number;
};

export type CourseSlot = {
  levelId: string;
  levelName: string;
  semesterId: string;
  semesterName: string;
};

export type CourseCardData = {
  id: string;
  code: string;
  title: string;
  isActive: boolean;
  topicCount: number;
  slots: CourseSlot[];
};

export type FilterOption = { value: string; label: string };

function toCount(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value) && value >= 0) {
    return value;
  }
  if (typeof value === "string" && /^\d{1,9}$/.test(value))
    return Number(value);
  return null;
}

function toInt(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

export function toProgrammeHeader(row: unknown): ProgrammeHeader | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  if (
    typeof r.id !== "string" ||
    typeof r.code !== "string" ||
    typeof r.name !== "string" ||
    typeof r.is_active !== "boolean"
  ) {
    return null;
  }
  return { id: r.id, code: r.code, name: r.name, isActive: r.is_active };
}

export function toCourseRow(row: unknown): CourseSlotRow | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  const topicCount = toCount(r.topic_count);
  const levelSort = toInt(r.level_sort);
  const semesterSort = toInt(r.semester_sort);

  if (
    typeof r.course_id !== "string" ||
    typeof r.code !== "string" ||
    typeof r.title !== "string" ||
    typeof r.is_active !== "boolean" ||
    typeof r.level_id !== "string" ||
    typeof r.level_name !== "string" ||
    typeof r.semester_id !== "string" ||
    typeof r.semester_name !== "string" ||
    topicCount === null ||
    levelSort === null ||
    semesterSort === null
  ) {
    return null;
  }

  return {
    courseId: r.course_id,
    code: r.code,
    title: r.title,
    isActive: r.is_active,
    topicCount,
    levelId: r.level_id,
    levelName: r.level_name,
    levelSort,
    semesterId: r.semester_id,
    semesterName: r.semester_name,
    semesterSort,
  };
}

export function levelOptions(rows: CourseSlotRow[]): FilterOption[] {
  const found = new Map<string, { label: string; sort: number }>();
  for (const row of rows) {
    found.set(row.levelId, { label: row.levelName, sort: row.levelSort });
  }
  return [...found.entries()]
    .sort((a, b) => a[1].sort - b[1].sort)
    .map(([value, { label }]) => ({ value, label }));
}

export function semesterOptions(rows: CourseSlotRow[]): FilterOption[] {
  const found = new Map<string, { label: string; sort: number }>();
  for (const row of rows) {
    found.set(row.semesterId, {
      label: row.semesterName,
      sort: row.semesterSort,
    });
  }
  return [...found.entries()]
    .sort((a, b) => a[1].sort - b[1].sort)
    .map(([value, { label }]) => ({ value, label }));
}

export function filterRows(
  rows: CourseSlotRow[],
  levelId: string,
  semesterId: string,
): CourseSlotRow[] {
  return rows.filter(
    (row) =>
      (!levelId || row.levelId === levelId) &&
      (!semesterId || row.semesterId === semesterId),
  );
}

export function groupCourses(rows: CourseSlotRow[]): CourseCardData[] {
  const cards = new Map<string, CourseCardData>();
  for (const row of rows) {
    const slot: CourseSlot = {
      levelId: row.levelId,
      levelName: row.levelName,
      semesterId: row.semesterId,
      semesterName: row.semesterName,
    };
    const existing = cards.get(row.courseId);
    if (existing) {
      existing.slots.push(slot);
    } else {
      cards.set(row.courseId, {
        id: row.courseId,
        code: row.code,
        title: row.title,
        isActive: row.isActive,
        topicCount: row.topicCount,
        slots: [slot],
      });
    }
  }
  return [...cards.values()];
}
