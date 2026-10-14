import type { Metadata } from "next";
import { GraduationCapIcon, LogOutIcon, ShieldCheckIcon } from "lucide-react";
import { redirect } from "next/navigation";

import { signOut } from "@/features/sign-in/actions";
import { Button } from "@/components/ui/button";
import { getMyAccess } from "@/lib/admin-access";

import { VerifyForm } from "./verify-form";

export const metadata: Metadata = { title: "Verify your identity" };

export default async function VerifyPage() {
  const access = await getMyAccess();
  if (access.state === "mfa_enrollment_required") redirect("/mfa/enroll");
  if (access.state === "active") redirect("/admin");
  if (access.state !== "mfa_step_up_required") redirect("/sign-in");

  return (
    <main className="flex min-h-svh items-center justify-center px-4 py-10 sm:px-8">
      <div className="w-full max-w-sm">
        <div className="mb-8 flex items-center gap-2.5">
          <span className="flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
            <GraduationCapIcon aria-hidden="true" className="size-5" />
          </span>
          <span className="type-card-title">UniExam Admin</span>
        </div>

        <div className="space-y-1.5">
          <h1 className="type-page-title">Verify your identity</h1>
          <p className="type-description text-muted-foreground">
            Enter the 6-digit code from your authenticator app to continue to
            UniExam Admin.
          </p>
        </div>

        <div className="mt-8">
          <VerifyForm />
        </div>

        <div className="mt-2 flex flex-col gap-4 border-t pt-4">
          <form action={signOut}>
            <Button type="submit" variant="ghost" size="lg" className="w-full">
              <LogOutIcon aria-hidden="true" />
              Sign out
            </Button>
          </form>
          <p className="type-helper flex items-center justify-center gap-1.5 text-muted-foreground">
            <ShieldCheckIcon aria-hidden="true" className="size-3 shrink-0" />
            This extra step helps protect administrator access.
          </p>
        </div>
      </div>
    </main>
  );
}
