import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ProjectView } from "@/components/views/project-view";
import { getUserProfile } from "@/lib/profiles";
import { getVisibleProject } from "@/lib/project-access";
import { getImageUrl } from "@/lib/utils";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ username: string; projectSlug: string }>;
}): Promise<Metadata> {
  const { username, projectSlug } = await params;
  const projectData = await getVisibleProject(username, projectSlug);

  if (!projectData) {
    return {
      title: "Project Not Found - AI Film Camp",
    };
  }

  const { project } = projectData;
  const thumbnailUrl = project.thumbnail
    ? getImageUrl({ type: "thumbnail", filename: project.thumbnail, username })
    : undefined;

  return {
    robots: project.isPublished ? undefined : { index: false, follow: false },
    title: `${project.title} - ${username} - AI Film Camp`,
    description: project.logline || `View ${project.title} by ${username} on AI Film Camp`,
    openGraph: {
      title: `${project.title} - ${username} - AI Film Camp`,
      description: project.logline || `View ${project.title} by ${username} on AI Film Camp`,
      ...(thumbnailUrl && {
        images: [
          {
            url: thumbnailUrl,
            width: 1200,
            height: 630,
            alt: project.title,
          },
        ],
      }),
    },
    twitter: {
      card: "summary_large_image",
      title: `${project.title} - ${username} - AI Film Camp`,
      description: project.logline || `View ${project.title} by ${username} on AI Film Camp`,
      ...(thumbnailUrl && {
        images: [thumbnailUrl],
      }),
    },
  };
}

export default async function ProjectPage({
  params,
}: {
  params: Promise<{ username: string; projectSlug: string }>;
}) {
  const { username, projectSlug } = await params;

  // Get project data
  const projectData = await getVisibleProject(username, projectSlug);

  if (!projectData) {
    notFound();
  }

  // TypeScript assertion: projectData is non-null after the check above
  const { project, id } = projectData as NonNullable<typeof projectData>;

  // Get creator profile
  const creatorProfile = await getUserProfile(username);

  return (
    <ProjectView
      projectId={id}
      project={{ ...project, slug: projectSlug }}
      username={username}
      creatorProfile={creatorProfile}
    />
  );
}
