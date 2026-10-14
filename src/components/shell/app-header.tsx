import { AppBreadcrumbs } from "@/components/shell/app-breadcrumbs";
import { SignOutButton } from "@/components/shell/sign-out-button";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { SidebarTrigger } from "@/components/ui/sidebar";

export function AppHeader({ email }: { email: string | null }) {
  return (
    <header className="sticky top-0 z-30 flex h-14 shrink-0 items-center gap-2 border-b bg-background/95 px-4 supports-backdrop-filter:backdrop-blur">
      <SidebarTrigger className="-ml-1" />
      <Separator
        orientation="vertical"
        className="mr-2 data-[orientation=vertical]:h-4"
      />
      <AppBreadcrumbs />
      <div className="ml-auto flex items-center gap-2">
        {email ? (
          <Badge variant="outline" className="hidden max-w-56 sm:inline-flex">
            <span className="truncate">{email}</span>
          </Badge>
        ) : null}
        <SignOutButton />
      </div>
    </header>
  );
}
