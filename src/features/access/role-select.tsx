"use client";

import { ChevronDownIcon } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { AdminRole } from "@/config/navigation";
import { ROLE_LABELS } from "@/lib/admin-roles";

type RoleSelectProps = {
  id: string;
  name: string;
  roles: readonly AdminRole[];
  defaultValue?: AdminRole;
  disabled?: boolean;
  className?: string;
};

export function RoleSelect({
  id,
  name,
  roles,
  defaultValue,
  disabled,
  className,
}: RoleSelectProps) {
  const [value, setValue] = useState<AdminRole | undefined>(
    defaultValue ?? roles[0],
  );

  return (
    <>
      <input type="hidden" name={name} value={value ?? ""} />
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <Button
              id={id}
              type="button"
              variant="outline"
              size="lg"
              disabled={disabled}
              className={`w-full justify-between px-2.5 font-normal ${className ?? ""}`}
            />
          }
        >
          <span className="truncate">
            {value ? ROLE_LABELS[value] : "Select a role"}
          </span>
          <ChevronDownIcon
            aria-hidden="true"
            className="text-muted-foreground"
          />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start">
          <DropdownMenuRadioGroup
            value={value}
            onValueChange={(next) => {
              const match = roles.find((role) => role === next);
              if (match) setValue(match);
            }}
          >
            {roles.map((role) => (
              <DropdownMenuRadioItem key={role} value={role} closeOnClick>
                {ROLE_LABELS[role]}
              </DropdownMenuRadioItem>
            ))}
          </DropdownMenuRadioGroup>
        </DropdownMenuContent>
      </DropdownMenu>
    </>
  );
}
