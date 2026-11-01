export type TopicCardData = {
  id: string | null;
  title: string;
  total: number;
  live: number;
  retired: number;
  draft: number;
  waiting: number;
  mine: number;
};

function toCount(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value) && value >= 0) {
    return value;
  }
  if (typeof value === "string" && /^\d{1,12}$/.test(value))
    return Number(value);
  return null;
}

export function toTopicCard(row: unknown): TopicCardData | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;

  const total = toCount(r.total_count);
  const live = toCount(r.live_count);
  const retired = toCount(r.retired_count);
  const draft = toCount(r.draft_count);
  const waiting = toCount(r.waiting_count);
  const mine = toCount(r.mine_count);

  if (
    (r.topic_id !== null && typeof r.topic_id !== "string") ||
    typeof r.title !== "string" ||
    total === null ||
    live === null ||
    retired === null ||
    draft === null ||
    waiting === null ||
    mine === null
  ) {
    return null;
  }

  return {
    id: r.topic_id as string | null,
    title: r.title,
    total,
    live,
    retired,
    draft,
    waiting,
    mine,
  };
}
