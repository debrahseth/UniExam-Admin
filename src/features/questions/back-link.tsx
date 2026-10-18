import { ArrowLeftIcon } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";

import { buttonVariants } from "@/components/ui/button";

export function BackLink({
  href,
  children,
}: {
  href: string;
  children: ReactNode;
}) {
  return (
    <div>
      <Link
        href={href}
        className={buttonVariants({ variant: "ghost", size: "sm" })}
      >
        <ArrowLeftIcon aria-hidden="true" />
        {children}
      </Link>
    </div>
  );
}
