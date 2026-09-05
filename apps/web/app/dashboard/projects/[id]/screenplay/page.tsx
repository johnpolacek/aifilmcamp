import { StructuredScreenplayEditor } from "@/components/structured-screenplay-editor";
import { getOwnedProject } from "@/lib/project-access";
import { parseScreenplayToElements } from "@/lib/screenplay-parser";
export const metadata = { title: "Screenplay editor - AI Film Camp" };
export default async function ScreenplayPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const project = await getOwnedProject(id);
  const elements = project.screenplayElements?.length
    ? project.screenplayElements
    : project.screenplayText
      ? parseScreenplayToElements(project.screenplayText)
      : [];
  return (
    <StructuredScreenplayEditor
      projectId={id}
      initialElements={elements}
      initialScreenplayText={project.screenplayText}
      projectTitle={project.title}
    />
  );
}
