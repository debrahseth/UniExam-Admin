// run using npx tsx scripts/list-mfa-factors.ts

import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceRoleKey) {
  throw new Error(
    "Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env.local",
  );
}

const supabase = createClient(url, serviceRoleKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

async function main() {
  // replace this id with the id of the admin you want to get their mfa factor
  const userId = "User ID";

  const { data, error } = await supabase.auth.admin.mfa.listFactors({ userId });

  if (error) {
    throw error;
  }

  console.table(
    data.factors.map((factor) => ({
      id: factor.id,
      type: factor.factor_type,
      status: factor.status,
      name: factor.friendly_name,
    })),
  );
}

main().catch((error) => {
  console.error("Failed to list MFA factors:", error);
  process.exitCode = 1;
});
