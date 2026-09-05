"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { OptimizedImage } from "@/components/ui/optimized-image";
import { Textarea } from "@/components/ui/textarea";
import { saveProjectBasics, uploadProjectThumbnail } from "@/lib/actions/projects";
import type { ProjectBasics } from "@/lib/project-basics";

export function ProjectBasicsForm({
  projectId,
  initialData,
  username,
}: {
  projectId?: string;
  initialData?: ProjectBasics;
  username?: string;
}) {
  const router = useRouter();
  const [data, setData] = useState<ProjectBasics>(
    initialData || { title: "", logline: "", filmLink: "", thumbnail: "", isPublished: false }
  );
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState("");

  return (
    <form
      className="space-y-6"
      onSubmit={async (event) => {
        event.preventDefault();
        setSaving(true);
        setError("");
        try {
          const result = await saveProjectBasics(data, projectId);
          toast.success(projectId ? "Project saved" : "Project created");
          router.push(`/dashboard/projects/${result.projectId}/edit`);
          router.refresh();
        } catch (error) {
          setError(
            error instanceof Error ? error.message : "Could not save the project. Try again."
          );
        } finally {
          setSaving(false);
        }
      }}
    >
      <fieldset disabled={saving || uploading} className="space-y-6 disabled:opacity-70">
        <div className="space-y-2">
          <Label htmlFor="project-title">Title</Label>
          <Input
            id="project-title"
            required
            maxLength={200}
            value={data.title}
            onChange={(event) => setData({ ...data, title: event.target.value })}
            placeholder="Your film’s title"
          />
        </div>
        {projectId ? (
          <>
            <div className="space-y-2">
              <Label htmlFor="project-description">
                Short description <span className="text-muted-foreground">(optional)</span>
              </Label>
              <Textarea
                id="project-description"
                maxLength={500}
                rows={3}
                value={data.logline}
                onChange={(event) => setData({ ...data, logline: event.target.value })}
                placeholder="What’s your film about?"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="project-film">
                Video link <span className="text-muted-foreground">(optional)</span>
              </Label>
              <Input
                id="project-film"
                type="url"
                value={data.filmLink || ""}
                onChange={(event) => setData({ ...data, filmLink: event.target.value })}
                placeholder="https://…"
              />
              <p className="text-sm text-muted-foreground">
                YouTube and Vimeo play on your project page. Other video links open on their
                original site.
              </p>
            </div>
            <div className="space-y-3">
              <Label htmlFor="project-cover">
                Cover image <span className="text-muted-foreground">(optional)</span>
              </Label>
              {data.thumbnail && (
                <div className="relative aspect-video overflow-hidden rounded-xl border">
                  <OptimizedImage
                    key={data.thumbnail}
                    type="thumbnail"
                    filename={data.thumbnail}
                    username={username}
                    alt={`${data.title} cover`}
                    fill
                    objectFit="cover"
                    sizes="(max-width: 768px) 100vw, 640px"
                  />
                </div>
              )}
              <Input
                id="project-cover"
                type="file"
                accept="image/*"
                onChange={async (event) => {
                  const file = event.target.files?.[0];
                  if (!file) return;
                  setUploading(true);
                  setError("");
                  try {
                    const form = new FormData();
                    form.set("image", file);
                    const result = await uploadProjectThumbnail(form);
                    setData((current) => ({ ...current, thumbnail: result.thumbnailFilename }));
                  } catch (error) {
                    setError(
                      error instanceof Error ? error.message : "Could not upload the cover."
                    );
                  } finally {
                    setUploading(false);
                    event.target.value = "";
                  }
                }}
              />
              <p className="text-sm text-muted-foreground">
                {uploading ? "Uploading cover…" : "Choose an image up to 10 MB."}
              </p>
              {data.thumbnail && (
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => setData({ ...data, thumbnail: "" })}
                >
                  Remove cover
                </Button>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="project-visibility">Visibility</Label>
              <select
                id="project-visibility"
                className="h-10 w-full rounded-md border border-input bg-background px-3 text-sm"
                value={data.isPublished ? "public" : "private"}
                onChange={(event) =>
                  setData({ ...data, isPublished: event.target.value === "public" })
                }
              >
                <option value="private">Private — only you</option>
                <option value="public">Public — anyone can view</option>
              </select>
              <p className="text-sm text-muted-foreground">
                Your public page shows your film and these details. Development work stays in your
                workspace.
              </p>
            </div>
          </>
        ) : (
          <p className="text-muted-foreground">
            Start with a title. Add a cover, description, and film whenever you’re ready. Your
            project starts private.
          </p>
        )}
      </fieldset>
      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}
      <Button type="submit" disabled={saving || uploading || !data.title.trim()}>
        {saving ? "Saving…" : projectId ? "Save changes" : "Create project"}
      </Button>
    </form>
  );
}
