import { ArrowLeft, ArrowRight } from "lucide-react";
import type { Metadata } from "next";
import { TransitionLink } from "@/components/motion/transition";
import { getTool } from "@/lib/tools";

export const metadata: Metadata = {
  title: "AI Film Idea Generator - AI Film Camp",
  description:
    "A web tool for finding a film worth making. Start from a genre, a mood, or an image and get loglines, characters, and a shot list.",
};

const placeholderSteps = [
  {
    title: "Start from a spark",
    body: "Pick a genre, describe a mood, or drop in a single image. That’s enough to get going.",
  },
  {
    title: "Get loglines",
    body: "A handful of one-sentence pitches, each with a clear protagonist, a want, and a complication.",
  },
  {
    title: "Build it out",
    body: "Choose a logline and expand it into characters, a setting, and a shot list sized for a 30-second film.",
  },
  {
    title: "Take it into production",
    body: "Send the result to the Mac app as a starting screenplay, or copy it out and go.",
  },
];

export default function IdeaGeneratorPage() {
  const tool = getTool("idea-generator");

  return (
    <main className="mx-auto max-w-6xl px-4 pt-28 pb-20 sm:px-6 lg:px-8">
      <nav aria-label="Breadcrumb" className="text-sm text-muted-foreground">
        <TransitionLink href="/tools" className="transition-colors hover:text-foreground">
          Tools
        </TransitionLink>
        <span aria-hidden="true" className="mx-2">
          /
        </span>
        <span>{tool.name}</span>
      </nav>

      <div className="mt-8 max-w-3xl">
        <div className="flex flex-wrap items-center gap-3">
          <p className="text-sm font-semibold tracking-widest text-primary uppercase">
            {tool.platform}
          </p>
          <span className="rounded-full border border-border px-3 py-1 text-xs text-muted-foreground">
            Coming soon
          </span>
        </div>
        <h1 className="mt-4 text-4xl font-bold tracking-tight text-balance sm:text-5xl">
          {tool.name}
        </h1>
        <p className="mt-6 max-w-2xl text-lg leading-relaxed text-muted-foreground">
          {tool.description}
        </p>
      </div>

      <p className="mt-5 text-sm leading-relaxed text-muted-foreground">
        This tool is being built. Here’s how it will work.
      </p>

      <div className="mt-12 grid gap-4">
        {placeholderSteps.map((step, index) => (
          <section
            key={step.title}
            aria-label={step.title}
            className="rounded-xl border border-dashed border-border p-6 sm:p-8"
          >
            <div className="flex items-center gap-3">
              <p className="font-mono text-sm text-primary">{String(index + 1).padStart(2, "0")}</p>
              <h2 className="text-sm font-semibold tracking-widest text-primary uppercase">
                {step.title}
              </h2>
            </div>
            <p className="mt-3 max-w-2xl leading-relaxed text-muted-foreground">{step.body}</p>
          </section>
        ))}
      </div>

      <nav aria-label="Tool navigation" className="mt-16 flex flex-col gap-4 sm:flex-row">
        <TransitionLink
          href="/tools"
          className="flex flex-1 flex-col gap-1 rounded-xl border border-border bg-card p-5 transition-colors hover:border-primary/50"
        >
          <span className="flex items-center gap-2 text-xs text-muted-foreground">
            <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
            Back to
          </span>
          <span className="font-semibold">All tools</span>
        </TransitionLink>
        <TransitionLink
          href="/tools#macos-app"
          className="flex flex-1 flex-col gap-1 rounded-xl border border-border bg-card p-5 transition-colors hover:border-primary/50 sm:items-end sm:text-right"
        >
          <span className="flex items-center gap-2 text-xs text-muted-foreground">
            Available now
            <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
          </span>
          <span className="font-semibold">AI Film Camp for Mac</span>
        </TransitionLink>
      </nav>
    </main>
  );
}
