import { cn } from "@/lib/utils";

interface LogoProps {
  className?: string;
  /** Use the brand color by default, or inherit the text color for monochrome. */
  variant?: "color" | "mono";
}

/** AI Film Camp’s swept flame breaking through a lens ring; adapted from Lucide Flame (ISC). */
export function Logo({ className, variant = "color" }: LogoProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="0.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={cn("h-6 w-6 shrink-0", variant === "color" && "text-primary", className)}
      role="img"
      aria-label="AI Film Camp"
    >
      <path d="M16 4.404A9.3 9.3 0 1 1 10 3.717" />
      <path d="M13.8 1.5C13.35 5.775 19.2 8.15 19.2 12.9C19.2 17.08 15.96 20.5 12 20.5C8.04 20.5 4.8 17.36 4.8 13.37C4.8 10.43 6.42 8.53 8.4 6.725C7.95 9.1 8.67 10.71 9.75 11.47C8.85 6.725 11.1 3.875 13.8 1.5Z" />
    </svg>
  );
}
