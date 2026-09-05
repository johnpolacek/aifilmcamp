import type { Metadata } from "next";
import { NewProjectView } from "@/components/views/new-project-view";

export const metadata: Metadata = {
  title: "New Project - AI Film Camp",
  description: "Create a new AI film project",
};

export default function NewProjectPage() {
  return <NewProjectView />;
}
