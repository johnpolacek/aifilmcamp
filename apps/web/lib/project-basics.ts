import type { ProjectFormData } from "@/components/project-form";

export type ProjectBasics = Pick<
  ProjectFormData,
  "title" | "logline" | "thumbnail" | "filmLink" | "isPublished"
>;

export function getFilmUrl(value?: string): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    return ["https:", "http:"].includes(url.protocol) && !url.username && !url.password
      ? url.href
      : null;
  } catch {
    return null;
  }
}

export function getFilmEmbedUrl(value?: string): string | null {
  const safeUrl = getFilmUrl(value);
  if (!safeUrl) return null;
  const url = new URL(safeUrl);
  const host = url.hostname.replace(/^www\./, "");
  if (["youtube.com", "m.youtube.com", "youtu.be"].includes(host)) {
    const id =
      host === "youtu.be"
        ? url.pathname.slice(1)
        : url.searchParams.get("v") || url.pathname.match(/^\/(?:embed|shorts)\/([^/]+)$/)?.[1];
    return id && /^[\w-]{11}$/.test(id) ? `https://www.youtube-nocookie.com/embed/${id}` : null;
  }
  if (host === "vimeo.com" || host === "player.vimeo.com") {
    const match = url.pathname.match(/^\/(?:video\/)?(\d+)(?:\/([a-zA-Z0-9]+))?\/?$/);
    if (match) {
      const hash = match[2] || url.searchParams.get("h");
      return `https://player.vimeo.com/video/${match[1]}${hash ? `?h=${encodeURIComponent(hash)}` : ""}`;
    }
  }
  return null;
}

// Merge only editable basics into the latest stored project, preserving working material.
export function applyProjectBasics(
  existing: ProjectFormData,
  input: ProjectBasics
): ProjectFormData {
  const title = typeof input.title === "string" ? input.title.trim() : "";
  if (!title || title.length > 200) throw new Error("Enter a title of up to 200 characters.");
  const logline = typeof input.logline === "string" ? input.logline.trim() : "";
  if (logline.length > 500) throw new Error("Keep the description to 500 characters or less.");
  const filmLink = typeof input.filmLink === "string" ? input.filmLink.trim() : "";
  if (filmLink && !getFilmUrl(filmLink)) throw new Error("Enter a valid HTTP or HTTPS video link.");
  const isPublished = input.isPublished === true;
  return {
    ...existing,
    title,
    logline,
    filmLink,
    thumbnail: typeof input.thumbnail === "string" ? input.thumbnail : "",
    isPublished,
    publishedAt: isPublished
      ? existing.publishedAt || new Date().toISOString()
      : existing.publishedAt,
  };
}

export type ProjectSummary = ProjectBasics &
  Pick<ProjectFormData, "username" | "slug"> & { id: string };
