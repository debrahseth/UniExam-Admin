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

export type SelectMenuOption = { value: string; label: string };

type SelectMenuProps = {
  id: string;
  name?: string;
  options: readonly SelectMenuOption[];
  defaultValue?: string;
  value?: string;
  onValueChange?: (value: string) => void;
  placeholder?: string;
  disabled?: boolean;
  className?: string;
};

export function SelectMenu({
  id,
  name,
  options,
  defaultValue = "",
  value: controlledValue,
  onValueChange,
  placeholder = "Select…",
  disabled,
  className,
}: SelectMenuProps) {
  const [internal, setInternal] = useState(defaultValue);
  const value = controlledValue ?? internal;
  const selected = options.find((option) => option.value === value);

  function change(next: string) {
    if (controlledValue === undefined) setInternal(next);
    onValueChange?.(next);
  }

  return (
    <>
      {name ? <input type="hidden" name={name} value={value} /> : null}
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
          <span
            className={`min-w-0 truncate ${selected ? "" : "text-muted-foreground"}`}
          >
            {selected ? selected.label : placeholder}
          </span>
          <ChevronDownIcon
            aria-hidden="true"
            className="text-muted-foreground"
          />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" className="max-h-72">
          <DropdownMenuRadioGroup
            value={value}
            onValueChange={(next) => {
              const match = options.find((option) => option.value === next);
              if (match) change(match.value);
            }}
          >
            {options.map((option) => (
              <DropdownMenuRadioItem
                key={option.value}
                value={option.value}
                closeOnClick
              >
                {option.label}
              </DropdownMenuRadioItem>
            ))}
          </DropdownMenuRadioGroup>
        </DropdownMenuContent>
      </DropdownMenu>
    </>
  );
}
