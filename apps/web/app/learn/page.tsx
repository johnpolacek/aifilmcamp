import { ChevronRight } from "lucide-react";
import type { Metadata } from "next";
import { TransitionLink } from "@/components/motion/transition";
import { courses } from "@/lib/courses";

export const metadata: Metadata = {
  title: "Learn - AI Film Camp",
  description:
    "Courses and articles on making films with AI. Follow a course from start to finish, or read the individual guides when you need them.",
};

const articles = courses
  .filter((course) => course.slug !== "complete-course")
  .flatMap((course) =>
    course.outline.map((lesson) => ({ ...lesson, href: `/courses/${course.slug}/${lesson.slug}` }))
  );

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

      <section aria-labelledby="courses-title" className="mt-16">
        <h2 id="courses-title" className="text-sm font-semibold tracking-widest text-primary uppercase">
          Courses
        </h2>
        <div className="mt-6 grid gap-4 md:grid-cols-2">
          {courses.map((course) => {
            const Icon = course.icon;
            return (
              <TransitionLink
                key={course.slug}
                href={`/courses/${course.slug}`}
                className="group flex flex-col rounded-2xl border border-border bg-card p-6 transition-colors hover:border-primary/50 sm:p-8"
              >
                <div className="flex items-center gap-3">
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary/10">
                    <Icon className="h-5 w-5 text-primary" />
                  </div>
                  <div>
                    <p className="text-xs font-semibold tracking-widest text-primary uppercase">
                      {course.level}
                    </p>
                    <h3 className="text-xl font-semibold leading-tight text-balance">
                      {course.title}
                    </h3>
                  </div>
                </div>
                <p className="mt-4 leading-relaxed text-muted-foreground">{course.description}</p>
                <div className="mt-6 flex items-center justify-between pt-1">
                  <p className="text-lg font-semibold">
                    <span className="mr-2 text-muted-foreground line-through">${course.price}</span>
                    <span className="text-primary">FREE</span>
                  </p>
                  {course.status === "live" ? (
                    <span className="flex items-center gap-1 text-sm font-semibold transition-colors group-hover:text-primary">
                      Start
                      <ChevronRight className="h-4 w-4" aria-hidden="true" />
                    </span>
                  ) : (
                    <span className="rounded-full border border-border px-3 py-1 text-xs text-muted-foreground">
                      Coming soon
                    </span>
                  )}
                </div>
              </TransitionLink>
            );
          })}
        </div>
      </section>

      <section aria-labelledby="articles-title" className="mt-20">
        <h2 id="articles-title" className="text-sm font-semibold tracking-widest text-primary uppercase">
          Articles
        </h2>
        <ul className="mt-6 divide-y divide-border border-y border-border">
          {articles.map((article) => (
            <li key={article.href}>
              <TransitionLink href={article.href} className="group flex gap-5 py-5 sm:gap-8">
                <div className="flex-1">
                  <h3 className="text-lg font-semibold transition-colors group-hover:text-primary">
                    {article.title}
                  </h3>
                  <p className="mt-1 max-w-2xl leading-relaxed text-muted-foreground">
                    {article.description}
                  </p>
                </div>
                <ChevronRight
                  aria-hidden="true"
                  className="mt-1.5 h-5 w-5 shrink-0 text-muted-foreground transition-colors group-hover:text-primary"
                />
              </TransitionLink>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}
