import type { Metadata } from "next";
import {
  ClipboardListIcon,
  GraduationCapIcon,
  LockIcon,
  ShieldCheckIcon,
} from "lucide-react";
import { redirect } from "next/navigation";

import { getMyAccess } from "@/lib/admin-access";

import { SignInForm } from "@/features/sign-in/sign-in-form";

export const metadata: Metadata = { title: "Sign in" };

function Brand() {
  return (
    <div className="flex items-center gap-2.5">
      <span className="flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
        <GraduationCapIcon aria-hidden="true" className="size-5" />
      </span>
      <span className="type-card-title">UniExam Admin</span>
    </div>
  );
}

const CONTEXT_POINTS = [
  {
    icon: ShieldCheckIcon,
    text: "Access is limited to accounts that have been granted administrator access.",
  },
  {
    icon: ClipboardListIcon,
    text: "Changes to administrator access are recorded in an audit log.",
  },
];

export default async function SignInPage() {
  const access = await getMyAccess();
  if (access.state !== "none" && access.state !== "suspended") {
    redirect("/admin");
  }

  return (
    <main className="grid min-h-svh lg:grid-cols-[5fr_6fr]">
      <div className="relative hidden flex-col justify-between overflow-hidden border-r bg-muted/50 p-12 lg:flex">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 opacity-60 bg-[linear-gradient(to_right,var(--border)_1px,transparent_1px),linear-gradient(to_bottom,var(--border)_1px,transparent_1px)] bg-size-[40px_40px] mask-[radial-gradient(ellipse_at_center,black_20%,transparent_75%)]"
        />

        <div className="relative">
          <Brand />
        </div>

        <div className="relative max-w-md">
          <h2 className="type-page-title">Secure access to UniExam Admin</h2>
          <p className="type-body mt-2 text-muted-foreground">
            The administration workspace for the UniExam examination simulator,
            for authorized administrators only.
          </p>
          <ul className="mt-8 space-y-3">
            {CONTEXT_POINTS.map(({ icon: Icon, text }) => (
              <li key={text} className="flex items-start gap-3">
                <span className="flex size-7 shrink-0 items-center justify-center rounded-md border bg-card text-primary">
                  <Icon aria-hidden="true" className="size-4" />
                </span>
                <span className="type-description pt-1 text-muted-foreground">
                  {text}
                </span>
              </li>
            ))}
          </ul>
        </div>
      </div>

      <div className="flex items-center justify-center px-4 py-10 sm:px-8">
        <div className="w-full max-w-sm">
          <div className="mb-8 lg:hidden">
            <Brand />
          </div>

          <div className="space-y-1.5">
            <h1 className="type-page-title">Welcome back</h1>
            <p className="type-description text-muted-foreground">
              Sign in to continue to your admin workspace.
            </p>
          </div>

          <div className="mt-8">
            <SignInForm />
          </div>

          <p className="type-helper mt-6 flex items-center gap-1.5 text-muted-foreground">
            <LockIcon aria-hidden="true" className="size-3 shrink-0" />
            Only accounts with administrator access can sign in.
          </p>
        </div>
      </div>
    </main>
  );
}
