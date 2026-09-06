"use client";

import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { SplitText } from "gsap/SplitText";

// One registration for the whole app. Every other module imports GSAP from here.
gsap.registerPlugin(useGSAP, ScrollTrigger, SplitText);

/**
 * True when motion should be instant: the OS asks for reduced motion, or the
 * pre-paint mark never landed (no JavaScript, failsafe fired), so the page is
 * already on screen in its settled state.
 */
export function prefersReducedMotion(): boolean {
  if (typeof window === "undefined") return true;
  if (document.documentElement.dataset.motion !== "js") return true;
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** Marks the document as owned by a page controller so the failsafe leaves the mark alone. */
export function claimMotion() {
  if (typeof document !== "undefined") document.documentElement.dataset.motionClaimed = "";
}

export { gsap, ScrollTrigger, SplitText, useGSAP };
