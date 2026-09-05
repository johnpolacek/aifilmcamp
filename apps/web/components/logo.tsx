import { Flame } from "lucide-react";
import { cn } from "@/lib/utils";

interface LogoProps {
  className?: string;
  /** Use the brand color by default, or inherit the text color for monochrome. */
  variant?: "color" | "mono";
}

/** The clean outline flame used across AI Film Camp. */
export function Logo({ className, variant = "color" }: LogoProps) {
  return (
    <Flame
      className={cn("h-6 w-6 shrink-0", variant === "color" && "text-primary", className)}
      role="img"
      aria-label="AI Film Camp"
    />
  );
}
