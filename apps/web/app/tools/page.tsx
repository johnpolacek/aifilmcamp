import type { Metadata } from "next";
import { tools } from "@/lib/tools";

export const metadata: Metadata = {
  title: "Tools - AI Film Camp",
  description:
    "Free tools for AI filmmakers. Break down a screenplay, plan your assets, and assemble your generated shots into a finished film.",
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
          Software for the work between a finished script and a finished edit. Plan the production,
          get every scene ready to generate, and put the results together.
        </p>
      </div>

      <p className="mt-5 text-sm leading-relaxed text-muted-foreground">
        We’re building these now. Here’s what’s planned; downloads aren’t available yet.
      </p>

      <section aria-labelledby="tools-title" className="mt-16">
        <h2 id="tools-title" className="sr-only">
          Available tools
        </h2>
        <div className="grid gap-4 md:grid-cols-2">
          {tools.map((tool) => {
            const Icon = tool.icon;
            return (
              <article
                key={tool.id}
                className="flex flex-col rounded-2xl border border-border bg-card p-6 sm:p-8"
              >
                <div className="flex flex-wrap items-center justify-between gap-2 text-xs">
                  <span className="font-medium text-primary">{tool.platform}</span>
                  <span className="rounded-full border border-border px-3 py-1 text-muted-foreground">
                    Coming soon
                  </span>
                </div>
                <div className="mt-6 flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 text-primary">
                  <Icon className="h-6 w-6" aria-hidden="true" />
                </div>
                <h3 className="mt-5 text-2xl font-semibold">{tool.name}</h3>
                <p className="mt-1 text-sm text-muted-foreground">{tool.tagline}</p>
                <p className="mt-4 leading-relaxed text-muted-foreground">{tool.description}</p>
              </article>
            );
          })}
        </div>
      </section>
    </main>
  );
}
