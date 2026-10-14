import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export function SkeletonLine({ className }: { className?: string }) {
  return (
    <div className="flex h-5 items-center">
      <Skeleton className={`h-3.5 ${className ?? "w-full"}`} />
    </div>
  );
}

export function PageHeaderSkeleton() {
  return (
    <div className="space-y-1">
      <div className="flex h-8 items-center">
        <Skeleton className="h-6 w-44" />
      </div>
      <SkeletonLine className="w-full max-w-prose" />
      <SkeletonLine className="w-2/3 max-w-sm" />
    </div>
  );
}

export function CardTitleSkeleton({ width }: { width: string }) {
  return (
    <div className="flex h-5.5 items-center gap-2">
      <Skeleton className="size-4" />
      <Skeleton className={`h-4 ${width}`} />
    </div>
  );
}

export type SkeletonColumn = {
  head: string | null;
  cell: string;
};

export function TableSkeleton({
  columns,
  rows = 5,
  cellClassName = "px-3 py-2.5",
}: {
  columns: SkeletonColumn[];
  rows?: number;
  cellClassName?: string;
}) {
  return (
    <div
      className="overflow-hidden rounded-lg border contain-[inline-size]"
      aria-hidden="true"
    >
      <Table>
        <TableHeader className="bg-muted/40">
          <TableRow className="hover:bg-transparent">
            {columns.map((column, index) => (
              <TableHead key={index} className="h-9 px-3">
                {column.head ? (
                  <Skeleton className={`h-3 ${column.head}`} />
                ) : null}
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {Array.from({ length: rows }, (_, row) => (
            <TableRow key={row} className="hover:bg-transparent">
              {columns.map((column, index) => (
                <TableCell key={index} className={cellClassName}>
                  <Skeleton className={column.cell} />
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
