"use client";

import { useState, useTransition, type FormEvent } from "react";

import { NativeSelect, TextArea } from "@/components/shell/form-fields";
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
    <Card>
      <CardHeader>
        <CardTitle className="type-card-title">Add an administrator</CardTitle>
        <CardDescription>
          Create the account first in Supabase Authentication with a confirmed
          email, then look it up here. Only use accounts created for
          administration.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {notice ? (
          <p role="status" className="type-helper text-muted-foreground">
            {notice}
          </p>
        ) : null}

        <form
          key={formKey}
          onSubmit={onSearch}
          className="flex flex-col gap-2 sm:flex-row sm:items-end"
          noValidate
        >
          <div className="flex flex-1 flex-col gap-2">
            <Label htmlFor="lookup-email" className="type-label">
              Account email
            </Label>
            <Input
              id="lookup-email"
              name="email"
              type="email"
              autoComplete="off"
              required
              disabled={searching || granting}
            />
          </div>
          <Button type="submit" disabled={searching || granting}>
            {searching ? "Looking up…" : "Look up"}
          </Button>
        </form>

        {result && !result.ok ? (
          <p role="alert" className="type-helper text-destructive">
            {result.message}
          </p>
        ) : null}

        {result?.ok && result.user === null ? (
          <p className="type-helper text-muted-foreground">
            No account with that email exists. Create it in Supabase
            Authentication first.
          </p>
        ) : null}

        {user ? (
          <div className="flex flex-col gap-4 rounded-lg border p-4">
            <dl className="type-body grid gap-1 sm:grid-cols-[auto_1fr] sm:gap-x-4">
              <dt className="text-muted-foreground">Email</dt>
              <dd className="break-all">{user.email}</dd>
              <dt className="text-muted-foreground">Created</dt>
              <dd>{formatUtc(user.createdAt)}</dd>
              <dt className="text-muted-foreground">Last sign-in</dt>
              <dd>{formatUtc(user.lastSignInAt)}</dd>
            </dl>

            {blocked ? (
              <p role="alert" className="type-helper text-destructive">
                {blocked}
              </p>
            ) : (
              <form
                onSubmit={onGrant}
                className="flex flex-col gap-3"
                noValidate
              >
                <input type="hidden" name="target" value={user.userId} />
                <div className="flex flex-col gap-2">
                  <Label htmlFor="grant-role" className="type-label">
                    Role
                  </Label>
                  <NativeSelect
                    id="grant-role"
                    name="role"
                    defaultValue={ASSIGNABLE_ROLES[0]}
                    disabled={granting}
                  >
                    {ASSIGNABLE_ROLES.map((role) => (
                      <option key={role} value={role}>
                        {ROLE_LABELS[role]}
                      </option>
                    ))}
                  </NativeSelect>
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
                  />
                  <p className="type-helper text-muted-foreground">
                    Saved in the audit log. 10 to 500 characters.
                  </p>
                </div>
                {grantError ? (
                  <p role="alert" className="type-helper text-destructive">
                    {grantError}
                  </p>
                ) : null}
                <div>
                  <Button type="submit" disabled={granting}>
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
