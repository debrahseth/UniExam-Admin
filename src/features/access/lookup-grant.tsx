"use client";

import {
  LoaderCircleIcon,
  SearchIcon,
  ShieldCheckIcon,
  UserPlusIcon,
} from "lucide-react";
import { useState, useTransition, type FormEvent, type ReactNode } from "react";

import { TextArea } from "@/components/shell/form-fields";
import { RoleSelect } from "./role-select";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ASSIGNABLE_ROLES, ROLE_LABELS } from "@/lib/admin-roles";
import { formatUtc } from "@/lib/format";

import { findUser, grantAdmin } from "./actions";
import { InlineMessage } from "./inline-message";
import type { FoundUser, LookupResult } from "./types";

function blockedReason(user: FoundUser): string | null {
  if (!user.emailConfirmed) {
    return "This account has not confirmed its email address, so it cannot be granted access.";
  }
  if (user.isStudent) {
    return "This account has a student profile and cannot be an administrator. Use an account created only for administration.";
  }
  if (user.accessStatus === "active" || user.accessStatus === "suspended") {
    const role = user.accessRole
      ? ROLE_LABELS[user.accessRole]
      : "administrator";
    return `This account is already an administrator (${role}, ${user.accessStatus}). Manage it from the table below.`;
  }
  return null;
}

function SummaryRow({
  label,
  children,
  breakAll = false,
}: {
  label: string;
  children: ReactNode;
  breakAll?: boolean;
}) {
  return (
    <div className="grid gap-0.5 sm:grid-cols-[7rem_1fr] sm:gap-x-4">
      <dt className="type-body text-muted-foreground">{label}</dt>
      <dd className={`type-body ${breakAll ? "font-medium break-all" : ""}`}>
        {children}
      </dd>
    </div>
  );
}

export function LookupGrant() {
  const [result, setResult] = useState<LookupResult | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [grantError, setGrantError] = useState<string | null>(null);
  const [formKey, setFormKey] = useState(0);
  const [searching, startSearch] = useTransition();
  const [granting, startGrant] = useTransition();

  function onSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    setNotice(null);
    setGrantError(null);
    startSearch(async () => {
      setResult(await findUser(formData));
    });
  }

  function onGrant(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    setGrantError(null);
    startGrant(async () => {
      const outcome = await grantAdmin(formData);
      if (outcome.ok) {
        setNotice(outcome.message);
        setResult(null);
        setFormKey((key) => key + 1);
      } else {
        setGrantError(outcome.message);
      }
    });
  }

  const user = result?.ok ? result.user : null;
  const blocked = user ? blockedReason(user) : null;

  return (
    <Card className="[--card-spacing:--spacing(5)]">
      <CardHeader>
        <CardTitle className="type-card-title flex items-center gap-2">
          <UserPlusIcon aria-hidden="true" className="size-4 text-primary" />
          Add an administrator
        </CardTitle>
        <CardDescription className="max-w-prose">
          Create the account first in Supabase Authentication with a confirmed
          email, then look it up here. Only use accounts created for
          administration.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {notice ? (
          <InlineMessage tone="success" role="status">
            {notice}
          </InlineMessage>
        ) : null}

        <form
          key={formKey}
          onSubmit={onSearch}
          className="flex flex-col gap-3 sm:flex-row sm:items-end"
          noValidate
        >
          <div className="flex flex-1 flex-col gap-2">
            <Label htmlFor="lookup-email" className="type-label">
              Account email
            </Label>
            <div className="relative">
              <SearchIcon
                aria-hidden="true"
                className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
              />
              <Input
                id="lookup-email"
                name="email"
                type="email"
                autoComplete="off"
                autoCapitalize="none"
                spellCheck={false}
                placeholder="name@example.com"
                required
                disabled={searching || granting}
                className="h-9 pl-9"
              />
            </div>
          </div>
          <Button
            type="submit"
            size="lg"
            className="px-4 sm:min-w-28"
            disabled={searching || granting}
            aria-busy={searching}
          >
            {searching ? (
              <LoaderCircleIcon aria-hidden="true" className="animate-spin" />
            ) : null}
            {searching ? "Looking up…" : "Look up"}
          </Button>
        </form>

        {result && !result.ok ? (
          <InlineMessage tone="error" role="alert">
            {result.message}
          </InlineMessage>
        ) : null}

        {result?.ok && result.user === null ? (
          <InlineMessage tone="neutral">
            No account with that email exists. Create it in Supabase
            Authentication first.
          </InlineMessage>
        ) : null}

        {user ? (
          <div className="flex flex-col gap-4 rounded-lg border bg-muted/30 p-4">
            <dl className="flex flex-col gap-3 sm:gap-2">
              <SummaryRow label="Email" breakAll>
                {user.email}
              </SummaryRow>
              <SummaryRow label="Created">
                {formatUtc(user.createdAt)}
              </SummaryRow>
              <SummaryRow label="Last sign-in">
                {formatUtc(user.lastSignInAt)}
              </SummaryRow>
            </dl>

            {blocked ? (
              <InlineMessage tone="warning" role="alert">
                {blocked}
              </InlineMessage>
            ) : (
              <form
                onSubmit={onGrant}
                className="flex flex-col gap-4 border-t pt-4"
                noValidate
              >
                <input type="hidden" name="target" value={user.userId} />
                <div className="flex flex-col gap-2">
                  <Label htmlFor="grant-role" className="type-label">
                    Role
                  </Label>
                  <RoleSelect
                    id="grant-role"
                    name="role"
                    roles={ASSIGNABLE_ROLES}
                    defaultValue={ASSIGNABLE_ROLES[0]}
                    disabled={granting}
                    className="w-full"
                  />
                </div>
                <div className="flex flex-col gap-2">
                  <Label htmlFor="grant-reason" className="type-label">
                    Reason
                  </Label>
                  <TextArea
                    id="grant-reason"
                    name="reason"
                    minLength={10}
                    maxLength={500}
                    required
                    disabled={granting}
                    aria-describedby="grant-reason-help"
                  />
                  <p
                    id="grant-reason-help"
                    className="type-helper text-muted-foreground"
                  >
                    Saved in the audit log. 10 to 500 characters.
                  </p>
                </div>
                {grantError ? (
                  <InlineMessage tone="error" role="alert">
                    {grantError}
                  </InlineMessage>
                ) : null}
                <div>
                  <Button
                    type="submit"
                    size="lg"
                    className="px-4"
                    disabled={granting}
                    aria-busy={granting}
                  >
                    {granting ? (
                      <LoaderCircleIcon
                        aria-hidden="true"
                        className="animate-spin"
                      />
                    ) : (
                      <ShieldCheckIcon aria-hidden="true" />
                    )}
                    {granting ? "Granting…" : "Grant access"}
                  </Button>
                </div>
              </form>
            )}
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
