import { auth } from "@clerk/nextjs/server";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { EditPostView } from "@/components/views/edit-post-view";
import { getPost } from "@/lib/posts";
import { getProject } from "@/lib/projects";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string; postId: string }>;
}): Promise<Metadata> {
  const { postId } = await params;
  const post = await getPost(postId);

  return {
    title: post ? `Edit ${post.title} - AI Film Camp` : "Edit Post - AI Film Camp",
    description: "Edit your project post",
  };
}

export default async function EditPostPage({
  params,
}: {
  params: Promise<{ id: string; postId: string }>;
}) {
  const { userId } = await auth();

  if (!userId) {
    redirect("/signin");
  }

  const { id: projectId, postId } = await params;

  // Verify project exists and user has access
  const project = await getProject(projectId);

  if (!project) {
    redirect("/dashboard");
  }

  // Get post data
  const post = await getPost(postId);

  if (!post || post.projectId !== projectId) {
    redirect("/dashboard");
  }

  return <EditPostView projectId={projectId} post={post} />;
}
