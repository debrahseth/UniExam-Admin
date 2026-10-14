"use client";

import { CircleAlertIcon, LoaderCircleIcon } from "lucide-react";
import { useActionState, type ReactNode } from "react";

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
const HELP_ID = "enroll-code-help";
const ERROR_ID = "enroll-code-error";

function ErrorMessage({ id, children }: { id?: string; children: ReactNode }) {
  return (
    <div
      id={id}
      role="alert"
      className="type-description flex items-start gap-2 rounded-lg bg-destructive-muted px-3 py-2.5 text-destructive-muted-foreground"
    >
      <CircleAlertIcon aria-hidden="true" className="mt-0.5 size-4 shrink-0" />
      <p className="min-w-0">{children}</p>
    </div>
  );
}

function Step({
  number,
  title,
  last = false,
  children,
}: {
  number: number;
  title: string;
  last?: boolean;
  children: ReactNode;
}) {
  return (
    <li className={`relative flex gap-4 ${last ? "" : "pb-7"}`}>
      {last ? null : (
        <span
          aria-hidden="true"
          className="absolute top-7 bottom-1 left-3 w-px bg-border"
        />
      )}
      <span
        aria-hidden="true"
        className="relative z-10 flex size-6 shrink-0 items-center justify-center rounded-full bg-accent text-xs font-medium text-accent-foreground ring-1 ring-primary/20"
      >
        {number}
      </span>
      <div className="min-w-0 flex-1 space-y-3">
        <h2 className="type-card-title flex min-h-6 items-center">
          <span className="sr-only">Step {number}: </span>
          {title}
        </h2>
        {children}
      </div>
    </li>
  );
}

function StepText({ children }: { children: ReactNode }) {
  return <p className="type-description text-muted-foreground">{children}</p>;
}

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
    <div className="flex flex-col gap-6">
      <ol role="list" className="flex flex-col">
        <Step number={1} title="Open an authenticator app">
          <StepText>
            Use an authenticator app on your phone, then choose to add a new
            account.
          </StepText>
        </Step>

        <Step number={2} title="Scan the QR code">
          {start.status === "ready" ? (
            <div className="flex flex-col gap-4">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={start.qrCode}
                alt="QR code for your authenticator app"
                className="mx-auto size-44 rounded-lg border bg-white p-3 shadow-xs sm:size-52"
              />
              <div className="space-y-2 rounded-lg border bg-muted/30 p-3">
                <p className="type-label">Can&apos;t scan the code?</p>
                <p className="type-helper text-muted-foreground">
                  Enter this key manually. Store it in your password manager: it
                  is the only way to rebuild this authenticator if you lose your
                  phone.
                </p>
                <code className="type-helper block rounded-md border bg-card p-2 font-mono tracking-wide break-all select-all">
                  {start.secret}
                </code>
              </div>
            </div>
          ) : (
            <StepText>
              A QR code will appear here after you begin setup.
            </StepText>
          )}
        </Step>

        <Step number={3} title="Enter the 6-digit code" last>
          {start.status === "ready" ? (
            <form
              action={verifyAction}
              className="flex flex-col gap-4"
              noValidate
            >
              <input type="hidden" name="factorId" value={start.factorId} />
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
                  disabled={verifying}
                  spellCheck={false}
                  placeholder="000000"
                  aria-invalid={verify.error ? true : undefined}
                  aria-describedby={
                    verify.error ? `${HELP_ID} ${ERROR_ID}` : HELP_ID
                  }
                  className="h-11 text-center font-mono text-xl font-medium tracking-[0.3em] tabular-nums placeholder:font-normal placeholder:tracking-[0.3em] placeholder:text-muted-foreground/60 md:text-xl"
                />
                <p id={HELP_ID} className="type-helper text-muted-foreground">
                  Enter the current code shown in your authenticator app.
                </p>
              </div>

              {verify.error ? (
                <ErrorMessage id={ERROR_ID}>{verify.error}</ErrorMessage>
              ) : null}

              <Button
                type="submit"
                size="lg"
                className="w-full"
                disabled={verifying}
                aria-busy={verifying}
              >
                {verifying ? (
                  <LoaderCircleIcon
                    aria-hidden="true"
                    className="animate-spin"
                  />
                ) : null}
                {verifying ? "Verifying…" : "Verify and continue"}
              </Button>
            </form>
          ) : (
            <StepText>Enter the code your app shows to finish setup.</StepText>
          )}
        </Step>
      </ol>

      {start.status === "error" ? (
        <ErrorMessage>{start.message}</ErrorMessage>
      ) : null}

      <form action={startAction}>
        <Button
          type="submit"
          size="lg"
          className="w-full"
          variant={start.status === "ready" ? "outline" : "default"}
          disabled={starting}
          aria-busy={starting}
        >
          {starting ? (
            <LoaderCircleIcon aria-hidden="true" className="animate-spin" />
          ) : null}
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
