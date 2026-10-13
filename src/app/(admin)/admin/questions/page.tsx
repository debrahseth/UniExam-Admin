import { ClipboardCheck } from "lucide-react";

import { PlaceholderPage } from "@/components/shell/placeholder-page";

export const metadata = { title: "Question review" };

export default function QuestionsPage() {
  return (
    <PlaceholderPage
      title="Question review"
      description="Review, approve and retire questions in the question bank."
      icon={ClipboardCheck}
      planned="a later milestone"
    />
  );
}
