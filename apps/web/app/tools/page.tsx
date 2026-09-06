import { Show, SignInButton } from "@clerk/nextjs";
import { ArrowRight, Download } from "lucide-react";
import type { Metadata } from "next";
import { TransitionLink } from "@/components/motion/transition";
import { tools } from "@/lib/tools";

export const metadata: Metadata = {
  title: "Tools - AI Film Camp",
  description:
    "Free tools for AI filmmakers. Download the Mac app to break down a screenplay and plan your assets, or build a custom film idea prompt to use with your own LLM agent.",
};

export default function ToolsPage() {
  return (
    <main className="mx-auto max-w-6xl px-4 pt-28 pb-20 sm:px-6 lg:px-8">
      <div className="max-w-3xl">
        <p className="mb-4 text-sm font-semibold tracking-widest text-primary uppercase">
          Tools from AI Film Camp
        </p>
        <h1 className="text-4xl font-bold tracking-tight text-balance sm:text-6xl">
          Tools built for making AI films.
        </h1>
        <p className="mt-6 max-w-2xl text-lg leading-relaxed text-muted-foreground">
          Software for the work between an idea and a finished edit. Find a story, plan the
          production, and get every scene ready to generate.
        </p>
      </div>

      <section aria-labelledby="tools-title" className="mt-16">
        <h2 id="tools-title" className="sr-only">
          Available tools
        </h2>
        <div className="grid gap-4 md:grid-cols-2">
          {tools.map((tool) => {
            const Icon = tool.icon;
            const isLive = tool.status === "live";
            return (
              <article
                key={tool.id}
                id={tool.id}
                className="flex flex-col rounded-2xl border border-border bg-card p-6 sm:p-8"
              >
                <div className="flex flex-wrap items-center justify-between gap-2 text-xs">
                  <span className="font-medium text-primary">{tool.platform}</span>
                  <span
                    className={
                      isLive
                        ? "rounded-full border border-primary/40 bg-primary/10 px-3 py-1 font-medium text-primary"
                        : "rounded-full border border-border px-3 py-1 text-muted-foreground"
                    }
                  >
                    {isLive ? "Available now" : "Coming soon"}
                  </span>
                </div>
                <div className="mt-6 flex items-center gap-4">
                  <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                    <Icon className="h-6 w-6" aria-hidden="true" />
                  </div>
                  <div>
                    <h3 className="text-2xl font-semibold">{tool.name}</h3>
                    <p className="mt-1 text-sm text-muted-foreground">{tool.tagline}</p>
                  </div>
                </div>
                <p className="mt-4 leading-relaxed text-muted-foreground">{tool.description}</p>
                {tool.download ? (
                  <div className="mt-8 flex flex-col gap-3">
                    <Show when="signed-in">
                      <a
                        href={tool.download.href}
                        className="inline-flex w-fit items-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary/90"
                      >
                        <Download className="h-4 w-4" aria-hidden="true" />
                        {tool.download.label}
                      </a>
                    </Show>
                    <Show when="signed-out">
                      <SignInButton mode="modal" forceRedirectUrl={tool.download.href}>
                        <button
                          type="button"
                          className="inline-flex w-fit items-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary/90"
                        >
                          <Download className="h-4 w-4" aria-hidden="true" />
                          Sign in to download
                        </button>
                      </SignInButton>
                    </Show>
                    <p className="text-xs text-muted-foreground">{tool.download.requirements}</p>
                  </div>
                ) : null}
                {tool.href ? (
                  <TransitionLink
                    href={tool.href}
                    className="mt-8 inline-flex w-fit items-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground transition-colors hover:bg-primary/90"
                  >
                    Open {tool.name.replace(/^AI Film /, "")}
                    <ArrowRight className="h-4 w-4" aria-hidden="true" />
                  </TransitionLink>
                ) : null}
              </article>
            );
          })}
        </div>
      </section>
    </main>
  );
}
