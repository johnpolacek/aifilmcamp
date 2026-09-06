import { BRAND_MARK_PATH } from "@/lib/brand";
import { cn } from "@/lib/utils";

interface LogoProps {
  className?: string;
  /** Use the brand color by default, or inherit the text color for monochrome. */
  variant?: "color" | "mono";
}

/** The approved Ember Lens mark. Keep its circular opening and proportions intact. */
export function Logo({ className, variant = "color" }: LogoProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="currentColor"
      className={cn("h-6 w-6 shrink-0", variant === "color" && "text-primary", className)}
      role="img"
      aria-label="AI Film Camp"
    >
      <path fillRule="evenodd" d={BRAND_MARK_PATH} />
    </svg>
  );
}
