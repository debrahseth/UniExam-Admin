"use client";

import { LoaderCircleIcon, LockIcon, MoreHorizontalIcon } from "lucide-react";
import { useState, useTransition, type FormEvent } from "react";

import { TextArea } from "@/components/shell/form-fields";
import { RoleSelect } from "./role-select";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Label } from "@/components/ui/label";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  ASSIGNABLE_ROLES,
  ROLE_LABELS,
  type AdminStatus,
} from "@/lib/admin-roles";
import { formatUtc } from "@/lib/format";

import { manageAdmin } from "./actions";
import { InlineMessage } from "./inline-message";
import type { AdminRow, ManageIntent } from "./types";

type Pending = { intent: ManageIntent; admin: AdminRow };

const STATUS_BADGE: Record<AdminStatus, { label: string; className: string }> =
  {
    active: {
      label: "Active",
      className: "bg-success-muted text-success-muted-foreground",
    },
    suspended: {
      label: "Suspended",
      className: "bg-warning-muted text-warning-muted-foreground",
    },
    revoked: {
      label: "Revoked",
      className: "bg-destructive-muted text-destructive-muted-foreground",
    },
  };

const COPY: Record<
  ManageIntent,
  {
    menu: string;
    title: string;
    description: (email: string) => string;
    submit: string;
    destructive: boolean;
  }
> = {
  change_role: {
    menu: "Change role",
    title: "Change role",
    description: (email) =>
      `Choose a new role for ${email}. It applies immediately. The reason is saved in the audit log.`,
    submit: "Change role",
    destructive: false,
  },
  suspend: {
    menu: "Suspend",
    title: "Suspend access",
    description: (email) =>
      `${email} will lose access to UniExam Admin immediately, until you reactivate it. The reason is saved in the audit log.`,
    submit: "Suspend",
    destructive: true,
  },
  reactivate: {
    menu: "Reactivate",
    title: "Reactivate access",
    description: (email) =>
      `${email} will regain access with their current role. The reason is saved in the audit log.`,
    submit: "Reactivate",
    destructive: false,
  },
  revoke: {
    menu: "Revoke access",
    title: "Revoke access",
    description: (email) =>
      `${email} will lose administrator access immediately. You can grant access again later. The reason is saved in the audit log.`,
    submit: "Revoke access",
    destructive: true,
  },
};

function intentsFor(status: AdminStatus): ManageIntent[] {
  if (status === "active") return ["change_role", "suspend", "revoke"];
  if (status === "suspended") return ["change_role", "reactivate", "revoke"];
  return [];
}

function ManageForm({
  pending,
  onDone,
}: {
  pending: Pending;
  onDone: (message: string) => void;
}) {
  const { intent, admin } = pending;
  const copy = COPY[intent];
  const [error, setError] = useState<string | null>(null);
  const [busy, startTransition] = useTransition();
  const roles = ASSIGNABLE_ROLES.filter((role) => role !== admin.role);

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    setError(null);
    startTransition(async () => {
      const result = await manageAdmin(formData);
      if (result.ok) onDone(result.message);
      else setError(result.message);
    });
  }

  return (
    <form onSubmit={onSubmit} className="grid gap-4" noValidate>
      <DialogHeader>
        <DialogTitle className="pr-8">{copy.title}</DialogTitle>
        <DialogDescription className="leading-relaxed">
          {copy.description(admin.email)}
        </DialogDescription>
      </DialogHeader>

      <input type="hidden" name="intent" value={intent} />
      <input type="hidden" name="target" value={admin.userId} />

      {intent === "change_role" ? (
        <div className="flex flex-col gap-2">
          <Label htmlFor="manage-role" className="type-label">
            New role
          </Label>
          <RoleSelect
            id="manage-role"
            name="role"
            roles={roles}
            defaultValue={roles[0]}
            disabled={busy}
          />
        </div>
      ) : null}

      <div className="flex flex-col gap-2">
        <Label htmlFor="manage-reason" className="type-label">
          Reason
        </Label>
        <TextArea
          id="manage-reason"
          name="reason"
          minLength={10}
          maxLength={500}
          required
          disabled={busy}
          aria-describedby="manage-reason-help"
        />
        <p
          id="manage-reason-help"
          className="type-helper text-muted-foreground"
        >
          10 to 500 characters.
        </p>
      </div>

      {error ? (
        <InlineMessage tone="error" role="alert">
          {error}
        </InlineMessage>
      ) : null}

      <DialogFooter>
        <DialogClose
          render={<Button type="button" variant="outline" disabled={busy} />}
        >
          Cancel
        </DialogClose>
        <Button
          type="submit"
          variant={copy.destructive ? "destructive" : "default"}
          disabled={busy}
          aria-busy={busy}
        >
          {busy ? (
            <LoaderCircleIcon aria-hidden="true" className="animate-spin" />
          ) : null}
          {busy ? "Working…" : copy.submit}
        </Button>
      </DialogFooter>
    </form>
  );
}

