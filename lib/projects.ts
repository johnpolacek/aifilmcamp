import type { ProjectFormData } from "@/components/project-form";
import {
  createDefaultPhaseStatus,
  createDefaultPhaseVisibility,
  normalizeFilmLengthOption,
} from "@/lib/types/development";
import { getObjectFromS3, listObjectsInS3, putObjectToS3 } from "./s3";

const PROJECTS_PREFIX = "projects/";

function ensureProjectFields(project: ProjectFormData): ProjectFormData {
  const normalizedFilmLength =
    normalizeFilmLengthOption(project.filmLength) || normalizeFilmLengthOption(project.duration);

  return {
    ...project,
    duration: normalizedFilmLength || project.duration || project.filmLength || "",
    filmLength:
      normalizedFilmLength ||
      project.filmLength ||
      (project.duration as ProjectFormData["filmLength"]),
    development: project.development || {},
    phaseVisibility: {
      ...createDefaultPhaseVisibility(),
      ...project.phaseVisibility,
    },
    phaseStatus: {
      ...createDefaultPhaseStatus(),
      ...project.phaseStatus,
    },
  };
}

/**
 * Get a project by ID
 */
export async function getProject(projectId: string): Promise<ProjectFormData | null> {
  try {
    const key = `${PROJECTS_PREFIX}${projectId}.json`;
    const data = await getObjectFromS3(key);

    if (!data) {
      return null;
    }

    return ensureProjectFields(JSON.parse(data) as ProjectFormData);
  } catch (error) {
    console.error("Error getting project:", error);
    return null;
  }
}

/**
 * Save a project (create or update)
 */
export async function saveProject(projectId: string, projectData: ProjectFormData): Promise<void> {
  try {
    const key = `${PROJECTS_PREFIX}${projectId}.json`;
    const body = JSON.stringify(ensureProjectFields(projectData), null, 2);

    await putObjectToS3(key, body);
  } catch (error) {
    console.error("Error saving project:", error);
    throw error;
  }
}

/**
 * List all project IDs
 */
export async function listProjectIds(): Promise<string[]> {
  try {
    const keys = await listObjectsInS3(PROJECTS_PREFIX);

    // Extract project IDs from keys (remove prefix and .json extension)
    return keys
      .filter((key) => key.endsWith(".json"))
      .map((key) => {
        const filename = key.replace(PROJECTS_PREFIX, "");
        return filename.replace(".json", "");
      });
  } catch (error) {
    console.error("Error listing projects:", error);
    return [];
  }
}

/**
 * Get all projects
 */
export async function getAllProjects(): Promise<Record<string, ProjectFormData>> {
  try {
    const projectIds = await listProjectIds();
    const projects: Record<string, ProjectFormData> = {};

    await Promise.all(
      projectIds.map(async (id) => {
        const project = await getProject(id);
        if (project) {
          projects[id] = project;
        }
      })
    );

    return projects;
  } catch (error) {
    console.error("Error getting all projects:", error);
    return {};
  }
}

/**
 * Get projects by username
 */
export async function getProjectsByUsername(
  username: string
): Promise<Array<ProjectFormData & { id: string }>> {
  try {
    const allProjects = await getAllProjects();

    return Object.entries(allProjects)
      .filter(([_, project]) => project.username === username)
      .map(([id, project]) => ({ ...project, id }));
  } catch (error) {
    console.error("Error getting projects by username:", error);
    return [];
  }
}

/**
 * Get a project by username and slug
 */
export async function getProjectByUsernameAndSlug(
  username: string,
  slug: string
): Promise<{ project: ProjectFormData; id: string } | null> {
  try {
    const projects = await getProjectsByUsername(username);
    const project = projects.find((p) => p.slug === slug);

    if (!project) {
      return null;
    }

    return { project, id: project.id };
  } catch (error) {
    console.error("Error getting project by username and slug:", error);
    return null;
  }
}

/**
 * Delete a project
 */
export async function deleteProject(projectId: string): Promise<void> {
  try {
    const { DeleteObjectCommand } = await import("@aws-sdk/client-s3");
    const { s3Client, BUCKET_NAME } = await import("./s3");

    const key = `${PROJECTS_PREFIX}${projectId}.json`;
    const command = new DeleteObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    await s3Client.send(command);
  } catch (error) {
    console.error("Error deleting project:", error);
    throw error;
  }
}
