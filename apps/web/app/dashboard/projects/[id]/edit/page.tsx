import { EditProjectView } from "@/components/views/edit-project-view";
import { getOwnedProject } from "@/lib/project-access";

export const metadata = { title: "Project details - AI Film Camp" };

export default async function EditProjectPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const projectData = await getOwnedProject(id);
  return <EditProjectView projectData={projectData} projectId={id} />;
}
