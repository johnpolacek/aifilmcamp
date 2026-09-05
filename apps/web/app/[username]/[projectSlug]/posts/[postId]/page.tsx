import type { Metadata } from "next";
import { notFound } from "next/navigation";
import type { ProjectFormData } from "@/components/project-form";
import { PostView } from "@/components/views/post-view";
import { getPostImageUrl } from "@/lib/image-utils";
import { getPost } from "@/lib/posts";
import { getUserProfile } from "@/lib/profiles";
import { getProject } from "@/lib/projects";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ username: string; projectSlug: string; postId: string }>;
}): Promise<Metadata> {
  const { username, projectSlug, postId } = await params;
  const post = await getPost(postId);

  if (!post) {
    return {
      title: "Post Not Found - AI Film Camp",
    };
  }

  const project = await getProject(post.projectId);

  if (!project || project.username !== username || project.slug !== projectSlug) {
    return {
      title: "Post Not Found - AI Film Camp",
    };
  }

  // Get the first image from the post (post.image field)
  const postImageUrl =
    post.image && (post.username || username)
      ? getPostImageUrl(post.image, post.username || username)
      : undefined;

  const metadata: Metadata = {
    title: `${post.title} - ${project.title} - AI Film Camp`,
    description: post.content.substring(0, 160) || `Read ${post.title} by ${username}`,
  };

  // Add image to OpenGraph and Twitter metadata if available
  if (postImageUrl) {
    metadata.openGraph = {
      images: [postImageUrl],
    };
    metadata.twitter = {
      card: "summary_large_image",
      images: [postImageUrl],
    };
  }

  return metadata;
}

export default async function PostPage({
  params,
}: {
  params: Promise<{ username: string; projectSlug: string; postId: string }>;
}) {
  const { username, projectSlug, postId } = await params;

  // Get post data
  const post = await getPost(postId);

  if (!post) {
    notFound();
  }

  // Verify the post belongs to a project with matching username and slug
  const project = await getProject(post?.projectId);

  if (!project || project.username !== username || project.slug !== projectSlug) {
    notFound();
  }

  // Get creator profile
  const creatorProfile = await getUserProfile(username);

  return (
    <PostView
      post={post}
      project={{ ...project, username } as ProjectFormData & { username: string }}
      creatorProfile={creatorProfile}
      username={username}
      projectSlug={projectSlug}
    />
  );
}
