import { LifeBuoy } from "lucide-react";

import { PlaceholderPage } from "@/components/shell/placeholder-page";

export const metadata = { title: "Support" };

export default function SupportPage() {
  return (
    <PlaceholderPage
      title="Support"
      description="Help students with account and examination issues."
      icon={LifeBuoy}
      planned="a later milestone"
    />
  );
}
