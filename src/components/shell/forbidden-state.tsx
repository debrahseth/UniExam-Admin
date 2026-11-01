import { ShieldAlert } from "lucide-react";

import { StateMessage } from "@/components/shell/state-message";

export function ForbiddenState() {
  return (
    <StateMessage
      icon={ShieldAlert}
      title="You don't have access to this page"
      description="Your admin role doesn't include this area. If you think this is a mistake, ask a Super Admin to review your access."
    />
  );
}
