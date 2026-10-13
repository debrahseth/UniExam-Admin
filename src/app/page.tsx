import { Lock } from "lucide-react";
import { redirect } from "next/navigation";
import { connection } from "next/server";

import { StateMessage } from "@/components/shell/state-message";
import { Button } from "@/components/ui/button";
import { isAdminPreviewEnabled } from "@/lib/admin-preview";

export default async function HomePage() {
  await connection();
  if (isAdminPreviewEnabled()) redirect("/admin");

  return (
    <main>
      <StateMessage
        icon={Lock}
        title="UniExam Admin"
        description="Admin sign-in isn't available in this build yet. Access will be limited to provisioned administrators."
      >
        <Button disabled>Sign in</Button>
      </StateMessage>
    </main>
  );
}
