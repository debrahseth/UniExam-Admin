import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { signOut } from "@/app/sign-in/actions";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getMyAccess } from "@/lib/admin-access";

import { VerifyForm } from "./verify-form";

export const metadata: Metadata = { title: "Verify it's you" };

export default async function VerifyPage() {
  const access = await getMyAccess();
  if (access.state === "mfa_enrollment_required") redirect("/mfa/enroll");
  if (access.state === "active") redirect("/admin");
  if (access.state !== "mfa_step_up_required") redirect("/sign-in");

  return (
    <main className="flex min-h-svh items-center justify-center p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="type-section-title">
            Verify it&apos;s you
          </CardTitle>
          <CardDescription className="type-description">
            Enter the 6-digit code from your authenticator app.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <VerifyForm />
          <form action={signOut}>
            <Button type="submit" variant="ghost" size="sm">
              Sign out
            </Button>
          </form>
        </CardContent>
      </Card>
    </main>
  );
}
