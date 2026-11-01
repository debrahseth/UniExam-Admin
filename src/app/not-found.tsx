import type { Metadata } from "next";
import { FileQuestion } from "lucide-react";
import Link from "next/link";

import { GoBackButton } from "@/components/shell/go-back-button";
import { buttonVariants } from "@/components/ui/button";

export const metadata: Metadata = { title: "Page not found" };

const TIPS = [
  "Check the address for typing mistakes.",
  "Go back and use the menu to find the page you need.",
  "If you followed a link or a bookmark, the page may have moved or may not be available yet.",
];

export default function NotFound() {
  return (
    <section className="relative isolate flex min-h-[max(24rem,70svh)] items-center justify-center overflow-hidden px-4 py-16">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 -z-10 opacity-50 bg-[linear-gradient(to_right,var(--border)_1px,transparent_1px),linear-gradient(to_bottom,var(--border)_1px,transparent_1px)] bg-size-[40px_40px] mask-[radial-gradient(ellipse_at_center,black_15%,transparent_70%)]"
      />

      <div className="mx-auto flex w-full max-w-md flex-col items-center text-center">
        <div className="mb-6 flex size-16 items-center justify-center rounded-2xl border bg-card shadow-xs">
          <FileQuestion aria-hidden="true" className="size-7 text-primary" />
        </div>

        <p className="type-meta tracking-widest text-muted-foreground uppercase">
          Error 404
        </p>
        <h1 className="type-page-title mt-2">We can&apos;t find that page</h1>
        <p className="type-body mt-3 text-muted-foreground">
          The page you&apos;re looking for doesn&apos;t exist, or it isn&apos;t
          available yet.
        </p>

        <div className="mt-8 flex w-full flex-col-reverse gap-3 sm:w-auto sm:flex-row">
          <GoBackButton />
          <Link
            href="/"
            className={buttonVariants({ size: "lg", className: "px-4" })}
          >
            Go to the start page
          </Link>
        </div>

        <div className="mt-10 w-full rounded-lg border bg-card/60 p-4 text-left">
          <h2 className="type-label">Things to try</h2>
          <ul className="mt-2 flex flex-col gap-2">
            {TIPS.map((tip) => (
              <li
                key={tip}
                className="type-description flex items-start gap-2.5 text-muted-foreground"
              >
                <span
                  aria-hidden="true"
                  className="mt-2 size-1 shrink-0 rounded-full bg-muted-foreground/60"
                />
                {tip}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
