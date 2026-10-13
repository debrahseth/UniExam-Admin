import { ShieldCheck } from "lucide-react";

import { PlaceholderPage } from "@/components/shell/placeholder-page";

export const metadata = { title: "Admin access" };

export default function AccessPage() {
  return (
    <PlaceholderPage
      title="Admin access"
      description="Grant, change, suspend or revoke admin roles. Super Admin only."
      icon={ShieldCheck}
      planned="Milestone 1B"
    />
  );
}
