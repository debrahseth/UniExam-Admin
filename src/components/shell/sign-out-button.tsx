"use client";

import { LoaderCircleIcon } from "lucide-react";
import { useFormStatus } from "react-dom";

import { signOut } from "@/features/sign-in/actions";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

function DialogActions() {
  const { pending } = useFormStatus();

  return (
    <DialogFooter>
      <DialogClose
        render={<Button type="button" variant="outline" disabled={pending} />}
      >
        Cancel
      </DialogClose>
      <Button type="submit" disabled={pending} aria-busy={pending}>
        {pending ? (
          <LoaderCircleIcon aria-hidden="true" className="animate-spin" />
        ) : null}
        {pending ? "Signing out…" : "Sign out"}
      </Button>
    </DialogFooter>
  );
}

export function SignOutButton() {
  return (
    <Dialog>
      <DialogTrigger render={<Button variant="outline" size="sm" />}>
        Sign out
      </DialogTrigger>
      <DialogContent>
        <form action={signOut} className="grid gap-4">
          <DialogHeader>
            <DialogTitle className="pr-8">
              Sign out of UniExam Admin?
            </DialogTitle>
            <DialogDescription>
              You will need to sign in again to continue.
            </DialogDescription>
          </DialogHeader>
          <DialogActions />
        </form>
      </DialogContent>
    </Dialog>
  );
}
