import { Clapperboard, Film, Sparkles, Trophy } from "lucide-react";
import { Card } from "@/components/ui/card";

const courses = [
  {
    icon: Sparkles,
    level: "Intro",
    title: "Your First 30-Second Film",
    description:
      "Go from idea to a finished short in one sitting. Learn the core workflow of writing, generating, and editing.",
    price: 20,
  },
  {
    icon: Clapperboard,
    level: "Intermediate",
    title: "The Two-Minute Short",
    description:
      "Build a story with multiple scenes, consistent characters, and a real narrative arc across shots.",
    price: 20,
  },
  {
    icon: Film,
    level: "Advanced",
    title: "The 10-Minute+ Film",
    description:
      "Plan and produce a longer film with a full screenplay, asset pipeline, sound design, and final edit.",
    price: 20,
  },
  {
    icon: Trophy,
    level: "Everything",
    title: "The Complete Course",
    description:
      "All three courses in one guided path, from your first 30 seconds to a finished 10-minute film.",
    price: 50,
  },
];

export function Courses() {
  return (
    <section id="courses" className="pt-4 pb-20 lg:pb-32">
      <div className="container mx-auto px-4 lg:px-8">
        <div className="text-center mb-10">
          <h2 className="text-3xl lg:text-5xl font-bold mb-4 text-balance">From Zero to Hero</h2>
          <p className="text-lg text-muted-foreground text-pretty max-w-2xl mx-auto">
            Courses are coming soon. Start with a 30-second short and work your way up to a
            complete film, one step at a time.
          </p>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6 max-w-6xl mx-auto">
          {courses.map((course) => {
            const Icon = course.icon;
            return (
              <Card
                key={course.title}
                className="p-6 space-y-0! bg-[#0b1530] border-[#1c2a55] hover:border-primary/50 transition-colors"
              >
                <div className="w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center">
                  <Icon className="h-6 w-6 text-primary" />
                </div>
                <p className="text-xs font-semibold tracking-widest text-primary uppercase">
                  {course.level}
                </p>
                <h3 className="text-lg font-semibold text-balance -mt-2">{course.title}</h3>
                <p className="text-sm text-muted-foreground leading-relaxed -mt-2">
                  {course.description}
                </p>
                <p className="text-lg font-semibold mt-auto pt-4">
                  <span className="text-muted-foreground line-through mr-2">${course.price}</span>
                  <span className="text-primary">FREE</span>
                </p>
              </Card>
            );
          })}
        </div>
      </div>
    </section>
  );
}
