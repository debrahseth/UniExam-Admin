import { redirect } from "next/navigation";

import { getMyAccess } from "@/lib/admin-access";

export default async function HomePage() {
  const access = await getMyAccess();
  redirect(
    access.state === "none" || access.state === "suspended"
      ? "/sign-in"
      : "/admin",
  );
}
