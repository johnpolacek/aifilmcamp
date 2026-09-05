import { Film } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { ImagePlaceholder } from "@/components/ui/image-placeholder";
import { getAllProjects } from "@/lib/projects";
import { getThumbnailUrl } from "@/lib/utils";

export async function ProjectsView() {
  const projects = Object.entries(await getAllProjects())
    .filter(([, project]) => project.isPublished && project.username && project.slug)
    .sort(([, a], [, b]) => (b.publishedAt || "").localeCompare(a.publishedAt || ""));
  return (
    <main className="min-h-screen px-4 pt-28 pb-20 lg:px-8">
      <div className="mx-auto max-w-6xl">
        <div className="mb-12 flex flex-wrap items-end justify-between gap-6">
          <div>
            <h1 className="text-4xl font-bold md:text-5xl">Community projects</h1>
            <p className="mt-4 text-lg text-muted-foreground">
              Films and ideas from the AI Film Camp community.
            </p>
          </div>
          <Button asChild>
            <Link href="/dashboard/projects/new">Start a project</Link>
          </Button>
        </div>
        {projects.length ? (
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {projects.map(([id, project]) => (
              <Link
                key={id}
                href={`/${project.username}/${project.slug}`}
                className="group overflow-hidden rounded-xl border bg-card transition-colors hover:border-primary/50"
              >
                <div className="relative aspect-video bg-muted">
                  {project.thumbnail && project.username ? (
                    <Image
                      src={getThumbnailUrl(project.thumbnail, project.username)}
                      alt={project.title}
                      fill
                      sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
                      className="object-cover"
                    />
                  ) : (
                    <ImagePlaceholder text="" className="h-full w-full" />
                  )}
                </div>
                <div className="p-5">
                  <h2 className="text-xl font-semibold group-hover:text-primary">
                    {project.title}
                  </h2>
                  <p className="mt-1 text-sm text-muted-foreground">By {project.username}</p>
                  {project.logline && (
                    <p className="mt-3 line-clamp-2 text-sm leading-relaxed">{project.logline}</p>
                  )}
                </div>
              </Link>
            ))}
          </div>
        ) : (
          <div className="rounded-xl border border-dashed px-6 py-20 text-center">
            <Film className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <h2 className="text-xl font-semibold">A place for your next film</h2>
            <p className="mt-2 text-muted-foreground">
              Public projects will appear here. Start yours with just a title.
            </p>
          </div>
        )}
      </div>
    </main>
  );
}
