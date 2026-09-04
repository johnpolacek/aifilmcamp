import { auth } from "@clerk/nextjs/server";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ScreenplayViewer } from "@/components/screenplay-viewer";
import { ensureProjectPhaseVisibility } from "@/lib/development";
import { getProjectByUsernameAndSlug } from "@/lib/projects";
import { parseScreenplayToElements } from "@/lib/screenplay-parser";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ username: string; projectSlug: string }>;
}): Promise<Metadata> {
  const { username, projectSlug } = await params;
  const projectData = await getProjectByUsernameAndSlug(username, projectSlug);

  if (!projectData) {
    return {
      title: "Screenplay Not Found - AI Film Camp",
    };
  }

  const { project } = projectData;

  return {
    title: `Screenplay: ${project.title} - ${username} - AI Film Camp`,
    description: project.logline || `Read the screenplay for ${project.title} by ${username}`,
  };
}

export default async function PublicScreenplayPage({
  params,
}: {
  params: Promise<{ username: string; projectSlug: string }>;
}) {
  const { username, projectSlug } = await params;

  // Get project data
  const projectData = await getProjectByUsernameAndSlug(username, projectSlug);

  if (!projectData) {
    notFound();
  }

  const { project, id } = projectData;

  // Get screenplay elements - prefer structured elements, fall back to parsing text
  let elements = project.screenplayElements;

  if (!elements || elements.length === 0) {
    if (project.screenplayText) {
      elements = parseScreenplayToElements(project.screenplayText);
    } else {
      elements = [];
    }
  }

  // Check if current user is the owner
  const { userId } = await auth();
  let isOwner = false;

  if (userId) {
    // Get current user's username to compare
    const { currentUser } = await import("@clerk/nextjs/server");
    const user = await currentUser();
    const currentUsername = user?.username || user?.emailAddresses[0]?.emailAddress.split("@")[0];
    isOwner = currentUsername === username;
  }

  if (!isOwner && ensureProjectPhaseVisibility(project).screenplay !== "published") {
    notFound();
  }

  return (
    <ScreenplayViewer
      projectId={id}
      elements={elements}
      projectTitle={project.title}
      username={username}
      isOwner={isOwner}
      backUrl={`/${username}/${projectSlug}`}
      backLabel="Back to Project"
    />
  );
}
