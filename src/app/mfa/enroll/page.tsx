import type { Metadata } from "next";
import { GraduationCapIcon, LogOutIcon } from "lucide-react";
import { redirect } from "next/navigation";

import { signOut } from "@/features/sign-in/actions";
import { Button } from "@/components/ui/button";
import { getMyAccess } from "@/lib/admin-access";

import { EnrollForm } from "./enroll-form";

export const metadata: Metadata = { title: "Set up authenticator" };

export default async function EnrollPage() {
  const access = await getMyAccess();
  if (access.state === "mfa_step_up_required") redirect("/mfa/verify");
  if (access.state === "active") redirect("/admin");
  if (access.state !== "mfa_enrollment_required") redirect("/sign-in");

  return (
    <main className="flex min-h-svh justify-center px-4 py-10 sm:px-8 sm:py-16">
      <div className="w-full max-w-md">
        <div className="mb-8 flex items-center gap-2.5">
          <span className="flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
            <GraduationCapIcon aria-hidden="true" className="size-5" />
          </span>
          <span className="type-card-title">UniExam Admin</span>
        </div>

        <div className="space-y-1.5">
          <h1 className="type-page-title">
            Set up multi-factor authentication
          </h1>
          <p className="type-description text-muted-foreground">
            Administrator accounts require a second step at every sign-in. Use
            an authenticator app on your phone.
          </p>
        </div>

        <div className="mt-8">
          <EnrollForm />
        </div>

        <div className="mt-6 border-t pt-4">
          <form action={signOut}>
            <Button type="submit" variant="ghost" size="lg" className="w-full">
              <LogOutIcon aria-hidden="true" />
              Sign out
            </Button>
          </form>
        </div>
      </div>
    </main>
  );
}
