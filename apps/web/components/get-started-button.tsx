"use client";

import { useRef } from "react";
import { Logo } from "@/components/logo";
import { Button } from "@/components/ui/button";
import { gsap, prefersReducedMotion, useGSAP } from "@/lib/gsap";
import { cn } from "@/lib/utils";

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
        "h-16 px-12 text-2xl font-bold bg-primary text-white hover:bg-primary/90 hover:text-white",
        placeholder && "invisible",
        className
      )}
      aria-hidden={placeholder || undefined}
      tabIndex={placeholder ? -1 : undefined}
      data-magnetic
    >
      <Logo ref={markRef} variant="mono" className="mr-3 size-10" />
      Get Started
    </Button>
  );
}
