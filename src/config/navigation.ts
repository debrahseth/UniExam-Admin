import {
  BarChart3,
  ClipboardCheck,
  GraduationCap,
  LayoutDashboard,
  LifeBuoy,
  ScrollText,
  Settings,
  ShieldCheck,
  type LucideIcon,
} from "lucide-react";

export type AdminRole =
  | "super_admin"
  | "academic_admin"
  | "question_reviewer"
  | "support_admin"
  | "analytics_viewer";

export type NavItem = {
  title: string;
  href: string;
  icon: LucideIcon;
  roles: readonly AdminRole[];
};

export type NavGroup = {
  label: string;
  items: readonly NavItem[];
};

const ALL: readonly AdminRole[] = [
  "super_admin",
  "academic_admin",
  "question_reviewer",
  "support_admin",
  "analytics_viewer",
];

export const navigation: readonly NavGroup[] = [
  {
    label: "Overview",
    items: [
      { title: "Dashboard", href: "/admin", icon: LayoutDashboard, roles: ALL },
    ],
  },
  {
    label: "Content",
    items: [
      {
        title: "Academic structure",
        href: "/admin/academic",
        icon: GraduationCap,
        roles: ["super_admin", "academic_admin"],
      },
      {
        title: "Question review",
        href: "/admin/questions",
        icon: ClipboardCheck,
        roles: ["super_admin", "academic_admin", "question_reviewer"],
      },
    ],
  },
  {
    label: "Operations",
    items: [
      {
        title: "Support",
        href: "/admin/support",
        icon: LifeBuoy,
        roles: ["super_admin", "support_admin"],
      },
      {
        title: "Analytics",
        href: "/admin/analytics",
        icon: BarChart3,
        roles: ["super_admin", "analytics_viewer"],
      },
    ],
  },
  {
    label: "Administration",
    items: [
      {
        title: "Admin access",
        href: "/admin/access",
        icon: ShieldCheck,
        roles: ["super_admin"],
      },
      {
        title: "Audit log",
        href: "/admin/audit-log",
        icon: ScrollText,
        roles: ["super_admin"],
      },
      {
        title: "Settings",
        href: "/admin/settings",
        icon: Settings,
        roles: ["super_admin"],
      },
    ],
  },
];

export const routeTitles: Record<string, string> = Object.fromEntries([
  ["/admin", "Dashboard"],
  ...navigation.flatMap((g) => g.items.map((i) => [i.href, i.title] as const)),
]);
