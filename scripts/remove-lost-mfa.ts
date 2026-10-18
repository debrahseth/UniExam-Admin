// run using npx tsx scripts/remove-lost-mfa.ts

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
  // userId is replaced
  const userId = "196efb90-f3a7-4fb6-908c-5f6dc00743ae";
  // replace it with the factor you get from the first file
  const factorId = "7b638247-4091-4761-8202-675ae2ac7063";

  const { error } = await supabase.auth.admin.mfa.deleteFactor({
    userId,
    id: factorId,
  });

  if (error) {
    throw error;
  }

  console.log("MFA factor removed successfully.");
}

main().catch((error) => {
  console.error("Failed to remove MFA factor:", error);
  process.exitCode = 1;
});
