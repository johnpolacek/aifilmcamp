import Link from "next/link";
import ProjectForm from "@/components/project-form";
import { getOwnedProject } from "@/lib/project-access";

export const metadata = { title: "Development workspace - AI Film Camp" };

export default async function DevelopmentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const project = await getOwnedProject(id);
  return (
    <main className="px-4 pt-28 pb-16 lg:px-8">
      <div className="mx-auto max-w-7xl">
        <Link
          href={`/dashboard/projects/${id}/edit`}
          className="text-sm text-primary hover:underline"
        >
          ← Project details
        </Link>
        <h1 className="mt-6 text-3xl font-bold">Development workspace</h1>
        <p className="mt-2 mb-8 text-muted-foreground">
          Your private working material for {project.title}.
        </p>
        <ProjectForm
          initialData={project}
          projectId={id}
          isEditing
          useGridLayout
          redirectPath={`/dashboard/projects/${id}/edit`}
        />
      </div>
    </main>
  );
}
