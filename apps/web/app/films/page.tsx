import { ProjectsView } from "@/components/views/projects-view";
export const revalidate = 300;
export const metadata = {
  title: "Films - AI Film Camp",
  description: "Discover films and projects from the AI Film Camp community.",
};
export default function FilmsPage() {
  return <ProjectsView />;
}
