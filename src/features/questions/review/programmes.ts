export type Programme = {
  id: string;
  code: string;
  name: string;
  isActive: boolean;
  courseCount: number;
};

function toCount(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value) && value >= 0) {
    return value;
  }
  if (typeof value === "string" && /^\d{1,9}$/.test(value))
    return Number(value);
  return null;
}

export function toProgramme(row: unknown): Programme | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  const courseCount = toCount(r.course_count);

  if (
    typeof r.programme_id !== "string" ||
    typeof r.code !== "string" ||
    typeof r.name !== "string" ||
    typeof r.is_active !== "boolean" ||
    courseCount === null
  ) {
    return null;
  }

  return {
    id: r.programme_id,
    code: r.code,
    name: r.name,
    isActive: r.is_active,
    courseCount,
  };
}
