import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";

type StateMessageProps = {
  icon: LucideIcon;
  title: string;
  description: string;
  children?: ReactNode;
};

export function StateMessage({
  icon: Icon,
  title,
  description,
  children,
}: StateMessageProps) {
  return (
    <div className="flex min-h-[50dvh] flex-col items-center justify-center gap-4 px-4 text-center">
      <div className="bg-muted text-muted-foreground flex size-12 items-center justify-center rounded-full">
        <Icon className="size-6" aria-hidden="true" />
      </div>
      <div className="space-y-1">
        <h1 className="type-section-title">{title}</h1>
        <p className="type-description text-muted-foreground max-w-md">
          {description}
        </p>
      </div>
      {children ? (
        <div className="flex items-center gap-2">{children}</div>
      ) : null}
    </div>
  );
}
