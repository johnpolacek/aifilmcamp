"use client";

import Image from "next/image";
import { useRef } from "react";
import { CallToAction } from "@/components/call-to-action";
import { Courses } from "@/components/courses";
import { Hero } from "@/components/hero";
import { Fireflies } from "@/components/motion/fireflies";
import { useTransition } from "@/components/motion/transition";
import {
  claimMotion,
  gsap,
  prefersReducedMotion,
  ScrollTrigger,
  SplitText,
  useGSAP,
} from "@/lib/gsap";

type Arrival = "load" | "requested" | "history";

// Development double-mounts the same root; remember what it was told the first time.
let lastRoot: HTMLElement | null = null;
let lastArrival: Arrival = "load";
let mounted = false;

/**
 * The home page and its motion controller.
 *
 * Phases: initial → intro → settled → outro → end. The veil covers the route
 * before first paint (see MotionMark), lifts during the intro, and returns for
 * the outro. Scroll is the camera: the hero and courses pin while their scene
 * plays, the closing title rises out of the fog.
 */
export function HomeView() {
  const rootRef = useRef<HTMLElement>(null);
  const { registerOutro, consumeRequested } = useTransition();

  useGSAP(
    (_context, contextSafe) => {
      const root = rootRef.current;
      if (!root || !contextSafe) return;
      const q = gsap.utils.selector(root);
      const one = <T extends Element = HTMLElement>(sel: string) => q<T>(sel)[0];
      const setPhase = (phase: string) => {
        root.dataset.phase = phase;
      };

      claimMotion();
      if (prefersReducedMotion()) {
        setPhase("settled");
        return registerOutro((finish) => finish());
      }

      let arrival: Arrival = consumeRequested() ? "requested" : mounted ? "history" : "load";
      if (lastRoot === root) arrival = lastArrival;
      lastRoot = root;
      lastArrival = arrival;
      mounted = true;

      const veil = one("[data-veil]");
      const fogA = one("[data-fog='a']");
      const fogB = one("[data-fog='b']");
      const darken = one("[data-darken]");
      const image = one<HTMLImageElement>("[data-backdrop] img");
      const hero = one("[data-hero]");
      const headline = one("[data-headline]");
      const actions = one("[data-hero-actions]");
      const courses = one("[data-courses]");
      const cta = one("[data-cta]");
      const dot = one("[data-rail-dot]");

      // ---- order matters. A scroll tween records the values it finds when
      // it first initializes and restores them on every ScrollTrigger.refresh().
      // Scroll-scene targets are hidden first (that is their resting state),
      // then their scenes are created. The hero scene waits until settle.
      const split = SplitText.create(headline, { type: "words", wordsClass: "inline-block" });
      const words = split.words;
      const sceneTargets = q(
        "[data-courses-title], [data-courses-lede], [data-card], [data-cta-title], [data-cta-lede], [data-cta-button]"
      );
      gsap.set(sceneTargets, { autoAlpha: 0 });

      const later = { immediateRender: false, ease: "none" } as const;

      // Scene 2: the courses hold while the cards arrive from depth.
      gsap
        .timeline({
          scrollTrigger: {
            trigger: courses,
            start: "top top",
            end: "+=120%",
            pin: true,
            scrub: 0.8,
            anticipatePin: 1,
          },
        })
        .fromTo(
          q("[data-courses-title]"),
          { autoAlpha: 0, y: 50 },
          { autoAlpha: 1, y: 0, duration: 0.22, ease: "none" },
          0
        )
        .fromTo(
          q("[data-courses-lede]"),
          { autoAlpha: 0, y: 34 },
          { autoAlpha: 1, y: 0, duration: 0.22, ease: "none" },
          0.08
        )
        .fromTo(
          q("[data-card]"),
          { autoAlpha: 0, scale: 0.5, y: 180 },
          { autoAlpha: 1, scale: 1, y: 0, duration: 0.5, stagger: 0.12, ease: "power1.out" },
          0.18
        )
        .to({}, { duration: 0.12 });

      // Scene 3: the closing title rises out of the fog. No pin.
      gsap
        .timeline({
          scrollTrigger: { trigger: cta, start: "top 85%", end: "center 45%", scrub: 0.6 },
        })
        .fromTo(
          q("[data-cta-title]"),
          { scale: 0.78, autoAlpha: 0, y: 50 },
          { scale: 1, autoAlpha: 1, y: 0, ease: "none" },
          0
        )
        .fromTo(
          q("[data-cta-lede]"),
          { autoAlpha: 0, y: 30 },
          { autoAlpha: 1, y: 0, ease: "none" },
          0.15
        )
        .fromTo(
          q("[data-cta-button]"),
          { autoAlpha: 0, y: 24 },
          { autoAlpha: 1, y: 0, ease: "none" },
          0.3
        );

      gsap.to(dot, { y: 153, ease: "none", scrollTrigger: { start: 0, end: "max", scrub: true } });
      gsap.to(fogB, {
        xPercent: 6,
        yPercent: -3,
        duration: 26,
        ease: "sine.inOut",
        yoyo: true,
        repeat: -1,
      });

      // ---- initial state, written before anything is revealed
      gsap.set(veil, { autoAlpha: 1 });
      gsap.set(fogA, { autoAlpha: 1 });
      gsap.set(fogB, { autoAlpha: 0.6 });
      gsap.set(darken, { autoAlpha: 0 });
      gsap.set(words, { yPercent: 60, autoAlpha: 0 });
      gsap.set(actions, { autoAlpha: 0, y: 24 });
      setPhase("intro");

      // ---- intro
      // Scene 1: the camera dollies toward the screen, the words leave the frame.
      // Created at settle: a scroll tween records the values it finds when it
      // first initializes and restores them on every ScrollTrigger.refresh(),
      // so the hero must hold its settled state when this is built.
      const createHeroScene = contextSafe(() => {
        gsap
          .timeline({
            scrollTrigger: {
              trigger: hero,
              start: "top top",
              end: "+=110%",
              pin: true,
              scrub: 0.8,
              anticipatePin: 1,
              // Built after the scenes below it; refresh in page order regardless.
              refreshPriority: 1,
            },
          })
          .fromTo(
            image,
            { scale: 1, yPercent: 0 },
            { scale: 1.32, yPercent: -4, duration: 1, ...later },
            0.01
          )
          .fromTo(fogA, { autoAlpha: 0.55 }, { autoAlpha: 0.95, duration: 0.4, ...later }, 0.01)
          .to(fogA, { autoAlpha: 0.1, duration: 0.6, ease: "none" }, 0.4)
          .fromTo(
            words[0],
            { x: 0, autoAlpha: 1 },
            { x: -220, autoAlpha: 0, duration: 0.5, ...later, ease: "power1.in" },
            0.1
          )
          .fromTo(
            words[2],
            { x: 0, autoAlpha: 1 },
            { x: 220, autoAlpha: 0, duration: 0.5, ...later, ease: "power1.in" },
            0.1
          )
          .fromTo(
            words[1],
            { y: 0, scale: 1, autoAlpha: 1 },
            { y: -140, scale: 1.35, autoAlpha: 0, duration: 0.5, ...later, ease: "power1.in" },
            0.3
          )
          .fromTo(
            actions,
            { y: 0, autoAlpha: 1 },
            { y: 90, autoAlpha: 0, duration: 0.4, ...later, ease: "power1.in" },
            0.15
          )
          .fromTo(darken, { autoAlpha: 0 }, { autoAlpha: 0.5, duration: 0.5, ...later }, 0.5);
      });

      const intro = gsap.timeline({
        onComplete: () => {
          setPhase("settled");
          gsap.set([actions, ...words], { clearProps: "transform,opacity,visibility" });
          createHeroScene();
          ScrollTrigger.refresh();
        },
      });
      intro
        .to(veil, { autoAlpha: 0, duration: 1.6, ease: "power2.inOut" }, 0)
        .to(fogA, { autoAlpha: 0.55, duration: 2.2, ease: "power2.out" }, 0.2)
        .to(
          words,
          { yPercent: 0, autoAlpha: 1, duration: 1, ease: "power3.out", stagger: 0.1 },
          0.6
        )
        .to(actions, { autoAlpha: 1, y: 0, duration: 0.8, ease: "power3.out" }, 1.2);
      // Returning by history, or arriving already scrolled: no travel.
      if (arrival === "history" || window.scrollY > 80) intro.timeScale(3);

      // ---- interaction. The hero button is magnetic; cards tilt toward the
      // pointer. Focus gets its own, non-pointer, cue.
      const magnets = new Map<Element, { x: (v: number) => void; y: (v: number) => void }>();
      const magnetFor = contextSafe((label: Element) => {
        let m = magnets.get(label);
        if (!m) {
          m = {
            x: gsap.quickTo(label, "x", { duration: 0.4, ease: "power3" }),
            y: gsap.quickTo(label, "y", { duration: 0.4, ease: "power3" }),
          };
          magnets.set(label, m);
        }
        return m;
      });
      const releaseMagnets = (except?: Element | null) => {
        for (const [label, m] of magnets) {
          if (label === except) continue;
          m.x(0);
          m.y(0);
        }
      };
      const onActionsMove = (e: PointerEvent) => {
        const button = (e.target as Element).closest("[data-magnetic]");
        const label = button ? (button.querySelector("[data-mag]") ?? button) : null;
        releaseMagnets(label);
        if (!button || !label) return;
        const r = button.getBoundingClientRect();
        const m = magnetFor(label);
        m.x((e.clientX - r.left - r.width / 2) * 0.28);
        m.y((e.clientY - r.top - r.height / 2) * 0.35);
      };
      const onActionsLeave = () => releaseMagnets();
      actions.addEventListener("pointermove", onActionsMove);
      actions.addEventListener("pointerleave", onActionsLeave);

      const tilts = q<HTMLElement>("[data-card]").map((card) => {
        const rx = gsap.quickTo(card, "rotationX", { duration: 0.5, ease: "power3" });
        const ry = gsap.quickTo(card, "rotationY", { duration: 0.5, ease: "power3" });
        const move = (e: PointerEvent) => {
          const r = card.getBoundingClientRect();
          ry(((e.clientX - r.left) / r.width - 0.5) * 14);
          rx(-((e.clientY - r.top) / r.height - 0.5) * 12);
        };
        const leave = () => {
          rx(0);
          ry(0);
        };
        card.addEventListener("pointermove", move);
        card.addEventListener("pointerleave", leave);
        return () => {
          card.removeEventListener("pointermove", move);
          card.removeEventListener("pointerleave", leave);
        };
      });

      // ---- outro: content blurs and sinks, the veil returns, then the router moves.
      const unregister = registerOutro(
        contextSafe((finish) => {
          intro.kill();
          setPhase("outro");
          gsap
            .timeline({
              defaults: { overwrite: "auto" },
              onComplete: () => {
                setPhase("end");
                finish();
              },
            })
            .to(
              q("[data-outro]"),
              { autoAlpha: 0, filter: "blur(8px)", y: 20, duration: 0.5, ease: "power2.in" },
              0
            )
            .to(veil, { autoAlpha: 1, duration: 0.6, ease: "power2.in" }, 0.1);
        })
      );

      return () => {
        unregister();
        actions.removeEventListener("pointermove", onActionsMove);
        actions.removeEventListener("pointerleave", onActionsLeave);
        for (const off of tilts) off();
      };
    },
    { scope: rootRef }
  );

  return (
    <main ref={rootRef} data-page="home" data-phase="initial" className="min-h-screen relative">
      {/* Background image: full bleed so the dolly has room */}
      <div data-backdrop className="fixed inset-0 -z-10 overflow-hidden">
        <div className="relative w-full h-full">
          <Image
            src="/aifilmcamp.png"
            alt=""
            fill
            className="object-cover origin-[55%_40%]"
            priority
          />
          <div
            className="absolute inset-0"
            style={{
              background:
                "linear-gradient(to bottom, black 0%, rgba(0,0,0,0.6) 18%, transparent 48%)",
            }}
          />
        </div>
      </div>
      <div className="fixed inset-0 bg-background/50 -z-10" />

      {/* Fog, darkening, and fireflies sit between the image and the content */}
      <div
        data-fog="a"
        aria-hidden="true"
        className="fixed -inset-[25%] -z-[9] pointer-events-none"
        style={{
          background:
            "radial-gradient(ellipse at 40% 70%, rgba(150,185,220,0.22), transparent 55%), radial-gradient(ellipse at 75% 55%, rgba(110,150,190,0.18), transparent 50%)",
        }}
      />
      <div
        data-fog="b"
        aria-hidden="true"
        className="fixed -inset-[25%] -z-[9] pointer-events-none"
        style={{
          background:
            "radial-gradient(ellipse at 60% 90%, rgba(140,170,200,0.14), transparent 50%)",
        }}
      />
      <div
        data-darken
        aria-hidden="true"
        className="fixed inset-0 -z-[9] bg-black opacity-0 pointer-events-none"
      />
      <Fireflies className="fixed inset-0 z-[5] w-full h-full pointer-events-none" />

      {/* Content */}
      <div className="relative z-10">
        <Hero />
        <Courses />
        <CallToAction />
      </div>

      {/* Scroll progress rail */}
      <div
        aria-hidden="true"
        className="hidden md:block fixed right-6 top-1/2 -mt-20 h-40 w-px bg-white/20 z-40"
      >
        <i
          data-rail-dot
          className="absolute -left-[3px] top-0 h-[7px] w-[7px] rounded-full bg-[#FBBF24] shadow-[0_0_10px_#FBBF24]"
        />
      </div>

      {/* Route veil: covers the page before first paint (under the motion mark), lifts in the intro, returns in the outro */}
      <div
        data-veil
        aria-hidden="true"
        className="motion-veil fixed inset-0 z-40 bg-[#06090f] pointer-events-none"
      />
    </main>
  );
}
