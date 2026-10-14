import {
  CircleAlertIcon,
  CircleCheckIcon,
  InfoIcon,
  TriangleAlertIcon,
} from "lucide-react";
import type { ReactNode } from "react";

const TONES = {
  success: {
    icon: CircleCheckIcon,
    className: "bg-success-muted text-success-muted-foreground",
  },
  error: {
    icon: CircleAlertIcon,
    className: "bg-destructive-muted text-destructive-muted-foreground",
  },
  warning: {
    icon: TriangleAlertIcon,
    className: "bg-warning-muted text-warning-muted-foreground",
  },
  neutral: {
    icon: InfoIcon,
    className: "bg-muted text-muted-foreground",
  },
} as const;

export type InlineMessageTone = keyof typeof TONES;

type InlineMessageProps = {
  tone: InlineMessageTone;
  role?: "alert" | "status";
  children: ReactNode;
};

export function InlineMessage({ tone, role, children }: InlineMessageProps) {
  const { icon: Icon, className } = TONES[tone];

  return (
    <div
      role={role}
      className={`type-description flex items-start gap-2 rounded-lg px-3 py-2.5 ${className}`}
    >
      <Icon aria-hidden="true" className="mt-0.5 size-4 shrink-0" />
      <p className="min-w-0">{children}</p>
    </div>
  );
}
