/**
 * Project Export Service
 * Creates downloadable archives of project data
 */

import type { ProjectFormData } from "@/components/project-form";
import type { Scene } from "./scenes";

export interface ExportData {
  project: ProjectFormData;
  scenes?: Scene[];
  exportedAt: string;
  version: string;
}

/**
 * Create a JSON export of the project
 */
export function createProjectExportJson(project: ProjectFormData): ExportData {
  return {
    project: {
      ...project,
      // Remove internal fields that shouldn't be exported
    },
    scenes: project.scenes,
    exportedAt: new Date().toISOString(),
    version: "1.0.0",
  };
}

/**
 * Generate a README for the exported project
 */
export function generateProjectReadme(project: ProjectFormData): string {
  const readme = `# ${project.title}

${project.logline ? `> ${project.logline}` : ""}

## Development Package

- **Genre**: ${project.genre || "Not specified"}
- **Film Length**: ${project.filmLength || project.duration || "Not specified"}
${project.publishedAt ? `- **Published**: ${new Date(project.publishedAt).toLocaleDateString()}` : ""}

${project.development?.conceptStatement ? `## Concept

${project.development.conceptStatement}
` : ""}

${project.development?.outline && project.development.outline.length > 0 ? `## Plot Outline

${project.development.outline
  .map((beat) => `### Beat ${beat.order}: ${beat.title}
${beat.summary}`)
  .join("\n\n")}
` : ""}

${project.development?.scriptBreakdown && project.development.scriptBreakdown.length > 0 ? `## Script Breakdown

${project.development.scriptBreakdown
  .map((scene) => `### Scene ${scene.order}: ${scene.title}
${scene.summary}
Location: ${scene.locationName || "Not specified"}
Purpose: ${scene.dramaticPurpose}`)
  .join("\n\n")}
` : ""}

${project.characters && project.characters.length > 0 ? `## Characters

${project.characters.map((c) => `### ${c.name}
${c.role ? `Role: ${c.role}\n` : ""}${c.appearance || ""}
`).join("\n")}` : ""}

${project.scenes && project.scenes.length > 0 ? `## Scenes

${project.scenes
  .sort((a, b) => a.sceneNumber - b.sceneNumber)
  .map((s) => `### Scene ${s.sceneNumber}: ${s.title}

${s.summary || "No summary"}

${s.generatedImages && s.generatedImages.length > 0 ? `- ${s.generatedImages.length} generated image(s)` : ""}
${s.promptShots && s.promptShots.length > 0 ? `- ${s.promptShots.length} prompt shot(s)` : ""}
`).join("\n")}` : ""}

## Tools Used

${project.tools && project.tools.length > 0 
  ? project.tools.map((t) => `- ${t.name} (${t.category})`).join("\n")
  : "No tools specified"}

---

*Exported from AIFilmCamp*
`;

  return readme;
}

/**
 * Get list of assets to download for export
 */
export function getExportAssets(project: ProjectFormData): Array<{
  type: "image" | "video" | "thumbnail" | "character" | "location";
  url: string;
  filename: string;
}> {
  const assets: Array<{
    type: "image" | "video" | "thumbnail" | "character" | "location";
    url: string;
    filename: string;
  }> = [];

  // Thumbnail
  if (project.thumbnail) {
    assets.push({
      type: "thumbnail",
      url: project.thumbnail,
      filename: `thumbnail.jpg`,
    });
  }

  // Character images
  project.characters?.forEach((character, index) => {
    if (character.mainImage) {
      assets.push({
        type: "character",
        url: character.mainImage,
        filename: `characters/${index + 1}-${character.name.replace(/[^a-zA-Z0-9]/g, "_")}-main.jpg`,
      });
    }
    // Additional character images
    character.images?.forEach((image, imageIndex) => {
      if (image) {
        assets.push({
          type: "character",
          url: image,
          filename: `characters/${index + 1}-${character.name.replace(/[^a-zA-Z0-9]/g, "_")}-${imageIndex + 1}.jpg`,
        });
      }
    });
  });

  // Location images
  project.setting?.locations?.forEach((location, index) => {
    if (location.image) {
      assets.push({
        type: "location",
        url: location.image,
        filename: `locations/${index + 1}-${location.name.replace(/[^a-zA-Z0-9]/g, "_")}.jpg`,
      });
    }
  });

  // Scene assets
  project.scenes?.forEach((scene) => {
    // Generated images
    scene.generatedImages?.forEach((image, imgIndex) => {
      assets.push({
        type: "image",
        url: image.imageUrl,
        filename: `scenes/${scene.sceneNumber}/images/${imgIndex + 1}.png`,
      });
    });

    // Generated videos
    scene.generatedVideos?.forEach((video, vidIndex) => {
      if (video.status === "completed" && video.videoUrl) {
        assets.push({
          type: "video",
          url: video.videoUrl,
          filename: `scenes/${scene.sceneNumber}/videos/${vidIndex + 1}.mp4`,
        });
      }
    });
  });

  return assets;
}
