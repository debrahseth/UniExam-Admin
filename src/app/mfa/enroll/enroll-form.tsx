"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

import {
  startEnrollment,
  verifyEnrollment,
  type CodeState,
  type EnrollmentStart,
} from "../actions";

const startInitial: EnrollmentStart = { status: "idle" };
const verifyInitial: CodeState = { error: null };

export function EnrollForm() {
  const [start, startAction, starting] = useActionState(
    startEnrollment,
    startInitial,
  );
  const [verify, verifyAction, verifying] = useActionState(
    verifyEnrollment,
    verifyInitial,
  );

  return (
    <div className="flex flex-col gap-4">
      {start.status === "ready" ? (
        <>
          <ol className="type-body flex list-decimal flex-col gap-1 pl-5">
            <li>Scan this code with your authenticator app.</li>
            <li>Enter the 6-digit code the app shows.</li>
          </ol>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={start.qrCode}
            alt="QR code for your authenticator app"
            className="mx-auto size-48 rounded-md border bg-white p-2"
          />
          <div className="space-y-1">
            <p className="type-helper text-muted-foreground">
              Can&apos;t scan? Enter this key manually. Store it in your
              password manager: it is the only way to rebuild this authenticator
              if you lose your phone.
            </p>
            <code className="type-helper block break-all rounded-md border p-2">
              {start.secret}
            </code>
          </div>
          <form
            action={verifyAction}
            className="flex flex-col gap-3"
            noValidate
          >
            <input type="hidden" name="factorId" value={start.factorId} />
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
                disabled={verifying}
              />
            </div>
            {verify.error ? (
              <p role="alert" className="type-helper text-destructive">
                {verify.error}
              </p>
            ) : null}
            <Button type="submit" disabled={verifying}>
              {verifying ? "Verifying…" : "Verify and continue"}
            </Button>
          </form>
        </>
      ) : null}

      {start.status === "error" ? (
        <p role="alert" className="type-helper text-destructive">
          {start.message}
        </p>
      ) : null}

      <form action={startAction}>
        <Button
          type="submit"
          variant={start.status === "ready" ? "outline" : "default"}
          disabled={starting}
        >
          {starting
            ? "Preparing…"
            : start.status === "ready"
              ? "Start over"
              : "Begin setup"}
        </Button>
      </form>
    </div>
  );
}
