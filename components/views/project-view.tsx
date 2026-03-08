import { Calendar, Clock, Eye, FileText, Layers3, Sparkles, User } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import type React from "react";
import { PostsList } from "@/components/posts-list";
import type { ProjectFormData } from "@/components/project-form";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ImagePlaceholder } from "@/components/ui/image-placeholder";
import { OptimizedImage } from "@/components/ui/optimized-image";
import { ProjectNavigation } from "@/components/views/project-navigation";
import { getPromptShotCount, getPublishedPhases } from "@/lib/development";
import type { Post } from "@/lib/posts";
import type { UserProfile } from "@/lib/profiles";
import { getThumbnailUrl } from "@/lib/utils";

interface ProjectViewProps {
  projectId: string;
  project: ProjectFormData & { slug: string };
  username: string;
  projectSlug: string;
  creatorProfile: UserProfile | null;
  posts: Post[];
}

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <Card className="border-border bg-card/70">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  );
}

export function ProjectView({
  projectId,
  project,
  username,
  projectSlug,
  creatorProfile,
  posts,
}: ProjectViewProps) {
  const publishedPhases = new Set(getPublishedPhases(project));
  const thumbnailUrl = project.thumbnail ? getThumbnailUrl(project.thumbnail, username) : "";
  const promptShotCount = getPromptShotCount(project.scenes);
  const assetCount =
    (project.characters?.filter((character) => character.mainImage || character.images?.length)
      .length || 0) +
    (project.setting?.locations?.filter((location) => location.image || location.images?.length)
      .length || 0);

  return (
    <div className="min-h-screen bg-background pb-16">
      <div className="relative h-[360px] w-full overflow-hidden xl:h-[520px]">
        <ProjectNavigation projectId={projectId} ownerUsername={username} />
        {thumbnailUrl ? (
          <Image src={thumbnailUrl} alt={project.title} fill className="object-cover" priority />
        ) : (
          <ImagePlaceholder className="h-full w-full" />
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-background via-background/60 to-transparent" />
        <div className="absolute inset-x-0 bottom-0">
          <div className="container mx-auto max-w-6xl px-4 pb-10 lg:px-8">
            <div className="mb-4 flex flex-wrap items-center gap-2">
              {project.isPublished && (
                <span className="rounded-full bg-green-500/15 px-3 py-1 text-sm font-medium text-green-500">
                  Published Project
                </span>
              )}
              {project.genre && (
                <span className="rounded-full bg-background/70 px-3 py-1 text-sm">
                  {project.genre}
                </span>
              )}
              {(project.filmLength || project.duration) && (
                <span className="rounded-full bg-background/70 px-3 py-1 text-sm">
                  {project.filmLength || project.duration}
                </span>
              )}
            </div>
            <h1 className="max-w-4xl text-4xl font-bold text-balance md:text-5xl">
              {project.title}
            </h1>
            {project.logline && (
              <p className="mt-4 max-w-3xl text-lg text-foreground/85">{project.logline}</p>
            )}
            <div className="mt-5 flex flex-wrap items-center gap-4 text-sm text-muted-foreground">
              <div className="flex items-center gap-1">
                <User className="h-4 w-4" />
                <span>{creatorProfile?.name || username}</span>
              </div>
              {project.publishedAt && (
                <div className="flex items-center gap-1">
                  <Calendar className="h-4 w-4" />
                  <span>{new Date(project.publishedAt).toLocaleDateString()}</span>
                </div>
              )}
              {(project.filmLength || project.duration) && (
                <div className="flex items-center gap-1">
                  <Clock className="h-4 w-4" />
                  <span>{project.filmLength || project.duration}</span>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      <div className="container mx-auto mt-8 max-w-6xl space-y-8 px-4 lg:px-8">
        <Card className="border-border bg-muted/30">
          <CardContent className="flex flex-wrap items-center gap-3 p-4 text-sm text-muted-foreground">
            <span>{project.characters?.length || 0} characters</span>
            <span>{project.development?.scriptBreakdown?.length || project.scenes?.length || 0} scenes</span>
            <span>{assetCount} asset groups</span>
            <span>{promptShotCount} prompt shots</span>
            <span>{publishedPhases.size} published phases</span>
          </CardContent>
        </Card>

        {publishedPhases.has("concept") && (
          <Section title="Concept">
            <p className="text-sm leading-relaxed text-muted-foreground">
              {project.development?.conceptStatement || project.development?.conceptSeed || "No concept published yet."}
            </p>
          </Section>
        )}

        {publishedPhases.has("title-logline") && (
          <Section title="Title and Logline">
            <div className="space-y-2">
              <p className="text-lg font-semibold">{project.title}</p>
              {project.logline && <p className="text-sm text-muted-foreground">{project.logline}</p>}
            </div>
          </Section>
        )}

        {publishedPhases.has("film-length") && (
          <Section title="Target Runtime">
            <p className="text-sm text-muted-foreground">{project.filmLength || project.duration}</p>
          </Section>
        )}

        {publishedPhases.has("characters") && (project.characters?.length || 0) > 0 && (
          <Section title="Characters">
            <div className="grid gap-4 md:grid-cols-2">
              {project.characters?.map((character, index) => (
                <div key={`${character.name}-${index}`} className="rounded-lg border border-border bg-background p-4">
                  {character.mainImage && project.username && (
                    <div className="relative mb-4 aspect-video overflow-hidden rounded-lg border border-border">
                      <OptimizedImage
                        type="character"
                        filename={character.mainImage}
                        username={project.username}
                        alt={character.name}
                        fill
                        objectFit="cover"
                      />
                    </div>
                  )}
                  <p className="font-semibold">{character.name}</p>
                  {character.role && <p className="text-sm text-primary">{character.role}</p>}
                  {character.appearance && (
                    <p className="mt-2 text-sm text-muted-foreground">{character.appearance}</p>
                  )}
                  {character.motivation && (
                    <p className="mt-2 text-sm text-muted-foreground">
                      <span className="font-medium text-foreground">Motivation:</span> {character.motivation}
                    </p>
                  )}
                  {character.arc && (
                    <p className="mt-2 text-sm text-muted-foreground">
                      <span className="font-medium text-foreground">Arc:</span> {character.arc}
                    </p>
                  )}
                </div>
              ))}
            </div>
          </Section>
        )}

        {publishedPhases.has("outline") && (project.development?.outline?.length || 0) > 0 && (
          <Section title="Plot Outline">
            <div className="space-y-3">
              {project.development?.outline?.map((beat) => (
                <div key={beat.id} className="rounded-lg border border-border bg-background p-4">
                  <p className="font-medium">
                    Beat {beat.order}: {beat.title}
                  </p>
                  <p className="mt-2 text-sm text-muted-foreground">{beat.summary}</p>
                </div>
              ))}
            </div>
          </Section>
        )}

        {publishedPhases.has("script-breakdown") &&
          (project.development?.scriptBreakdown?.length || 0) > 0 && (
            <Section title="Script Breakdown">
              <div className="space-y-3">
                {project.development?.scriptBreakdown?.map((scene) => (
                  <div key={scene.id} className="rounded-lg border border-border bg-background p-4">
                    <p className="font-medium">
                      Scene {scene.order}: {scene.title}
                    </p>
                    <p className="mt-2 text-sm text-muted-foreground">{scene.summary}</p>
                    <div className="mt-3 flex flex-wrap gap-3 text-xs text-muted-foreground">
                      {scene.locationName && <span>{scene.locationName}</span>}
                      {scene.characters.length > 0 && <span>{scene.characters.join(", ")}</span>}
                    </div>
                  </div>
                ))}
              </div>
            </Section>
          )}

        {publishedPhases.has("screenplay") && project.screenplayText && (
          <Section title="Screenplay">
            <div className="space-y-4">
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <FileText className="h-4 w-4" />
                {project.screenplayText.trim().split(/\s+/).length} words
              </div>
              <pre className="max-h-[500px] overflow-auto whitespace-pre-wrap rounded-lg border border-border bg-background p-4 text-sm leading-relaxed">
                {project.screenplayText}
              </pre>
              <div>
                <Link href={`/${username}/${projectSlug}/screenplay`}>
                  <Button variant="outline">Open Dedicated Screenplay View</Button>
                </Link>
              </div>
            </div>
          </Section>
        )}

        {publishedPhases.has("assets") && (
          <Section title="Reference Assets">
            <div className="grid gap-6 md:grid-cols-2">
              <div className="space-y-3">
                <div className="flex items-center gap-2">
                  <Sparkles className="h-4 w-4 text-primary" />
                  <p className="font-medium">Character Assets</p>
                </div>
                {(project.characters || [])
                  .filter((character) => character.mainImage)
                  .map((character) => (
                    <div key={character.name} className="rounded-lg border border-border bg-background p-3">
                      <p className="mb-2 text-sm font-medium">{character.name}</p>
                      {project.username && character.mainImage && (
                        <div className="relative aspect-video overflow-hidden rounded-lg">
                          <OptimizedImage
                            type="character"
                            filename={character.mainImage}
                            username={project.username}
                            alt={character.name}
                            fill
                            objectFit="cover"
                          />
                        </div>
                      )}
                    </div>
                  ))}
              </div>
              <div className="space-y-3">
                <div className="flex items-center gap-2">
                  <Layers3 className="h-4 w-4 text-primary" />
                  <p className="font-medium">Location Assets</p>
                </div>
                {(project.setting?.locations || [])
                  .filter((location) => location.image)
                  .map((location) => (
                    <div key={location.name} className="rounded-lg border border-border bg-background p-3">
                      <p className="mb-2 text-sm font-medium">{location.name}</p>
                      {project.username && location.image && (
                        <div className="relative aspect-video overflow-hidden rounded-lg">
                          <OptimizedImage
                            type="location"
                            filename={location.image}
                            username={project.username}
                            alt={location.name}
                            fill
                            objectFit="cover"
                          />
                        </div>
                      )}
                    </div>
                  ))}
              </div>
            </div>
          </Section>
        )}

        {publishedPhases.has("shot-prompts") && (project.scenes?.length || 0) > 0 && (
          <Section title="Shot Prompts">
            <div className="space-y-4">
              {project.scenes?.map((scene) => (
                <div key={scene.id} className="rounded-lg border border-border bg-background p-4">
                  <p className="font-semibold">
                    Scene {scene.sceneNumber}: {scene.title}
                  </p>
                  {scene.summary && (
                    <p className="mt-2 text-sm text-muted-foreground">{scene.summary}</p>
                  )}
                  <div className="mt-4 space-y-3">
                    {(scene.promptShots || []).map((shot) => (
                      <div key={shot.id} className="rounded-lg border border-border bg-muted/30 p-3">
                        <p className="font-medium">
                          Shot {shot.shotNumber}: {shot.title}
                        </p>
                        <div className="mt-2 grid gap-2 text-xs text-muted-foreground md:grid-cols-3">
                          <span>Framing: {shot.framing || "Not set"}</span>
                          <span>Camera: {shot.cameraMovement || "Not set"}</span>
                          <span>Duration: {shot.durationEstimateSeconds || 0}s</span>
                        </div>
                        {shot.action && <p className="mt-2 text-sm text-muted-foreground">{shot.action}</p>}
                        <pre className="mt-3 whitespace-pre-wrap rounded-md border border-border bg-background p-3 text-xs leading-relaxed">
                          {shot.prompt}
                        </pre>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </Section>
        )}

        {publishedPhases.size === 0 && (
          <Section title="Development Package">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Eye className="h-4 w-4" />
              This project has not published any public phases yet.
            </div>
          </Section>
        )}

        {posts.length > 0 && (
          <Section title="Project Posts">
            <PostsList
              projectId={projectId}
              initialPosts={posts}
              canEdit={false}
              username={username}
              projectSlug={projectSlug}
              showAddButton={false}
            />
          </Section>
        )}
      </div>
    </div>
  );
}
