import { redirect } from "next/navigation";
import type { ReactNode } from "react";

import { AppHeader } from "@/components/shell/app-header";
import { AppSidebar } from "@/components/shell/app-sidebar";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { getAdminContext } from "@/lib/admin-access";

export default async function AdminLayout({
  children,
}: {
  children: ReactNode;
}) {
  const { access, email } = await getAdminContext();

  if (access.state === "mfa_enrollment_required") redirect("/mfa/enroll");
  if (access.state === "mfa_step_up_required") redirect("/mfa/verify");
  if (access.state !== "active") redirect("/sign-in");

  return (
    <SidebarProvider>
      <AppSidebar role={access.role} />
      <SidebarInset>
        <AppHeader email={email} />
        <main className="flex-1 p-4 md:p-6">{children}</main>
      </SidebarInset>
    </SidebarProvider>
  );
}
