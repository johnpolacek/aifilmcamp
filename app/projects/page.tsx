import type { Metadata } from "next";
import { ProjectsView } from "@/components/views/projects-view";

export const metadata: Metadata = {
  title: "Community Projects - AI Film Camp",
  description:
    "Explore public AI film development packages, prompts, scripts, and reference assets from creators around the world.",
};

export default function ProjectsPage() {
  return <ProjectsView />;
}
