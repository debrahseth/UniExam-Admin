import { Settings } from "lucide-react";

import { PlaceholderPage } from "@/components/shell/placeholder-page";

export const metadata = { title: "Settings" };

export default function SettingsPage() {
  return (
    <PlaceholderPage
      title="Settings"
      description="Admin application settings."
      icon={Settings}
      planned="a later milestone"
    />
  );
}
