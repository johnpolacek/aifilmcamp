import { ArrowLeft, ArrowRight } from "lucide-react";
import type { Metadata } from "next";
import { TransitionLink } from "@/components/motion/transition";
import { IdeaPromptBuilder } from "@/components/tools/idea-prompt-builder";
import { getTool } from "@/lib/tools";

export const metadata: Metadata = {
  title: "AI Film Idea Generator - AI Film Camp",
  description:
    "Build a film idea prompt from your duration, genre, inspirations, and creative constraints. Copy it into your own LLM agent to explore original film ideas.",
};

export default function IdeaGeneratorPage() {
  const tool = getTool("idea-generator");

  return (
    <main className="container mx-auto px-4 pt-28 pb-20 lg:px-8">
      <div className="max-w-3xl">
        <div className="flex flex-wrap items-center gap-3">
          <p className="text-sm font-semibold tracking-widest text-primary uppercase">
            {tool.platform}
          </p>
          <span className="rounded-full border border-border px-3 py-1 text-xs text-muted-foreground">
            Free prompt builder
          </span>
        </div>
      </div>

      <IdeaPromptBuilder />

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
