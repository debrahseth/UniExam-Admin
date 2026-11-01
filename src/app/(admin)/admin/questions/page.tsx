import type { Metadata } from "next";
import { GraduationCapIcon } from "lucide-react";
import Link from "next/link";

import { ForbiddenState } from "@/components/shell/forbidden-state";
import { PageHeader } from "@/components/shell/page-header";
import { buttonVariants } from "@/components/ui/button";
import { getAdminContext } from "@/lib/admin-access";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { InlineMessage } from "@/features/access/inline-message";
import { ProgrammeBrowser } from "@/features/questions/review/programme-browser";
import {
  toProgramme,
  type Programme,
} from "@/features/questions/review/programmes";

export const metadata: Metadata = { title: "Programme" };

export default async function QuestionsPage() {
  const { access } = await getAdminContext();
  if (
    access.state !== "active" ||
    (access.role !== "super_admin" &&
      access.role !== "academic_admin" &&
      access.role !== "question_reviewer")
  ) {
    return <ForbiddenState />;
  }

  const canAuthor =
    access.role === "super_admin" || access.role === "academic_admin";

  const header = (
    <PageHeader
      title="Programme"
      description="Choose a programme to browse its courses and review their questions."
      actions={
        canAuthor ? (
          <Link
            href="/admin/questions/new"
            className={buttonVariants({ size: "lg" })}
          >
            New question
          </Link>
        ) : undefined
      }
    />
  );

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("admin_catalog_programmes");

  if (error || !Array.isArray(data)) {
    return (
      <div className="space-y-6">
        {header}
        <InlineMessage tone="error" role="alert">
          The programmes could not be loaded. Reload the page. If this keeps
          happening, sign out and sign in again.
        </InlineMessage>
      </div>
    );
  }

  const programmes = data
    .map(toProgramme)
    .filter((p): p is Programme => p !== null);
  const skipped = data.length - programmes.length;

  return (
    <div className="space-y-6">
      {header}

      {skipped > 0 ? (
        <InlineMessage tone="error" role="alert">
          {skipped} {skipped === 1 ? "programme" : "programmes"} could not be
          displayed.
        </InlineMessage>
      ) : null}

      {programmes.length === 0 ? (
        <div className="flex flex-col items-center gap-3 rounded-lg border border-dashed px-4 py-10 text-center">
          <GraduationCapIcon
            aria-hidden="true"
            className="size-5 text-muted-foreground"
          />
          <p className="type-body text-muted-foreground">
            There are no programmes yet.
          </p>
        </div>
      ) : (
        <ProgrammeBrowser programmes={programmes} />
      )}
    </div>
  );
}
