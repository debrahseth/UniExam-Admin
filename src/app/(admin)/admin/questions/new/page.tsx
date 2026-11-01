import type { Metadata } from "next";

import { ForbiddenState } from "@/components/shell/forbidden-state";
import { PageHeader } from "@/components/shell/page-header";
import { getAdminContext } from "@/lib/admin-access";

import { QuestionEditor } from "@/features/questions/editor/question-editor";
import { NewQuestionTabs } from "@/features/questions/import/new-question-tabs";
import { QuestionImport } from "@/features/questions/import/question-import";

export const metadata: Metadata = { title: "New Question" };

export default async function NewQuestionPage() {
  const { access } = await getAdminContext();
  if (
    access.state !== "active" ||
    (access.role !== "super_admin" && access.role !== "academic_admin")
  ) {
    return <ForbiddenState />;
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="New Question"
        description="Add one question, or import a whole file. Everything is saved as a draft under your name; you submit it for review afterwards."
      />
      <NewQuestionTabs
        single={
          <QuestionEditor
            mode="create"
            topics={[]}
            initial={{
              courseId: "",
              topicId: "",
              stem: "",
              options: ["", ""],
              correctIndex: -1,
              explanation: "",
              difficulty: "",
            }}
            submitLabel="Save draft"
            cancelHref="/admin/questions"
          />
        }
        importer={<QuestionImport />}
      />
    </div>
  );
}
