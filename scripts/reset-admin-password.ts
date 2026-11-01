import { createClient } from "@supabase/supabase-js";
import dotenv from "dotenv";

dotenv.config({ path: ".env.local" });

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
);

async function resetPassword() {
  const { error } = await supabaseAdmin.auth.admin.updateUserById(
    "ADMIN_UUID",
    {
      password: "Your New Password",
    },
  );

  if (error) {
    console.error("Password reset failed:", error.message);
    process.exit(1);
  }

  console.log("Admin password successfully reset!");
}

resetPassword();
