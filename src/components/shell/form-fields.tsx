import type { ComponentProps } from "react";

const field =
  "w-full min-w-0 rounded-lg border border-input bg-transparent px-2.5 text-sm transition-colors outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-input/30";

export function NativeSelect({
  className,
  ...props
}: ComponentProps<"select">) {
  return <select className={`${field} h-8 ${className ?? ""}`} {...props} />;
}

export function TextArea({ className, ...props }: ComponentProps<"textarea">) {
  return (
    <textarea
      className={`${field} min-h-20 resize-y py-1.5 ${className ?? ""}`}
      {...props}
    />
  );
}
