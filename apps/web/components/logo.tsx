import { cn } from "@/lib/utils";

interface LogoProps {
  className?: string;
  /** Use the brand color by default, or inherit the text color for monochrome. */
  variant?: "color" | "mono";
}

/** AI Film Camp’s custom swept flame, adapted from Lucide Flame (ISC). */
export function Logo({ className, variant = "color" }: LogoProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={cn("h-6 w-6 shrink-0", variant === "color" && "text-primary", className)}
      role="img"
      aria-label="AI Film Camp"
    >
      <path d="M14 2C13.5 6.5 20 9 20 14C20 18.4 16.4 22 12 22C7.6 22 4 18.7 4 14.5C4 11.4 5.8 9.4 8 7.5C7.5 10 8.3 11.7 9.5 12.5C8.5 7.5 11 4.5 14 2Z" />
    </svg>
  );
}
