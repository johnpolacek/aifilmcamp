import { TransitionLink } from "@/components/motion/transition";

export function ComeUpWithAnIdea() {
  return (
    <div className="mt-12 max-w-3xl space-y-10 leading-relaxed text-muted-foreground">
      <section aria-labelledby="generate-heading" className="space-y-4">
        <h2 id="generate-heading" className="text-2xl font-semibold text-foreground">
          Generate five ideas
        </h2>
        <p>
          Open the{" "}
          <TransitionLink
            href="/tools/idea-generator"
            className="font-medium text-primary underline underline-offset-4 hover:text-foreground"
          >
            AI Film Idea Generator
          </TransitionLink>
          . Set the duration to 30 seconds and request five ideas.
        </p>
        <ul className="list-disc space-y-2 pl-5">
          <li>Pick a genre. Combine two for an unexpected angle.</li>
          <li>Add a specific inspiration: a strange habit, a vivid memory, an unusual place.</li>
          <li>Set constraints: one character, one location, no dialogue, a visual payoff.</li>
        </ul>
        <p>Copy the prompt into your LLM chat to generate the ideas.</p>
      </section>

      <section aria-labelledby="refine-heading" className="space-y-4">
        <h2 id="refine-heading" className="text-2xl font-semibold text-foreground">
          Keep the spark. Push the idea.
        </h2>
        <p>
          Pick the idea with the strongest image. Tell the LLM what to keep and what feels
          predictable. Be specific:
        </p>
        <blockquote className="rounded-xl border border-border bg-card p-6 text-foreground">
          Keep the shadow moving on its own. Replace the sinister twist with an act of kindness.
          Give me three endings shown through one simple action, without dialogue.
        </blockquote>
        <p>
          Combine the best details. Cut backstory, extra characters, and location changes. Ask for
          simpler alternatives to difficult visuals.
        </p>
      </section>

      <section
        aria-labelledby="assignment-heading"
        className="space-y-4 rounded-xl border border-primary/30 bg-card p-6 sm:p-8"
      >
        <h2 id="assignment-heading" className="text-2xl font-semibold text-foreground">
          Leave with one premise
        </h2>
        <p>
          Write your idea in one sentence. Note the opening image, what changes, and the final
          image. If those need more than 30 seconds or an explanation, simplify. Bring them to Step
          2.
        </p>
      </section>
    </div>
  );
}
