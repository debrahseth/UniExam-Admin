import { createSupabaseServerClient } from "@/lib/supabase/server";

import { shortId } from "./labels";
import { toEntry } from "./parse";
import type { AuditRow, Person } from "./types";

export const PAGE_SIZE = 25;

export type AuditPageResult =
  | { status: "error" }
  | {
      status: "ok";
      rows: AuditRow[];
      skipped: number;
      nextBefore: number | null;
    };

export async function loadAuditPage(
  before: number | null,
): Promise<AuditPageResult> {
  const supabase = await createSupabaseServerClient();
  const [auditResult, adminsResult] = await Promise.all([
    supabase.rpc("admin_list_audit", {
      p_limit: PAGE_SIZE + 1,
      p_before_id: before,
    }),
    supabase.rpc("admin_list_admins"),
  ]);

  if (auditResult.error || !Array.isArray(auditResult.data)) {
    return { status: "error" };
  }

  const emails = new Map<string, string>();
  if (!adminsResult.error && Array.isArray(adminsResult.data)) {
    for (const row of adminsResult.data as unknown[]) {
      if (typeof row !== "object" || row === null) continue;
      const r = row as Record<string, unknown>;
      if (typeof r.user_id === "string" && typeof r.email === "string") {
        emails.set(r.user_id, r.email);
      }
    }
  }
  const who = (id: string): Person => {
    const email = emails.get(id);
    return email
      ? { label: email, known: true }
      : { label: shortId(id), known: false };
  };

  const rawRows = auditResult.data as unknown[];
  const hasMore = rawRows.length > PAGE_SIZE;
  const pageRows = rawRows.slice(0, PAGE_SIZE);
  const entries = pageRows
    .map(toEntry)
    .filter(
      (entry): entry is NonNullable<ReturnType<typeof toEntry>> =>
        entry !== null,
    );
  const nextBefore =
    hasMore && entries.length > 0 ? entries[entries.length - 1].id : null;

  return {
    status: "ok",
    skipped: pageRows.length - entries.length,
    nextBefore,
    rows: entries.map((entry) => ({
      id: entry.id,
      occurredAt: entry.occurredAt,
      action: entry.action,
      actor:
        entry.actorKind === "operator" || !entry.actorUserId
          ? null
          : who(entry.actorUserId),
      target: who(entry.targetUserId),
      before: entry.before,
      after: entry.after,
      reason: entry.reason,
    })),
  };
}
