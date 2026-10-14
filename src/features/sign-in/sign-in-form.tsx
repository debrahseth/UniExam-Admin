"use client";

import {
  CircleAlertIcon,
  EyeIcon,
  EyeOffIcon,
  LoaderCircleIcon,
} from "lucide-react";
import { useActionState, useState } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

import { signIn, type SignInState } from "./actions";

const initialState: SignInState = { error: null };
const ERROR_ID = "sign-in-error";

export function SignInForm() {
  const [state, formAction, pending] = useActionState(signIn, initialState);
  const [showPassword, setShowPassword] = useState(false);

  const invalid = state.error ? true : undefined;
  const describedBy = state.error ? ERROR_ID : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-5" noValidate>
      <div className="flex flex-col gap-2">
        <Label htmlFor="email" className="type-label">
          Email
        </Label>
        <Input
          id="email"
          name="email"
          type="email"
          autoComplete="username"
          autoCapitalize="none"
          spellCheck={false}
          placeholder="name@example.com"
          required
          disabled={pending}
          aria-invalid={invalid}
          aria-describedby={describedBy}
          className="h-9"
        />
      </div>

      <div className="flex flex-col gap-2">
        <Label htmlFor="password" className="type-label">
          Password
        </Label>
        <div className="relative">
          <Input
            id="password"
            name="password"
            type={showPassword ? "text" : "password"}
            autoComplete="current-password"
            required
            disabled={pending}
            aria-invalid={invalid}
            aria-describedby={describedBy}
            className="h-9 pr-10"
          />
          <Button
            type="button"
            variant="ghost"
            size="icon-sm"
            className="absolute top-1 right-1 text-muted-foreground"
            onClick={() => setShowPassword((visible) => !visible)}
            disabled={pending}
            aria-label={showPassword ? "Hide password" : "Show password"}
            aria-pressed={showPassword}
          >
            {showPassword ? (
              <EyeOffIcon aria-hidden="true" />
            ) : (
              <EyeIcon aria-hidden="true" />
            )}
          </Button>
        </div>
      </div>

      <Button
        type="submit"
        size="lg"
        className="w-full"
        disabled={pending}
        aria-busy={pending}
      >
        {pending ? (
          <LoaderCircleIcon aria-hidden="true" className="animate-spin" />
        ) : null}
        {pending ? "Signing in…" : "Sign in"}
      </Button>

      {/* Reserved height so the layout does not jump when an error appears. */}
      <div className="-mt-1 min-h-15">
        {state.error ? (
          <div
            id={ERROR_ID}
            role="alert"
            className="type-description flex items-start gap-2 rounded-lg bg-destructive-muted px-3 py-2.5 text-destructive-muted-foreground"
          >
            <CircleAlertIcon
              aria-hidden="true"
              className="mt-0.5 size-4 shrink-0"
            />
            <p className="min-w-0">{state.error}</p>
          </div>
        ) : null}
      </div>
    </form>
  );
}
