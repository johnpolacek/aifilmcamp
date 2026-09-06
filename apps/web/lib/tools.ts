import type { LucideIcon } from "lucide-react";
import { Clapperboard, Lightbulb, Scissors } from "lucide-react";

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
      "Start from a genre, a mood, or a single image and get loglines, characters, and a shot list you can take straight into production.",
    platform: "Web tool",
    status: "coming-soon",
    icon: Lightbulb,
  },
  {
    id: "film-stitcher",
    name: "AI Film Stitcher",
    tagline: "Assemble generated clips into a cut",
    description:
      "Drop in the shots you generated, put them in order, and export a single film ready to share or bring into a full editor.",
    platform: "Web tool",
    status: "coming-soon",
    icon: Scissors,
  },
];
