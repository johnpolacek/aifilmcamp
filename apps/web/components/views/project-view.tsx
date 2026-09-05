import Image from "next/image";
import type { ProjectFormData } from "@/components/project-form";
import { Button } from "@/components/ui/button";
import { ImagePlaceholder } from "@/components/ui/image-placeholder";
import { ProjectNavigation } from "@/components/views/project-navigation";
import type { UserProfile } from "@/lib/profiles";
import { getFilmEmbedUrl, getFilmUrl } from "@/lib/project-basics";
import { getThumbnailUrl } from "@/lib/utils";

export function ProjectView({
  projectId,
  project,
  username,
  creatorProfile,
}: {
  projectId: string;
  project: ProjectFormData;
  username: string;
  creatorProfile: UserProfile | null;
}) {
  const cover = project.thumbnail ? getThumbnailUrl(project.thumbnail, username) : null;
  const filmUrl = getFilmUrl(project.filmLink);
  const embed = getFilmEmbedUrl(project.filmLink);
  return (
    <main className="relative min-h-screen bg-background px-4 pt-36 pb-20 lg:px-8">
      <ProjectNavigation projectId={projectId} ownerUsername={username} />
      <div className="mx-auto max-w-5xl">
        {!project.isPublished && (
          <p className="mb-4 text-sm text-muted-foreground">
            Private preview · Only you can view this page
          </p>
        )}
        <div className="relative aspect-video overflow-hidden rounded-2xl border border-border bg-muted">
          {embed ? (
            <iframe
              src={embed}
              title={project.title}
              className="h-full w-full"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen"
              allowFullScreen
            />
          ) : cover ? (
            <Image
              src={cover}
              alt={project.title}
              fill
              priority
              sizes="(max-width: 1024px) 100vw, 1024px"
              className="object-cover"
            />
          ) : (
            <ImagePlaceholder text="" className="h-full w-full" />
          )}
        </div>
        {filmUrl && (
          <Button asChild className="mt-6" variant={embed ? "outline" : "default"}>
            <a href={filmUrl} target="_blank" rel="noopener noreferrer">
              {embed ? "Open video" : "Watch film"} ↗
            </a>
          </Button>
        )}
        <h1 className="mt-8 text-4xl font-bold text-balance md:text-5xl">{project.title}</h1>
        <p className="mt-3 text-muted-foreground">By {creatorProfile?.name || username}</p>
        {project.logline && (
          <p className="mt-6 max-w-3xl text-lg leading-relaxed">{project.logline}</p>
        )}
      </div>
    </main>
  );
}
