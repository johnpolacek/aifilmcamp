import type { LucideIcon } from "lucide-react";
import { Clapperboard, Film, Sparkles, Trophy } from "lucide-react";

export type Course = {
  slug: string;
  icon: LucideIcon;
  level: string;
  title: string;
  description: string;
  price: number;
  status: "live" | "coming-soon";
  /** What the finished course will cover, in order. */
  outline: Lesson[];
};

export type Lesson = {
  slug: string;
  title: string;
  description: string;
};

export const courses: Course[] = [
  {
    slug: "first-30-second-film",
    icon: Sparkles,
    level: "Intro",
    title: "Your First 30-Second Film",
    description:
      "Go from idea to a finished short in one sitting. Learn the core workflow of writing, generating, and editing.",
    price: 20,
    status: "live",
    outline: [
      {
        slug: "come-up-with-an-idea",
        title: "Come up with an idea",
        description: "Work with an LLM to explore unexpected ideas, make one your own, and shape it into a story you can tell in 30 seconds.",
      },
      {
        slug: "write-your-scenes",
        title: "Write your scenes",
        description: "Turn the idea into a short script and break it into scenes, deciding what each one needs to show.",
      },
      {
        slug: "identify-your-assets",
        title: "Identify your assets",
        description: "Define the images, references, video, and audio each shot needs.",
      },
      {
        slug: "generate-your-assets",
        title: "Generate your assets",
        description: "Choose tools, develop prompts, and review what you create.",
      },
      {
        slug: "bring-it-all-together",
        title: "Bring it all together",
        description: "Arrange your shots, shape the sound, and export a finished 30-second film.",
      },
    ],
  },
  {
    slug: "two-minute-short",
    icon: Clapperboard,
    level: "Intermediate",
    title: "The Two-Minute Short",
    description:
      "Build a story with multiple scenes, consistent characters, and a real narrative arc across shots.",
    price: 20,
    status: "coming-soon",
    outline: [
      {
        slug: "write-a-multi-scene-story",
        title: "Write a multi-scene story",
        description: "Shape a short script with a beginning, middle, and end across several locations.",
      },
      {
        slug: "keep-characters-consistent",
        title: "Keep characters consistent",
        description: "Build reference sheets so the same faces, costumes, and places hold from shot to shot.",
      },
      {
        slug: "direct-performance-and-pacing",
        title: "Direct performance and pacing",
        description: "Use dialogue, voice, and shot length to carry a story arc.",
      },
      {
        slug: "cut-a-two-minute-film",
        title: "Cut a two-minute film",
        description: "Edit across scenes with transitions, music, and sound that serve the story.",
      },
    ],
  },
  {
    slug: "ten-minute-film",
    icon: Film,
    level: "Advanced",
    title: "The 10-Minute+ Film",
    description:
      "Plan and produce a longer film with a full screenplay, asset pipeline, sound design, and final edit.",
    price: 20,
    status: "coming-soon",
    outline: [
      {
        slug: "develop-a-full-screenplay",
        title: "Develop a full screenplay",
        description: "Structure a longer story and refine it into a production-ready script.",
      },
      {
        slug: "build-an-asset-pipeline",
        title: "Build an asset pipeline",
        description: "Break the script down into a manifest and generate hundreds of shots without losing track.",
      },
      {
        slug: "design-the-sound",
        title: "Design the sound",
        description: "Layer dialogue, effects, ambience, and score into a finished mix.",
      },
      {
        slug: "finish-and-release",
        title: "Finish and release",
        description: "Assemble the final edit, color and title it, and share the film.",
      },
    ],
  },
  {
    slug: "complete-course",
    icon: Trophy,
    level: "Everything",
    title: "The Complete Course",
    description:
      "All three courses in one guided path, from your first 30 seconds to a finished 10-minute film.",
    price: 50,
    status: "coming-soon",
    outline: [
      {
        slug: "your-first-30-second-film",
        title: "Your First 30-Second Film",
        description: "Learn the core workflow of writing, generating, and editing in one sitting.",
      },
      {
        slug: "the-two-minute-short",
        title: "The Two-Minute Short",
        description: "Build a multi-scene story with consistent characters and a real arc.",
      },
      {
        slug: "the-10-minute-film",
        title: "The 10-Minute+ Film",
        description: "Produce a longer film with a full screenplay, asset pipeline, and final edit.",
      },
    ],
  },
];

export function getCourse(slug: string): Course | undefined {
  return courses.find((course) => course.slug === slug);
}

export function getLesson(course: Course, slug: string) {
  const index = course.outline.findIndex((lesson) => lesson.slug === slug);
  if (index === -1) return undefined;
  return {
    lesson: course.outline[index],
    index,
    previous: course.outline[index - 1],
    next: course.outline[index + 1],
  };
}
