"use client";

import { MoreHorizontalIcon } from "lucide-react";
import { useState, useTransition, type FormEvent } from "react";

import { NativeSelect, TextArea } from "@/components/shell/form-fields";
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
import type { AdminRow, ManageIntent } from "./types";

type Pending = { intent: ManageIntent; admin: AdminRow };

const STATUS_BADGE: Record<
  AdminStatus,
  { label: string; variant: "default" | "outline" | "destructive" }
> = {
  active: { label: "Active", variant: "default" },
  suspended: { label: "Suspended", variant: "outline" },
  revoked: { label: "Revoked", variant: "destructive" },
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
        <DialogTitle>{copy.title}</DialogTitle>
        <DialogDescription>{copy.description(admin.email)}</DialogDescription>
      </DialogHeader>

      <input type="hidden" name="intent" value={intent} />
      <input type="hidden" name="target" value={admin.userId} />

      {intent === "change_role" ? (
        <div className="flex flex-col gap-2">
          <Label htmlFor="manage-role" className="type-label">
            New role
          </Label>
          <NativeSelect
            id="manage-role"
            name="role"
            defaultValue={roles[0]}
            disabled={busy}
          >
            {roles.map((role) => (
              <option key={role} value={role}>
                {ROLE_LABELS[role]}
              </option>
            ))}
          </NativeSelect>
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
        />
        <p className="type-helper text-muted-foreground">
          10 to 500 characters.
        </p>
      </div>

      {error ? (
        <p role="alert" className="type-helper text-destructive">
          {error}
        </p>
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
        >
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
    <div className="flex flex-col gap-3">
      {notice ? (
        <p role="status" className="type-helper text-muted-foreground">
          {notice}
        </p>
      ) : null}

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Email</TableHead>
            <TableHead>Role</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Added</TableHead>
            <TableHead className="w-12">
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
                <TableCell className="type-table">{admin.email}</TableCell>
                <TableCell className="type-table">
                  {ROLE_LABELS[admin.role]}
                </TableCell>
                <TableCell>
                  <Badge variant={badge.variant}>{badge.label}</Badge>
                </TableCell>
                <TableCell className="type-table">
                  {formatUtc(admin.createdAt)}
                </TableCell>
                <TableCell>
                  {admin.role === "super_admin" ? (
                    <span className="type-helper text-muted-foreground">
                      Protected
                    </span>
                  ) : intents.length > 0 ? (
                    <DropdownMenu>
                      <DropdownMenuTrigger
                        render={
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            aria-label={`Actions for ${admin.email}`}
                          />
                        }
                      >
                        <MoreHorizontalIcon />
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
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

      <Dialog
        open={pending !== null}
        onOpenChange={(open) => {
          if (!open) setPending(null);
        }}
      >
        <DialogContent>
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
