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

import { EnrollForm } from "./enroll-form";

export const metadata: Metadata = { title: "Set up authenticator" };

export default async function EnrollPage() {
  const access = await getMyAccess();
  if (access.state === "mfa_step_up_required") redirect("/mfa/verify");
  if (access.state === "active") redirect("/admin");
  if (access.state !== "mfa_enrollment_required") redirect("/sign-in");

  return (
    <main className="flex min-h-svh items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle className="type-section-title">
            Set up your authenticator
          </CardTitle>
          <CardDescription className="type-description">
            Administrator accounts require a second step at every sign-in. Use
            an authenticator app on your phone.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <EnrollForm />
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
