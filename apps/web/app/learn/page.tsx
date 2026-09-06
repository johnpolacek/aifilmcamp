import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Learn - AI Film Camp",
  description:
    "Explore the upcoming AI Film Camp course and resource library. Follow a filmmaking workflow or learn one step at a time.",
};

const resources = [
  {
    id: "script-to-shot-list",
    title: "Script to Shot List",
    action: "Plan your shots",
    description: "Break a script into a visual sequence. Decide what each shot needs to show.",
    topic: "Shot planning",
  },
  {
    id: "shot-list-to-assets",
    title: "Shot List to Asset Requirements",
    action: "Identify your assets",
    description:
      "Define the images, character and location references, video, and audio each shot needs.",
    topic: "Asset planning",
  },
  {
    id: "generate-assets",
    title: "Generate Your Assets",
    action: "Generate your assets",
    description:
      "Choose tools, develop prompts, and review the images, audio, and video you create.",
    topic: "Generation",
  },
  {
    id: "edit-your-film",
    title: "Assemble Your Film",
    action: "Bring it all together",
    description: "Arrange your shots, shape the sound, and export your finished 30-second film.",
    topic: "Editing",
  },
];

const anchorClass =
  "inline-flex min-h-11 items-center justify-center rounded-lg px-5 py-3 text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-primary";

export default function LearnPage() {
  return (
    <main className="mx-auto max-w-6xl px-4 pt-28 pb-20 sm:px-6 lg:px-8">
      <div className="max-w-3xl">
        <p className="mb-4 text-sm font-semibold tracking-widest text-primary uppercase">
          Learn at AI Film Camp
        </p>
        <h1 className="text-4xl font-bold tracking-tight text-balance sm:text-6xl">
          Learn to turn a script into a movie.
        </h1>
        <p className="mt-6 max-w-2xl text-lg leading-relaxed text-muted-foreground">
          Follow a course from start to finish, or read the individual guides when you need them.
          The same filmmaking knowledge, at your own pace.
        </p>
      </div>

      <div className="mt-10 grid gap-4 md:grid-cols-2">
        <div className="flex flex-col items-start rounded-2xl border border-primary/40 bg-primary/5 p-6 sm:p-8">
          <p className="text-sm text-muted-foreground">A guided path</p>
          <h2 className="mt-2 text-2xl font-semibold">Take the course</h2>
          <p className="mt-3 mb-6 leading-relaxed text-muted-foreground">
            Make your first 30-second film with a sequence of lessons and practical assignments.
          </p>
          <a
            href="#course"
            className={`${anchorClass} mt-auto bg-primary text-primary-foreground hover:bg-primary/90`}
          >
            Preview the course{" "}
            <span aria-hidden="true" className="ml-3">
              ↓
            </span>
          </a>
        </div>
        <div className="flex flex-col items-start rounded-2xl border border-border bg-card p-6 sm:p-8">
          <p className="text-sm text-muted-foreground">Help with a specific step</p>
          <h2 className="mt-2 text-2xl font-semibold">Browse resources</h2>
          <p className="mt-3 mb-6 leading-relaxed text-muted-foreground">
            Go straight to the topic you need. Each guide will be available to read on its own,
            without enrolling in a course.
          </p>
          <a
            href="#resources"
            className={`${anchorClass} mt-auto border border-border hover:bg-muted`}
          >
            Explore upcoming guides{" "}
            <span aria-hidden="true" className="ml-3">
              ↓
            </span>
          </a>
        </div>
      </div>

      <p className="mt-5 text-sm leading-relaxed text-muted-foreground">
        We’re building the course and library now. Here’s what’s planned; lessons aren’t available
        to read yet.
      </p>

      <section id="course" aria-labelledby="course-title" className="mt-20 scroll-mt-24">
        <div className="flex flex-wrap items-center gap-3">
          <p className="text-sm font-semibold tracking-widest text-primary uppercase">The course</p>
          <span className="rounded-full border border-border px-3 py-1 text-xs text-muted-foreground">
            In development
          </span>
        </div>
        <h2 id="course-title" className="mt-4 text-3xl font-semibold tracking-tight sm:text-4xl">
          Your First 30-Second Film
        </h2>
        <p className="mt-4 max-w-2xl leading-relaxed text-muted-foreground">
          Start with a supplied script and learn the decisions that turn it into a movie. Plan the
          shots, work out what you need, and create the assets before bringing them into an edit.
        </p>
        <ol className="mt-8 divide-y divide-border border-y border-border">
          {resources.map((resource, index) => (
            <li key={resource.id} className="flex gap-5 py-6 sm:gap-8">
              <span aria-hidden="true" className="pt-1 font-mono text-lg text-primary">
                {String(index + 1).padStart(2, "0")}
              </span>
              <div>
                <h3 className="text-lg font-semibold">{resource.action}</h3>
                <p className="mt-2 max-w-2xl leading-relaxed text-muted-foreground">
                  {resource.description}
                </p>
              </div>
            </li>
          ))}
        </ol>
        <p className="mt-5 text-sm leading-relaxed text-muted-foreground">
          The course will connect the guides below with assignments for your film and a clear next
          step after each lesson.
        </p>
      </section>

      <section id="resources" aria-labelledby="resources-title" className="mt-20 scroll-mt-24">
        <p className="text-sm font-semibold tracking-widest text-primary uppercase">The library</p>
        <h2 id="resources-title" className="mt-4 text-3xl font-semibold tracking-tight sm:text-4xl">
          The same guides. Read in any order.
        </h2>
        <p className="mt-4 max-w-2xl leading-relaxed text-muted-foreground">
          Each resource will explain one part of the process with examples you can apply to your own
          project. Follow the course, or just read what’s useful to you.
        </p>
        <div className="mt-8 grid gap-4 sm:grid-cols-2">
          {resources.map((resource) => (
            <article key={resource.id} className="rounded-xl border border-border bg-card p-6">
              <div className="flex flex-wrap items-center justify-between gap-2 text-xs">
                <span className="font-medium text-primary">{resource.topic}</span>
                <span className="text-muted-foreground">Coming soon</span>
              </div>
              <h3 className="mt-4 text-xl font-semibold">{resource.title}</h3>
              <p className="mt-3 leading-relaxed text-muted-foreground">{resource.description}</p>
            </article>
          ))}
        </div>
        <aside className="mt-6 rounded-xl border border-dashed border-border p-6">
          <h3 className="font-semibold">Need a story first?</h3>
          <p className="mt-2 leading-relaxed text-muted-foreground">
            We’re also planning a separate guide to developing a story with an LLM—from exploring
            ideas to refining a short script. You can bring your own story or use the course’s
            supplied script.
          </p>
        </aside>
      </section>
    </main>
  );
}
