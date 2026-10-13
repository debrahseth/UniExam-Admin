"use client";

import { TriangleAlert } from "lucide-react";

import { StateMessage } from "@/components/shell/state-message";
import { Button } from "@/components/ui/button";

export default function AdminError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  // Never render error.message: it can carry internal details.
  return (
    <StateMessage
      icon={TriangleAlert}
      title="Something went wrong"
      description="This page couldn't be loaded. Try again, and if it keeps happening, report the reference below."
    >
      <Button onClick={reset}>Try again</Button>
      {error.digest ? (
        <span className="type-helper text-muted-foreground">
          Reference: {error.digest}
        </span>
      ) : null}
    </StateMessage>
  );
}
