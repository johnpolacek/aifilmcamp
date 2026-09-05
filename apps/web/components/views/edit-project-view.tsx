import Link from "next/link";
import { ProjectBasicsForm } from "@/components/project-basics-form";
import type { ProjectFormData } from "@/components/project-form";
import { ShareProjectButton } from "@/components/share-project-button";
import { Button } from "@/components/ui/button";

export function EditProjectView({
  projectData,
  projectId,
}: {
  projectData: ProjectFormData;
  projectId: string;
}) {
  const { title, logline, thumbnail, filmLink, isPublished, username, slug } = projectData;
  return (
    <main className="min-h-screen bg-background px-4 pt-28 pb-16">
      <div className="mx-auto max-w-2xl">
        <Link href="/dashboard" className="text-sm text-primary hover:underline">
          ← My projects
        </Link>
        <div className="my-8 flex flex-wrap items-center justify-between gap-4">
          <h1 className="text-3xl font-bold">Project details</h1>
          {username && slug && (
            <Button variant="outline" asChild>
              <Link href={`/${username}/${slug}`}>
                {isPublished ? "View public page" : "Preview page"}
              </Link>
            </Button>
          )}
        </div>
        <ProjectBasicsForm
          projectId={projectId}
          username={username}
          initialData={{ title, logline, thumbnail, filmLink, isPublished }}
        />
        {isPublished && username && slug && (
          <div className="mt-6 rounded-lg border p-4 text-sm">
            <div className="mb-2 flex items-center justify-between gap-4">
              <p className="font-medium">Share your project</p>
              <ShareProjectButton path={`/${username}/${slug}`} />
            </div>
            <Link className="break-all text-primary hover:underline" href={`/${username}/${slug}`}>
              /{username}/{slug}
            </Link>
          </div>
        )}
        <div className="mt-10 border-t pt-6">
          <Link
            className="font-medium text-primary hover:underline"
            href={`/dashboard/projects/${projectId}/development`}
          >
            Development workspace →
          </Link>
          <p className="mt-2 text-sm text-muted-foreground">
            Work on your script, characters, scenes, and assets.
          </p>
        </div>
      </div>
    </main>
  );
}
