import { createSupabaseServerClient } from "@/lib/supabase/server";

import { toCounts, type ListCounts } from "./search";

export type ListFilters = {
  q?: string;
  course?: string;
  topic?: string;
  difficulty?: string;
};

export async function loadCounts(
  filters: ListFilters,
): Promise<ListCounts | null> {
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("admin_question_counts", {
      p_query: filters.q ?? null,
      p_course_id: filters.course ?? null,
      p_topic_id: filters.topic ?? null,
      p_difficulty: filters.difficulty ?? null,
    });
    if (error || !Array.isArray(data) || data.length !== 1) return null;
    return toCounts(data[0]);
  } catch {
    return null;
  }
}
