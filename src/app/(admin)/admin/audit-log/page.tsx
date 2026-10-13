import { ScrollText } from "lucide-react";

import { PlaceholderPage } from "@/components/shell/placeholder-page";

export const metadata = { title: "Audit log" };

export default function AuditLogPage() {
  return (
    <PlaceholderPage
      title="Audit log"
      description="An append-only record of sensitive admin actions."
      icon={ScrollText}
      planned="Milestone 1B"
    />
  );
}
