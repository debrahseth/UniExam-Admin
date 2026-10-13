import { notFound } from "next/navigation";
import { connection } from "next/server";
import type { ReactNode } from "react";

import { AppHeader } from "@/components/shell/app-header";
import { AppSidebar } from "@/components/shell/app-sidebar";
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar";
import { isAdminPreviewEnabled } from "@/lib/admin-preview";

export default async function AdminLayout({
  children,
}: {
  children: ReactNode;
}) {
  await connection();

  if (!isAdminPreviewEnabled()) notFound();

  return (
    <SidebarProvider>
      <AppSidebar />
      <SidebarInset>
        <AppHeader />
        <main className="flex-1 p-4 md:p-6">{children}</main>
      </SidebarInset>
    </SidebarProvider>
  );
}