export function AdminsTable({ admins }: { admins: AdminRow[] }) {
  const [pending, setPending] = useState<Pending | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  return (
    <div className="flex flex-col gap-4">
      {notice ? (
        <InlineMessage tone="success" role="status">
          {notice}
        </InlineMessage>
      ) : null}

      <div className="overflow-hidden rounded-lg border">
        <Table>
          <TableHeader className="bg-muted/40">
            <TableRow className="hover:bg-transparent">
              <TableHead className="type-meta h-9 px-3 text-muted-foreground">
                Email
              </TableHead>
              <TableHead className="type-meta h-9 px-3 text-muted-foreground">
                Role
              </TableHead>
              <TableHead className="type-meta h-9 px-3 text-muted-foreground">
                Status
              </TableHead>
              <TableHead className="type-meta h-9 px-3 text-muted-foreground">
                Added
              </TableHead>
              <TableHead className="h-9 w-14 px-3 text-right">
                <span className="sr-only">Actions</span>
              </TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {admins.map((admin) => {
              const badge = STATUS_BADGE[admin.status];
              const intents =
                admin.role === "super_admin" ? [] : intentsFor(admin.status);

              return (
                <TableRow key={admin.userId}>
                  <TableCell className="type-table px-3 py-2.5 font-medium">
                    {admin.email}
                  </TableCell>
                  <TableCell className="type-table px-3 py-2.5">
                    {ROLE_LABELS[admin.role]}
                  </TableCell>
                  <TableCell className="px-3 py-2.5">
                    <Badge
                      variant="secondary"
                      className={`gap-1.5 ${badge.className}`}
                    >
                      <span
                        aria-hidden="true"
                        className="size-1.5 rounded-full bg-current"
                      />
                      {badge.label}
                    </Badge>
                  </TableCell>
                  <TableCell className="type-table px-3 py-2.5 text-muted-foreground tabular-nums">
                    {formatUtc(admin.createdAt)}
                  </TableCell>
                  <TableCell className="px-3 py-2.5 text-right">
                    {admin.role === "super_admin" ? (
                      <span className="type-helper inline-flex items-center gap-1 text-muted-foreground">
                        <LockIcon aria-hidden="true" className="size-3" />
                        Protected
                      </span>
                    ) : intents.length > 0 ? (
                      <DropdownMenu>
                        <DropdownMenuTrigger
                          render={
                            <Button
                              variant="ghost"
                              size="icon"
                              aria-label={`Actions for ${admin.email}`}
                            />
                          }
                        >
                          <MoreHorizontalIcon />
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end" className="min-w-40">
                          {intents.map((intent) => (
                            <DropdownMenuItem
                              key={intent}
                              variant={
                                intent === "suspend" || intent === "revoke"
                                  ? "destructive"
                                  : "default"
                              }
                              onClick={() => {
                                setNotice(null);
                                setPending({ intent, admin });
                              }}
                            >
                              {COPY[intent].menu}
                            </DropdownMenuItem>
                          ))}
                        </DropdownMenuContent>
                      </DropdownMenu>
                    ) : (
                      <span className="type-helper text-muted-foreground">
                        Grant again above
                      </span>
                    )}
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>

      <Dialog
        open={pending !== null}
        onOpenChange={(open) => {
          if (!open) setPending(null);
        }}
      >
        <DialogContent className="sm:max-w-md">
          {pending ? (
            <ManageForm
              key={`${pending.admin.userId}:${pending.intent}`}
              pending={pending}
              onDone={(message) => {
                setNotice(message);
                setPending(null);
              }}
            />
          ) : null}
        </DialogContent>
      </Dialog>
    </div>
  );
}
