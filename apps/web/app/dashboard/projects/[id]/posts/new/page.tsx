import { auth } from "@clerk/nextjs/server";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { NewPostView } from "@/components/views/new-post-view";
import { getProject } from "@/lib/projects";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const project = await getProject(id);

  return {
    title: project ? `New Post - ${project.title} - AI Film Camp` : "New Post - AI Film Camp",
    description: "Create a new post for your project",
  };
}

export default async function NewPostPage({ params }: { params: Promise<{ id: string }> }) {
  const { userId } = await auth();

  if (!userId) {
    redirect("/signin");
  }

  const { id } = await params;
  const projectId = id;

  // Verify project exists and user has access
  const project = await getProject(projectId);

  if (!project) {
    redirect("/dashboard");
  }

  return <NewPostView projectId={projectId} />;
}
