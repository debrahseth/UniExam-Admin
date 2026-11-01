"use client";

import { ArrowLeftIcon } from "lucide-react";
import { useRouter } from "next/navigation";

import { Button } from "@/components/ui/button";

export function GoBackButton() {
  const router = useRouter();

  return (
    <Button
      type="button"
      variant="outline"
      size="lg"
      className="px-4"
      onClick={() => {
        if (window.history.length > 1) router.back();
        else router.push("/");
      }}
    >
      <ArrowLeftIcon aria-hidden="true" />
      Go back
    </Button>
  );
}
