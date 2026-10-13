import { FileQuestion } from "lucide-react";
import Link from "next/link";

import { StateMessage } from "@/components/shell/state-message";
import { buttonVariants } from "@/components/ui/button";

export const metadata = { title: "Page not found" };

export default function NotFound() {
  return (
    <StateMessage
      icon={FileQuestion}
      title="Page not found"
      description="This page doesn't exist, or it isn't available in this build."
    >
      <Link href="/" className={buttonVariants({ variant: "outline" })}>
        Go to start
      </Link>
    </StateMessage>
  );
}
