import { auth, currentUser } from "@clerk/nextjs/server";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { ScreenplayViewer } from "@/components/screenplay-viewer";
import { StructuredScreenplayEditor } from "@/components/structured-screenplay-editor";
import { getProject } from "@/lib/projects";
import { parseScreenplayToElements } from "@/lib/screenplay-parser";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const projectData = await getProject(id);

  return {
    title: projectData
      ? `Screenplay: ${projectData.title} - AI Film Camp`
      : "Screenplay Editor - AI Film Camp",
    description: "Edit your screenplay",
  };
}

export default async function ScreenplayPage({ params }: { params: Promise<{ id: string }> }) {
  const { userId } = await auth();

  if (!userId) {
    redirect("/signin");
  }

  const { id } = await params;
  const projectId = id;

  // Get project data from S3
  const projectData = await getProject(projectId);

  if (!projectData) {
    redirect("/dashboard");
  }

  // Check if user is the owner
  const user = await currentUser();
  const currentUsername =
    user?.username || user?.emailAddresses[0]?.emailAddress.split("@")[0] || "";
  const isOwner = projectData.username === currentUsername;

  // Get screenplay elements - prefer structured elements, fall back to parsing text
  let elements = projectData.screenplayElements;

  if (!elements || elements.length === 0) {
    if (projectData.screenplayText) {
      elements = parseScreenplayToElements(projectData.screenplayText);
    }
  }

  // If owner, show editor; otherwise show viewer
  if (isOwner) {
    return (
      <StructuredScreenplayEditor
        projectId={projectId}
        initialElements={elements}
        initialScreenplayText={projectData.screenplayText}
        projectTitle={projectData.title}
      />
    );
  }

  // Not owner - show read-only viewer
  return (
    <ScreenplayViewer
      projectId={projectId}
      elements={elements || []}
      projectTitle={projectData.title}
      username={projectData.username}
      isOwner={false}
      backUrl="/dashboard"
      backLabel="Back to Dashboard"
    />
  );
}
