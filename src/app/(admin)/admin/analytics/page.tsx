import { BarChart3 } from "lucide-react";

import { PlaceholderPage } from "@/components/shell/placeholder-page";

export const metadata = { title: "Analytics" };

export default function AnalyticsPage() {
  return (
    <PlaceholderPage
      title="Analytics"
      description="Read-only platform and performance reporting."
      icon={BarChart3}
      planned="a later milestone"
    />
  );
}
