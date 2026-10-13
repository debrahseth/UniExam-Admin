import { signOut } from "@/app/sign-in/actions";
import { AppBreadcrumbs } from "@/components/shell/app-breadcrumbs";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { SidebarTrigger } from "@/components/ui/sidebar";

export function AppHeader({ email }: { email: string | null }) {
  return (
    <header className="bg-background flex h-14 shrink-0 items-center gap-2 border-b px-4">
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
        <form action={signOut}>
          <Button type="submit" variant="outline" size="sm">
            Sign out
          </Button>
        </form>
      </div>
    </header>
  );
}
