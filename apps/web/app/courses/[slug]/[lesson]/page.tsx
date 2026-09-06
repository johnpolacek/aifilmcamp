import { ArrowLeft, ArrowRight } from "lucide-react";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { TransitionLink } from "@/components/motion/transition";
import { courses, getCourse, getLesson } from "@/lib/courses";

type Props = { params: Promise<{ slug: string; lesson: string }> };

export function generateStaticParams() {
  return courses.flatMap((course) =>
    course.outline.map((lesson) => ({ slug: course.slug, lesson: lesson.slug }))
  );
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug, lesson: lessonSlug } = await params;
  const course = getCourse(slug);
  const found = course && getLesson(course, lessonSlug);
  if (!course || !found) return {};
  return {
    title: `${found.lesson.title} - ${course.title} - AI Film Camp`,
    description: found.lesson.description,
  };
}

const placeholderSections = [
  {
    title: "Lesson",
    body: "The lesson itself: what this step is for, how to think about it, and a worked example from the course’s supplied script.",
  },
  {
    title: "Assignment",
    body: "A short, practical task that applies the lesson to your own 30-second film before moving on.",
  },
  {
    title: "Resources",
    body: "Links to the tools, prompts, and reference material used in this step.",
  },
];

const navClass =
  "flex flex-1 flex-col gap-1 rounded-xl border border-border bg-card p-5 transition-colors hover:border-primary/50";

export default async function LessonPage({ params }: Props) {
  const { slug, lesson: lessonSlug } = await params;
  const course = getCourse(slug);
  const found = course && getLesson(course, lessonSlug);
  if (!course || !found) notFound();

  const { lesson, index, previous, next } = found;
  const live = course.status === "live";
  const courseHref = `/courses/${course.slug}`;

  return (
    <main className="mx-auto max-w-6xl px-4 pt-28 pb-20 sm:px-6 lg:px-8">
      <nav aria-label="Breadcrumb" className="text-sm text-muted-foreground">
        <TransitionLink href={courseHref} className="transition-colors hover:text-foreground">
          {course.title}
        </TransitionLink>
        <span aria-hidden="true" className="mx-2">
          /
        </span>
        <span>
          Step {index + 1} of {course.outline.length}
        </span>
      </nav>

      <div className="mt-8 max-w-3xl">
        {!live && (
          <span className="inline-block rounded-full border border-border px-3 py-1 text-xs text-muted-foreground">
            Coming soon
          </span>
        )}
        <h1 className="mt-4 text-4xl font-bold tracking-tight text-balance sm:text-5xl">
          {lesson.title}
        </h1>
        <p className="mt-6 max-w-2xl text-lg leading-relaxed text-muted-foreground">
          {lesson.description}
        </p>
      </div>

      {!live && (
        <p className="mt-5 text-sm leading-relaxed text-muted-foreground">
          This lesson is being written. Here’s what it will include.
        </p>
      )}

      <div className="mt-12 grid gap-4">
        {placeholderSections.map((section) => (
          <section
            key={section.title}
            aria-label={section.title}
            className={`rounded-xl border border-border p-6 sm:p-8 ${live ? "bg-card" : "border-dashed"}`}
          >
            <h2 className="text-sm font-semibold tracking-widest text-primary uppercase">
              {section.title}
            </h2>
            <p className="mt-3 max-w-2xl leading-relaxed text-muted-foreground">{section.body}</p>
          </section>
        ))}
      </div>

      <nav aria-label="Lesson navigation" className="mt-16 flex flex-col gap-4 sm:flex-row">
        {previous ? (
          <TransitionLink href={`${courseHref}/${previous.slug}`} className={navClass}>
            <span className="flex items-center gap-2 text-xs text-muted-foreground">
              <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
              Previous
            </span>
            <span className="font-semibold">{previous.title}</span>
          </TransitionLink>
        ) : (
          <TransitionLink href={courseHref} className={navClass}>
            <span className="flex items-center gap-2 text-xs text-muted-foreground">
              <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
              Back to
            </span>
            <span className="font-semibold">{course.title}</span>
          </TransitionLink>
        )}
        {next ? (
          <TransitionLink
            href={`${courseHref}/${next.slug}`}
            className={`${navClass} sm:items-end sm:text-right`}
          >
            <span className="flex items-center gap-2 text-xs text-muted-foreground">
              Next
              <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
            </span>
            <span className="font-semibold">{next.title}</span>
          </TransitionLink>
        ) : (
          <TransitionLink href={courseHref} className={`${navClass} sm:items-end sm:text-right`}>
            <span className="flex items-center gap-2 text-xs text-muted-foreground">
              Finished
              <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
            </span>
            <span className="font-semibold">Back to {course.title}</span>
          </TransitionLink>
        )}
      </nav>
    </main>
  );
}
