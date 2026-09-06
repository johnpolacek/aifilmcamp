"use client";

import { useRef } from "react";
import { gsap, prefersReducedMotion, ScrollTrigger, useGSAP } from "@/lib/gsap";

type Fly = { x: number; y: number; vx: number; vy: number; r: number; p: number; s: number };

/**
 * A field of fireflies drawn on a canvas behind the page content. Scroll
 * velocity acts as wind. Renders nothing under reduced motion.
 */
export function Fireflies({ className }: { className?: string }) {
  const ref = useRef<HTMLCanvasElement>(null);

  useGSAP(() => {
    const canvas = ref.current;
    if (!canvas || prefersReducedMotion()) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let W = 0;
    let H = 0;
    let dpr = 1;
    const size = () => {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = canvas.width = window.innerWidth * dpr;
      H = canvas.height = window.innerHeight * dpr;
    };
    size();
    window.addEventListener("resize", size);

    const count = window.innerWidth < 768 ? 34 : 70;
    const flies: Fly[] = Array.from({ length: count }, () => ({
      x: Math.random(),
      y: 0.25 + Math.random() * 0.75,
      vx: gsap.utils.random(-0.02, 0.02),
      vy: gsap.utils.random(-0.012, 0.012),
      r: gsap.utils.random(1, 2.6),
      p: Math.random() * Math.PI * 2,
      s: gsap.utils.random(0.6, 1.6),
    }));

    let wind = 0;
    let targetWind = 0;
    ScrollTrigger.create({
      start: 0,
      end: "max",
      onUpdate: (self) => {
        targetWind = gsap.utils.clamp(-1.6, 1.6, self.getVelocity() / 2200);
      },
    });

    const draw = (time: number, deltaTime: number) => {
      const d = deltaTime / 1000;
      wind += (targetWind - wind) * 0.06;
      targetWind *= 0.9;
      ctx.clearRect(0, 0, W, H);
      for (const f of flies) {
        f.x += (f.vx + Math.sin(time * 0.3 + f.p) * 0.01) * d;
        f.y += (f.vy - wind * 0.12) * d;
        if (f.x < -0.05) f.x = 1.05;
        if (f.x > 1.05) f.x = -0.05;
        if (f.y < 0.15) f.y = 1.05;
        if (f.y > 1.05) f.y = 0.15;
        const a = 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(time * f.s + f.p));
        const x = f.x * W;
        const y = f.y * H;
        const r = f.r * dpr * 6;
        const g = ctx.createRadialGradient(x, y, 0, x, y, r);
        g.addColorStop(0, `rgba(255,200,90,${(a * 0.9).toFixed(3)})`);
        g.addColorStop(0.35, `rgba(255,170,60,${(a * 0.25).toFixed(3)})`);
        g.addColorStop(1, "rgba(255,150,40,0)");
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
      }
    };
    gsap.ticker.add(draw);

    return () => {
      gsap.ticker.remove(draw);
      window.removeEventListener("resize", size);
      ctx.clearRect(0, 0, W, H);
    };
  });

  return <canvas ref={ref} className={className} />;
}
