import type { Metadata } from "next";
import { ProjectsView } from "@/components/views/projects-view";

export const metadata: Metadata = {
  title: "Community Projects - AI Film Camp",
  description: "Discover films and projects from the AI Film Camp community.",
};

export const revalidate = 300;

export default function ProjectsPage() {
  return <ProjectsView />;
}
