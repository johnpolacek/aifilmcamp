import { ChevronRight } from "lucide-react";
import { TransitionLink } from "@/components/motion/transition";
import { buttonVariants } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { courses } from "@/lib/courses";

const ctaClass = "bg-[#2c4494] text-white hover:bg-[#3854b3]";

export function Courses() {
  return (
    <section id="courses" data-courses className="pt-6 pb-20 lg:pb-32">
      <div data-outro className="container mx-auto px-4 lg:px-8">
        <div className="text-center mb-10">
          <h2 data-courses-title className="text-3xl lg:text-5xl font-bold mb-4 text-balance text-shadow-[0_0_12px_rgba(0,0,0,0.5)]">
            From Zero to Hero
          </h2>
          <p
            data-courses-lede
            className="text-lg text-white text-balance max-w-2xl mx-auto text-shadow-[0_0_12px_rgba(0,0,0,0.5)]"
          >
            Courses are coming soon. Start with a 30-second short and work your way up to a complete
            film, one step at a time.
          </p>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6 max-w-6xl mx-auto [perspective:1200px]">
          {courses.map((course) => {
            const Icon = course.icon;
            return (
              <div key={course.slug} data-card className="flex [transform-style:preserve-3d]">
                <TransitionLink href={`/courses/${course.slug}`} className="flex w-full">
                  <Card className="w-full p-5 gap-3 bg-[#050a1c] border-[#121d40] hover:border-primary/50 transition-colors cursor-pointer">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 shrink-0 rounded-lg bg-primary/10 flex items-center justify-center">
                        <Icon className="h-5 w-5 text-primary" />
                      </div>
                      <div>
                        <p className="text-xs font-semibold tracking-widest text-primary uppercase">
                          {course.level}
                        </p>
                        <h3 className="text-lg font-semibold leading-tight text-balance">
                          {course.title}
                        </h3>
                      </div>
                    </div>
                    <p className="text-sm text-muted-foreground leading-relaxed text-balance">
                      {course.description}
                    </p>
                    <div className="mt-auto flex items-center justify-between pt-1">
                      <p className="text-lg font-semibold">
                        <span className="text-muted-foreground line-through mr-2">${course.price}</span>
                        <span className="text-primary">FREE</span>
                      </p>
                      <span className={buttonVariants({ size: "sm", className: ctaClass })}>
                        Learn more
                        <ChevronRight className="h-4 w-4" />
                      </span>
                    </div>
                  </Card>
                </TransitionLink>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
