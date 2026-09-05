import { auth, currentUser } from "@clerk/nextjs/server";
import { notFound, redirect } from "next/navigation";
import { EditScenePromptsView } from "@/components/views/edit-scene-prompts-view";
import { getProject } from "@/lib/projects";
import { getScene } from "@/lib/scenes";

export const metadata = { title: "Scene planning - AI Film Camp" };

export default async function EditScenePage({
  params,
}: {
  params: Promise<{ id: string; sceneId: string }>;
}) {
  // Check authentication
  const { userId } = await auth();

  if (!userId) {
    redirect("/signin");
  }

  const { id: projectId, sceneId } = await params;

  // Get project data (for characters)
  const projectData = await getProject(projectId);

  if (!projectData) {
    notFound();
  }

  // Verify user owns the project
  const user = await currentUser();
  const currentUsername =
    user?.username || user?.emailAddresses[0]?.emailAddress.split("@")[0] || "";

  if (projectData.username !== currentUsername) {
    redirect("/dashboard");
  }

  // Get scene data
  const scene = await getScene(projectId, sceneId);

  if (!scene) {
    notFound();
  }

  return (
    <EditScenePromptsView
      scene={scene}
      projectId={projectId}
      projectTitle={projectData.title}
      characters={projectData.characters || []}
      locations={projectData.setting?.locations || []}
    />
  );
}
