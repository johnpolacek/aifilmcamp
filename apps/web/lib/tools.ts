import type { LucideIcon } from "lucide-react";
import { Clapperboard, Scissors } from "lucide-react";

export type Tool = {
  id: string;
  name: string;
  tagline: string;
  description: string;
  platform: string;
  status: "coming-soon";
  icon: LucideIcon;
};

export const tools: Tool[] = [
  {
    id: "macos-app",
    name: "AI Film Camp for Mac",
    tagline: "The production brain for your film",
    description:
      "Import a screenplay and break it down into scenes, characters, and locations. Build an asset manifest, prepare generation-ready prompts, and hand everything off to your editor.",
    platform: "macOS app",
    status: "coming-soon",
    icon: Clapperboard,
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
