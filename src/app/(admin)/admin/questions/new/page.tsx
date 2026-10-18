import type { Metadata } from "next";

import { ForbiddenState } from "@/components/shell/forbidden-state";
import { PageHeader } from "@/components/shell/page-header";
import { getAdminContext } from "@/lib/admin-access";

import { QuestionEditor } from "@/features/questions/editor/question-editor";

export const metadata: Metadata = { title: "New question" };

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
        title="New question"
        description="Saved as a draft. You submit it for review from the next page."
      />
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
    </div>
  );
}
