export const SUPABASE_AUTH_COOKIE_NAME = "sb-uniexam-admin-auth";

export function getCookieOptions(): {
  name: string;
  path: string;
  sameSite: "lax";
  secure: boolean;
} {
  return {
    name: SUPABASE_AUTH_COOKIE_NAME,
    path: "/",
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
  };
}

export function getSupabaseEnv(): { url: string; anonKey: string } {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    throw new Error("Supabase environment variables are not configured.");
  }

  return { url, anonKey };
}
