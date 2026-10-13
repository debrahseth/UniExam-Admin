import type { Metadata } from "next";

import { ForbiddenState } from "@/components/shell/forbidden-state";
import { PageHeader } from "@/components/shell/page-header";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getAdminContext } from "@/lib/admin-access";
import { isAdminRole, isAdminStatus } from "@/lib/admin-roles";
import { createSupabaseServerClient } from "@/lib/supabase/server";

import { AdminsTable } from "@/features/access/admins-table";
import { LookupGrant } from "@/features/access/lookup-grant";
import type { AdminRow } from "@/features/access/types";

export const metadata: Metadata = { title: "Admin access" };

function toAdminRow(row: unknown): AdminRow | null {
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  if (
    typeof r.user_id !== "string" ||
    typeof r.email !== "string" ||
    typeof r.created_at !== "string" ||
    !isAdminRole(r.role) ||
    !isAdminStatus(r.status)
  ) {
    return null;
  }
  return {
    userId: r.user_id,
    email: r.email,
    role: r.role,
    status: r.status,
    createdAt: r.created_at,
  };
}

export default async function AccessPage() {
  const { access } = await getAdminContext();
  if (access.state !== "active" || access.role !== "super_admin") {
    return <ForbiddenState />;
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("admin_list_admins");

  const admins =
    !error && Array.isArray(data)
      ? data.map(toAdminRow).filter((row): row is AdminRow => row !== null)
      : null;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Admin access"
        description="Grant, change, suspend and revoke administrator access. Every change needs a reason and is recorded in the audit log."
      />

      <LookupGrant />

      <Card>
        <CardHeader>
          <CardTitle className="type-card-title">Administrators</CardTitle>
          <CardDescription>
            Roles and status are read live from the database.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {admins ? (
            <AdminsTable admins={admins} />
          ) : (
            <p role="alert" className="type-body text-muted-foreground">
              The administrator list could not be loaded. Reload the page. If
              this keeps happening, sign out and sign in again.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
