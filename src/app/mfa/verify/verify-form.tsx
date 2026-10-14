"use client";

import { CircleAlertIcon, LoaderCircleIcon } from "lucide-react";
import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

import { verifyStepUp, type CodeState } from "../actions";

const initialState: CodeState = { error: null };
const HELP_ID = "code-help";
const ERROR_ID = "code-error";

export function VerifyForm() {
  const [state, formAction, pending] = useActionState(
    verifyStepUp,
    initialState,
  );

  return (
    <form action={formAction} className="flex flex-col gap-5" noValidate>
      <div className="flex flex-col gap-2">
        <Label htmlFor="code" className="type-label">
          Verification code
        </Label>
        <Input
          id="code"
          name="code"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9]*"
          maxLength={7}
          required
          autoFocus
          disabled={pending}
          spellCheck={false}
          placeholder="000000"
          aria-invalid={state.error ? true : undefined}
          aria-describedby={state.error ? `${HELP_ID} ${ERROR_ID}` : HELP_ID}
          className="h-11 text-center font-mono text-xl font-medium tracking-[0.3em] tabular-nums placeholder:font-normal placeholder:tracking-[0.3em] placeholder:text-muted-foreground/60 md:text-xl"
        />
        <p id={HELP_ID} className="type-helper text-muted-foreground">
          Open your authenticator app and enter the current 6-digit code.
        </p>
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
        {pending ? "Verifying…" : "Verify and continue"}
      </Button>

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
