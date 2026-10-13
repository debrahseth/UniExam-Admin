import { PageHeader } from "@/components/shell/page-header";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export const metadata = { title: "Dashboard" };

export default function AdminDashboardPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Dashboard"
        description="Overview of the UniExam platform. Live figures arrive once authentication and data access are in place."
      />
      <Card>
        <CardHeader>
          <CardTitle className="type-card-title">Not connected</CardTitle>
          <CardDescription>
            This build has no Supabase connection and shows no real data.
          </CardDescription>
        </CardHeader>
        <CardContent className="type-body text-muted-foreground">
          Sign-in, role checks and the audit log are part of Milestone 1B.
        </CardContent>
      </Card>
    </div>
  );
}
