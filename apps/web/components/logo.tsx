import { cn } from "@/lib/utils";

interface LogoProps {
  className?: string;
  /** Right half color. Defaults to the current text color so it reads on dark and light. */
  variant?: "color" | "mono";
}

/** AI Film Camp mark: a lens disc split by a candle flame of negative space. */
export function Logo({ className, variant = "color" }: LogoProps) {
  const left = variant === "color" ? "#F59E0B" : "currentColor";
  return (
    <svg
      viewBox="0 0 100 100"
      className={cn("h-6 w-6 shrink-0", className)}
      role="img"
      aria-label="AI Film Camp"
    >
      <path
        fill={left}
        d="M50 8 A42 42 0 0 0 44 91.57 C40 83 41.5 73 45.5 65 C40.5 53 42 26 50 8 Z"
      />
      <path
        fill="currentColor"
        d="M50 8 A42 42 0 0 1 56 91.57 C62 84 63 66 58 52 C54 40 51 24 50 8 Z"
      />
    </svg>
  );
}
