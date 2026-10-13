/**
 * Milestone 1A has no authentication. The admin UI is therefore closed by
 * default and only renders when ADMIN_PREVIEW_ENABLED is exactly "true".
 * Server-only: this variable is not NEXT_PUBLIC_ and never reaches the browser.
 */
export function isAdminPreviewEnabled(): boolean {
  return process.env.ADMIN_PREVIEW_ENABLED === "true";
}
