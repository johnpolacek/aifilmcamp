import type { LucideIcon } from "lucide-react";
import { Clapperboard, Lightbulb } from "lucide-react";

export type ToolDownload = {
  href: string;
  label: string;
  requirements: string;
};

export type Tool = {
  id: string;
  name: string;
  tagline: string;
  description: string;
  platform: string;
  status: "live" | "coming-soon";
  icon: LucideIcon;
  href?: string;
  download?: ToolDownload;
};

export const MACOS_APP_RELEASES_URL = "https://github.com/johnpolacek/aifilmclub/releases";
export const MACOS_APP_DOWNLOAD_URL = `${MACOS_APP_RELEASES_URL}/latest/download/AI-Film-Camp.dmg`;

export const tools: Tool[] = [
  {
    id: "macos-app",
    name: "AI Film Camp for Mac",
    tagline: "The production brain for your film",
    description:
      "Import a screenplay and break it down into scenes, characters, and locations. Build an asset manifest, prepare generation-ready prompts, and hand everything off to your editor.",
    platform: "macOS app",
    status: "live",
    icon: Clapperboard,
    download: {
      href: "/download/mac",
      label: "Download for Mac",
      requirements: "Free with an account. Requires macOS 15 or later on Apple silicon.",
    },
  },
  {
    id: "idea-generator",
    name: "AI Film Idea Generator",
    tagline: "Find a story worth making",
    description:
      "Build a prompt for your next film. Choose a duration and genre, add your inspirations, then copy it into your own LLM agent to explore ideas.",
    platform: "Web tool",
    status: "live",
    icon: Lightbulb,
    href: "/tools/idea-generator",
  },
];

export function getTool(id: string): Tool {
  const tool = tools.find((candidate) => candidate.id === id);
  if (!tool) throw new Error(`Unknown tool: ${id}`);
  return tool;
}
