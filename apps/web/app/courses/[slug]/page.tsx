import { Show, SignUpButton } from "@clerk/nextjs";
import { ChevronRight } from "lucide-react";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { TransitionLink } from "@/components/motion/transition";
import { Button, buttonVariants } from "@/components/ui/button";
import { courses, getCourse } from "@/lib/courses";

type Props = { params: Promise<{ slug: string }> };

export function generateStaticParams() {
  return courses.map((course) => ({ slug: course.slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const course = getCourse(slug);
  if (!course) return {};
  return {
    title: `${course.title} - AI Film Camp`,
    description: course.description,
  };
}

const ctaClass = "bg-[#2c4494] text-white hover:bg-[#3854b3]";

export default async function CoursePage({ params }: Props) {
  const { slug } = await params;
  const course = getCourse(slug);
  if (!course) notFound();

  const Icon = course.icon;
  const live = course.status === "live";
  const others = courses.filter((other) => other.slug !== course.slug);

  return (
    <main className="mx-auto max-w-6xl px-4 pt-28 pb-20 sm:px-6 lg:px-8">
      <div>
        <div className="flex flex-wrap items-center gap-3">
          <p className="text-sm font-semibold tracking-widest text-primary uppercase">
            {course.level} course
          </p>
          {!live && (
            <span className="rounded-full border border-border px-3 py-1 text-xs text-muted-foreground">
              Coming soon
            </span>
          )}
        </div>
        <div className="mt-4 flex items-start gap-4">
          <div className="mt-1 flex h-12 w-12 shrink-0 items-center justify-center rounded-lg bg-primary/10">
            <Icon className="h-6 w-6 text-primary" />
          </div>
          <h1 className="text-4xl font-bold tracking-tight text-balance sm:text-6xl">
            {course.title}
          </h1>
        </div>
        <p className="mt-6 text-lg leading-relaxed text-muted-foreground">{course.description}</p>
        <div className="mt-8 flex flex-wrap items-center gap-5">
          <p className="text-2xl font-semibold">
            <span className="mr-2 text-muted-foreground line-through">${course.price}</span>
            <span className="text-primary">FREE</span>
          </p>
          {live ? (
            <TransitionLink
              href={`/courses/${course.slug}/${course.outline[0].slug}`}
              className={buttonVariants({ className: ctaClass })}
            >
              Start the course
              <ChevronRight className="h-4 w-4" />
            </TransitionLink>
          ) : (
            <>
              <Show when="signed-out">
                <SignUpButton mode="modal">
                  <Button type="button" className={ctaClass}>
                    Sign up to get notified
                    <ChevronRight className="h-4 w-4" />
                  </Button>
                </SignUpButton>
              </Show>
              <Show when="signed-in">
                <TransitionLink href="/dashboard" className={buttonVariants({ className: ctaClass })}>
                  Go to your dashboard
                  <ChevronRight className="h-4 w-4" />
                </TransitionLink>
              </Show>
            </>
          )}
        </div>
      </div>

      {!live && (
        <p className="mt-5 text-sm leading-relaxed text-muted-foreground">
          We’re building this course now. Here’s what’s planned; lessons aren’t available yet.
        </p>
      )}

      <section aria-labelledby="outline-title" className="mt-20">
        <p className="text-sm font-semibold tracking-widest text-primary uppercase">
          What you’ll learn
        </p>
        <h2 id="outline-title" className="mt-4 text-3xl font-semibold tracking-tight sm:text-4xl">
          The course, step by step.
        </h2>
        <ol className="mt-8 divide-y divide-border border-y border-border">
          {course.outline.map((step, index) => (
            <li key={step.slug}>
              <TransitionLink
                href={`/courses/${course.slug}/${step.slug}`}
                className="group flex gap-5 py-6 sm:gap-8"
              >
                <span aria-hidden="true" className="pt-1 font-mono text-lg text-primary">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <div className="flex-1">
                  <h3 className="text-lg font-semibold transition-colors group-hover:text-primary">
                    {step.title}
                  </h3>
                  <p className="mt-2 max-w-2xl leading-relaxed text-muted-foreground">
                    {step.description}
                  </p>
                </div>
                <ChevronRight
                  aria-hidden="true"
                  className="mt-1.5 h-5 w-5 shrink-0 text-muted-foreground transition-colors group-hover:text-primary"
                />
              </TransitionLink>
            </li>
          ))}
        </ol>
      </section>

      <section aria-labelledby="others-title" className="mt-20">
        <h2 id="others-title" className="text-2xl font-semibold tracking-tight">
          Other courses
        </h2>
        <div className="mt-6 grid gap-4 sm:grid-cols-3">
          {others.map((other) => {
            const OtherIcon = other.icon;
            return (
              <TransitionLink
                key={other.slug}
                href={`/courses/${other.slug}`}
                className="flex flex-col rounded-xl border border-border bg-card p-6 transition-colors hover:border-primary/50"
              >
                <div className="flex items-center gap-3">
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary/10">
                    <OtherIcon className="h-4 w-4 text-primary" />
                  </div>
                  <p className="text-xs font-semibold tracking-widest text-primary uppercase">
                    {other.level}
                  </p>
                </div>
                <h3 className="mt-4 text-lg font-semibold leading-tight text-balance">
                  {other.title}
                </h3>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                  {other.description}
                </p>
              </TransitionLink>
            );
          })}
        </div>
      </section>
    </main>
  );
}
