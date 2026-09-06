import type { LucideIcon } from "lucide-react";
import { Clapperboard, Film, Sparkles, Trophy } from "lucide-react";

export type Course = {
  slug: string;
  icon: LucideIcon;
  level: string;
  title: string;
  description: string;
  price: number;
  status: "coming-soon";
  /** What the finished course will cover, in order. */
  outline: { title: string; description: string }[];
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
    status: "coming-soon",
    outline: [
      {
        title: "Plan your shots",
        description: "Break a supplied script into a visual sequence and decide what each shot needs to show.",
      },
      {
        title: "Identify your assets",
        description: "Define the images, references, video, and audio each shot needs.",
      },
      {
        title: "Generate your assets",
        description: "Choose tools, develop prompts, and review what you create.",
      },
      {
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
        title: "Write a multi-scene story",
        description: "Shape a short script with a beginning, middle, and end across several locations.",
      },
      {
        title: "Keep characters consistent",
        description: "Build reference sheets so the same faces, costumes, and places hold from shot to shot.",
      },
      {
        title: "Direct performance and pacing",
        description: "Use dialogue, voice, and shot length to carry a story arc.",
      },
      {
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
        title: "Develop a full screenplay",
        description: "Structure a longer story and refine it into a production-ready script.",
      },
      {
        title: "Build an asset pipeline",
        description: "Break the script down into a manifest and generate hundreds of shots without losing track.",
      },
      {
        title: "Design the sound",
        description: "Layer dialogue, effects, ambience, and score into a finished mix.",
      },
      {
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
        title: "Your First 30-Second Film",
        description: "Learn the core workflow of writing, generating, and editing in one sitting.",
      },
      {
        title: "The Two-Minute Short",
        description: "Build a multi-scene story with consistent characters and a real arc.",
      },
      {
        title: "The 10-Minute+ Film",
        description: "Produce a longer film with a full screenplay, asset pipeline, and final edit.",
      },
    ],
  },
];

export function getCourse(slug: string): Course | undefined {
  return courses.find((course) => course.slug === slug);
}
