import { TransitionLink } from "@/components/motion/transition";

export function ComeUpWithAnIdea() {
  return (
    <div className="mt-12 max-w-3xl space-y-10 leading-relaxed text-muted-foreground">
      <section aria-labelledby="brainstorm-heading" className="space-y-4">
        <h2 id="brainstorm-heading" className="text-2xl font-semibold text-foreground">
          Give your brainstorming partner something to work with
        </h2>
        <p>
          A 30-second film has room for a small discovery, a surprising reversal, or a feeling that
          stays with you. Start with one character, one location, and one thing that changes. You
          can build a whole film around a single memorable image.
        </p>
        <p>
          A large language model (LLM) can help you explore possibilities and develop a rough idea.
          Your taste gives that conversation direction. Bring it a detail from your own life: a
          strange habit, a place you know well, an object you keep, or something you noticed on the
          way home. Specific details give the ideas somewhere interesting to go.
        </p>
        <p>
          Try combining that detail with an unexpected rule. A laundromat where clothes remember
          their owners. A bus stop where shadows arrive early. Pick a combination that makes you
          curious about what happens next.
        </p>
      </section>

      <section aria-labelledby="generate-heading" className="space-y-4">
        <h2 id="generate-heading" className="text-2xl font-semibold text-foreground">
          Explore several directions
        </h2>
        <p>
          Open our{" "}
          <TransitionLink
            href="/tools/idea-generator"
            className="font-medium text-primary underline underline-offset-4 hover:text-foreground"
          >
            AI Film Idea Generator
          </TransitionLink>
          . Set the duration to 30 seconds, choose a genre or a mix of genres, and add your personal
          detail under inspirations. Under other instructions, try “one character, one location, no
          dialogue, and an ending we can understand visually.” Ask for five ideas, then copy the
          prompt into your preferred LLM chat. The tool builds the prompt; your LLM generates the
          ideas.
        </p>
        <p>You can also start the conversation with this prompt:</p>
        <blockquote className="rounded-xl border border-border bg-card p-6 text-foreground">
          Help me brainstorm five distinct ideas for a 30-second film. My starting point is a lone
          commuter at a bus stop, and I like the idea of a shadow arriving before its owner. Keep it
          to one visible character, one location, and no dialogue. For each idea, give me the
          opening image, what changes, the final image, and the feeling it leaves behind. Vary the
          story and ending, not just the scenery. Avoid dream endings and familiar twists.
        </blockquote>
      </section>

      <section aria-labelledby="refine-heading" className="space-y-4">
        <h2 id="refine-heading" className="text-2xl font-semibold text-foreground">
          Push past the first answer
        </h2>
        <p>
          Read the suggestions as starting points. Which image can you already picture? Which ending
          feels too familiar? Tell the LLM exactly what you want to keep and what needs another
          pass. A useful follow-up might be:
        </p>
        <blockquote className="rounded-xl border border-border bg-card p-6 text-foreground">
          I like the shadow having a life of its own, but the sinister ending feels predictable.
          Give me three versions where the shadow does something unexpectedly kind. Make the
          kindness visible through one simple action. Keep the story understandable in 30 seconds
          without dialogue or written explanation.
        </blockquote>
        <p>
          Keep steering. Ask “What feels generic here?” or “How could the last image change the
          meaning of the first?” Borrow the strongest detail from one suggestion and combine it with
          an ending you prefer. An LLM cannot guarantee originality; the specific choices you make
          help the premise feel like yours.
        </p>
      </section>

      <section aria-labelledby="example-heading" className="space-y-4">
        <h2 id="example-heading" className="text-2xl font-semibold text-foreground">
          Make the idea small enough to finish
        </h2>
        <p>
          For example: “At a deserted bus stop, a lonely commuter watches their shadow wave goodbye
          and walk away, then return carrying a shadow umbrella that shelters them from the rain.”
        </p>
        <p>
          The opening establishes loneliness, the departing shadow creates a question, and its
          return answers that question with kindness. That gives you a beginning, a change, and a
          payoff. You can picture it in a few shots without explaining the world’s rules.
        </p>
        <p>
          Check the production challenge, too. An independently moving shadow may take several
          generation attempts or compositing. Ask your LLM to flag difficult visuals and suggest
          simpler ways to show the same idea. If your premise needs a crowd, several locations, or a
          paragraph of backstory, shrink it until one clear moment carries the film.
        </p>
      </section>

      <section
        aria-labelledby="assignment-heading"
        className="space-y-4 rounded-xl border border-primary/30 bg-card p-6 sm:p-8"
      >
        <h2 id="assignment-heading" className="text-2xl font-semibold text-foreground">
          Your assignment
        </h2>
        <ol className="list-decimal space-y-3 pl-5">
          <li>Bring one personal detail to the idea generator and explore five possible films.</li>
          <li>
            Choose the most promising idea and give your LLM specific feedback for another pass.
          </li>
          <li>
            Write your chosen premise in one sentence. Save the opening image, the thing that
            changes, the final image, and the feeling you want to leave with the viewer.
          </li>
        </ol>
        <p>
          You’re ready for Step 2 when you can picture those images, explain what makes the idea
          interesting to you, and see it fitting into 30 seconds. Bring that premise into “Write
          your scenes.”
        </p>
      </section>
    </div>
  );
}
