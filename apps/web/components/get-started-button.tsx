"use client";

import { useRef } from "react";
import { Logo } from "@/components/logo";
import { Button } from "@/components/ui/button";
import { gsap, prefersReducedMotion, useGSAP } from "@/lib/gsap";
import { cn } from "@/lib/utils";

/** Shared look for the two hero CTAs. Fixed height; hover glows rather than moves. */
export const heroButtonClass =
  "h-16 px-9 text-3xl font-bold text-white hover:text-white bg-linear-to-br from-[oklch(0.7_0.19_55)] via-primary to-[oklch(0.5_0.18_35)] hover:brightness-110 [text-shadow:0_0_10px_rgba(0,0,0,0.35)] shadow-[0_0_0_0_rgba(255,150,70,0)] hover:shadow-[0_0_32px_6px_rgba(255,150,70,0.45)]";

interface GetStartedButtonProps {
  className?: string;
  /** Renders the same footprint without visuals, so layout holds while auth loads. */
  placeholder?: boolean;
}

/** Primary hero CTA. Intentionally inert for now; the ember mark flickers like a live flame. */
export function GetStartedButton({ className, placeholder = false }: GetStartedButtonProps) {
  const markRef = useRef<SVGSVGElement>(null);

  useGSAP(
    () => {
      const mark = markRef.current;
      if (!mark || placeholder || prefersReducedMotion()) return;

      gsap.set(mark, { transformOrigin: "50% 85%" });

      // Slow breath: the flame swells and settles like an ember catching air.
      gsap.to(mark, {
        scale: 1.08,
        duration: 1.6,
        ease: "sine.inOut",
        repeat: -1,
        yoyo: true,
      });

      // Flicker: each cycle picks a fresh lean and glow so it never reads as a loop.
      gsap.to(mark, {
        rotation: () => gsap.utils.random(-4, 4),
        skewX: () => gsap.utils.random(-3, 3),
        filter: () =>
          `drop-shadow(0 0 ${gsap.utils.random(2, 7)}px rgba(255, 190, 120, ${gsap.utils.random(0.45, 0.9)}))`,
        duration: () => gsap.utils.random(0.35, 0.8),
        ease: "sine.inOut",
        repeat: -1,
        repeatRefresh: true,
      });
    },
    { scope: markRef, dependencies: [placeholder] }
  );

  return (
    <Button
      type="button"
      size="lg"
      className={cn(
        heroButtonClass,
        placeholder && "invisible",
        className
      )}
      aria-hidden={placeholder || undefined}
      tabIndex={placeholder ? -1 : undefined}
    >
      <Logo ref={markRef} variant="mono" className="mr-1 size-10" />
      Get Started
    </Button>
  );
}
