"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

import { verifyStepUp, type CodeState } from "../actions";

const initialState: CodeState = { error: null };

export function VerifyForm() {
  const [state, formAction, pending] = useActionState(
    verifyStepUp,
    initialState,
  );

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <div className="flex flex-col gap-2">
        <Label htmlFor="code" className="type-label">
          6-digit code
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
        />
      </div>
      {state.error ? (
        <p role="alert" className="type-helper text-destructive">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" disabled={pending}>
        {pending ? "Verifying…" : "Verify"}
      </Button>
    </form>
  );
}
