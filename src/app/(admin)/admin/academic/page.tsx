import { GraduationCap } from "lucide-react";

import { PlaceholderPage } from "@/components/shell/placeholder-page";

export const metadata = { title: "Academic structure" };

export default function AcademicPage() {
  return (
    <PlaceholderPage
      title="Academic structure"
      description="Manage universities, programmes, levels, semesters, courses and topics."
      icon={GraduationCap}
      planned="a later milestone"
    />
  );
}
