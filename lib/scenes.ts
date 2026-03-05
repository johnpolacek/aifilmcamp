import { getProject, saveProject } from "./projects";
import { getObjectFromS3, listObjectsInS3, putObjectToS3 } from "./s3";

// Re-export all types from client-safe module for server-side usage
export type {
  AudioSourceType,
  AudioTrack,
  CompositeStatus,
  CompositeVideo,
  GeneratedImage,
  GeneratedVideo,
  GenerationMode,
  PromptShot,
  Scene,
  Shot,
  ShotVideo,
  Transition,
  TransitionType,
  VideoSourceType,
} from "./scenes-client";

// Re-export client-safe helper functions
export {
  calculateTimelinePositions,
  createNewAudioTrack,
  createNewPromptShot,
  createNewShot,
  getDefaultTransition,
  getSceneDuration,
} from "./scenes-client";

// Import types for use in this file
import type {
  AudioTrack,
  GeneratedImage,
  GeneratedVideo,
  GenerationMode,
  Scene,
  Shot,
  ShotVideo,
  VideoSourceType,
} from "./scenes-client";

const SCENES_PREFIX = "scenes/";

/**
 * Get the S3 key for a scene
 */
function getSceneKey(projectId: string, sceneId: string): string {
  return `${SCENES_PREFIX}${projectId}/${sceneId}.json`;
}

/**
 * Ensure a scene has all required fields (for backward compatibility)
 */
function ensureSceneFields(scene: Scene): Scene {
  return {
    ...scene,
    promptShots: scene.promptShots || [],
    shots: scene.shots || [],
    audioTracks: scene.audioTracks || [],
    transitionOut: scene.transitionOut || { type: "none", durationMs: 0 },
    generatedImages: scene.generatedImages || [],
    generatedVideos: scene.generatedVideos || [],
    removedShots: scene.removedShots || [],
  };
}

/**
 * Get a scene by ID
 * First checks the project's scenes array, then falls back to separate S3 storage
 * Ensures backward compatibility by initializing missing fields
 */
export async function getScene(projectId: string, sceneId: string): Promise<Scene | null> {
  try {
    // First, try to get the scene from the project's scenes array
    const project = await getProject(projectId);
    if (project?.scenes) {
      const sceneFromProject = project.scenes.find((s) => s.id === sceneId);
      if (sceneFromProject) {
        return ensureSceneFields(sceneFromProject);
      }
    }

    // Fallback: try to get from separate S3 storage (for new scenes)
    const key = getSceneKey(projectId, sceneId);
    const data = await getObjectFromS3(key);

    if (!data) {
      return null;
    }

    const scene = JSON.parse(data) as Scene;
    return ensureSceneFields(scene);
  } catch (error) {
    console.error("Error getting scene:", JSON.stringify({ projectId, sceneId, error }, null, 2));
    return null;
  }
}

/**
 * Save a scene (create or update)
 * If the scene exists in the project's scenes array, update it there
 * Otherwise, save to separate S3 storage
 */
export async function saveScene(projectId: string, sceneData: Scene): Promise<void> {
  try {
    // First, check if this scene exists in the project's scenes array
    const project = await getProject(projectId);

    if (project) {
      const scenes = project.scenes || [];
      const existingIndex = scenes.findIndex((s) => s.id === sceneData.id);

      if (existingIndex !== -1) {
        // Update existing scene in project
        scenes[existingIndex] = sceneData;
        await saveProject(projectId, { ...project, scenes });
        return;
      } else {
        // Add new scene to project's scenes array
        scenes.push(sceneData);
        // Sort by scene number
        scenes.sort((a, b) => a.sceneNumber - b.sceneNumber);
        await saveProject(projectId, { ...project, scenes });
        return;
      }
    }

    // Fallback: save to separate S3 storage
    const key = getSceneKey(projectId, sceneData.id);
    const body = JSON.stringify(sceneData, null, 2);
    await putObjectToS3(key, body);
  } catch (error) {
    console.error(
      "Error saving scene:",
      JSON.stringify({ projectId, sceneId: sceneData.id, error }, null, 2)
    );
    throw error;
  }
}

/**
 * List all scenes for a project
 */
export async function listScenesForProject(projectId: string): Promise<Scene[]> {
  try {
    const prefix = `${SCENES_PREFIX}${projectId}/`;
    const keys = await listObjectsInS3(prefix);

    const scenes: Scene[] = [];

    await Promise.all(
      keys
        .filter((key) => key.endsWith(".json"))
        .map(async (key) => {
          try {
            const data = await getObjectFromS3(key);
            if (data) {
              const scene = JSON.parse(data) as Scene;
              scenes.push(scene);
            }
          } catch (error) {
            console.error("Error reading scene:", JSON.stringify({ key, error }, null, 2));
          }
        })
    );

    // Sort by scene number
    return scenes.sort((a, b) => a.sceneNumber - b.sceneNumber);
  } catch (error) {
    console.error("Error listing scenes:", JSON.stringify({ projectId, error }, null, 2));
    return [];
  }
}

/**
 * Delete a scene
 * If the scene exists in the project's scenes array, remove it from there
 * Otherwise, delete from separate S3 storage
 */
export async function deleteScene(projectId: string, sceneId: string): Promise<void> {
  try {
    // First, check if this scene exists in the project's scenes array
    const project = await getProject(projectId);

    if (project?.scenes) {
      const existingIndex = project.scenes.findIndex((s) => s.id === sceneId);

      if (existingIndex !== -1) {
        // Remove scene from project and renumber remaining scenes
        const updatedScenes = project.scenes.filter((s) => s.id !== sceneId);
        updatedScenes.forEach((scene, index) => {
          scene.sceneNumber = index + 1;
        });
        await saveProject(projectId, { ...project, scenes: updatedScenes });
        return;
      }
    }

    // Fallback: delete from separate S3 storage
    const { DeleteObjectCommand } = await import("@aws-sdk/client-s3");
    const { s3Client, BUCKET_NAME } = await import("./s3");

    const key = getSceneKey(projectId, sceneId);
    const command = new DeleteObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    await s3Client.send(command);
  } catch (error) {
    console.error("Error deleting scene:", JSON.stringify({ projectId, sceneId, error }, null, 2));
    throw error;
  }
}

/**
 * Create a new scene with default values
 */
export function createNewScene(projectId: string, sceneNumber: number): Scene {
  const now = new Date().toISOString();
  return {
    id: `scene-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
    projectId,
    sceneNumber,
    title: `Scene ${sceneNumber}`,
    screenplay: "",
    summary: "",
    dramaticPurpose: "",
    emotionalBeat: "",
    visualIntent: "",
    characters: [],
    promptShots: [],
    shots: [],
    audioTracks: [],
    transitionOut: { type: "none", durationMs: 0 },
    // Legacy fields for migration compatibility
    generatedImages: [],
    generatedVideos: [],
    createdAt: now,
    updatedAt: now,
  };
}

// ============================================================================
// SHOT HELPERS
// ============================================================================

/**
 * Add a shot to a scene
 */
export async function addShotToScene(
  projectId: string,
  sceneId: string,
  shot: Shot
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene) {
      return null;
    }

    // Initialize shots array if needed
    if (!scene.shots) {
      scene.shots = [];
    }

    scene.shots.push(shot);
    // Sort by order
    scene.shots.sort((a, b) => a.order - b.order);
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error adding shot to scene:",
      JSON.stringify({ projectId, sceneId, error }, null, 2)
    );
    throw error;
  }
}

/**
 * Update a shot in a scene
 */
export async function updateShot(
  projectId: string,
  sceneId: string,
  shotId: string,
  updates: Partial<Shot>
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene || !scene.shots) {
      return null;
    }

    const shotIndex = scene.shots.findIndex((s) => s.id === shotId);
    if (shotIndex === -1) {
      return null;
    }

    scene.shots[shotIndex] = {
      ...scene.shots[shotIndex],
      ...updates,
      updatedAt: new Date().toISOString(),
    };
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error updating shot:",
      JSON.stringify({ projectId, sceneId, shotId, error }, null, 2)
    );
    throw error;
  }
}

/**
 * Delete a shot from a scene
 */
export async function deleteShot(
  projectId: string,
  sceneId: string,
  shotId: string
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene || !scene.shots) {
      return null;
    }

    scene.shots = scene.shots.filter((s) => s.id !== shotId);
    // Reorder remaining shots
    scene.shots.forEach((shot, index) => {
      shot.order = index;
    });
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error deleting shot:",
      JSON.stringify({ projectId, sceneId, shotId, error }, null, 2)
    );
    throw error;
  }
}

/**
 * Reorder shots in a scene
 */
export async function reorderShots(
  projectId: string,
  sceneId: string,
  shotIds: string[]
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene || !scene.shots) {
      return null;
    }

    const shotMap = new Map(scene.shots.map((s) => [s.id, s]));
    scene.shots = shotIds
      .map((id, index) => {
        const shot = shotMap.get(id);
        if (shot) {
          shot.order = index;
          shot.updatedAt = new Date().toISOString();
        }
        return shot;
      })
      .filter((s): s is Shot => s !== undefined);

    scene.updatedAt = new Date().toISOString();
    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error reordering shots:",
      JSON.stringify({ projectId, sceneId, error }, null, 2)
    );
    throw error;
  }
}

/**
 * Update a shot's video status
 */
export async function updateShotVideoStatus(
  projectId: string,
  sceneId: string,
  shotId: string,
  videoUpdates: Partial<ShotVideo>
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene || !scene.shots) {
      return null;
    }

    const shotIndex = scene.shots.findIndex((s) => s.id === shotId);
    if (shotIndex === -1) {
      return null;
    }

    scene.shots[shotIndex].video = {
      ...scene.shots[shotIndex].video,
      ...videoUpdates,
    } as ShotVideo;
    scene.shots[shotIndex].updatedAt = new Date().toISOString();
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error updating shot video status:",
      JSON.stringify({ projectId, sceneId, shotId, error }, null, 2)
    );
    throw error;
  }
}

// ============================================================================
// AUDIO TRACK HELPERS
// ============================================================================

/**
 * Add an audio track to a scene
 */
export async function addAudioTrackToScene(
  projectId: string,
  sceneId: string,
  audioTrack: AudioTrack
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene) {
      return null;
    }

    // Initialize audioTracks array if needed
    if (!scene.audioTracks) {
      scene.audioTracks = [];
    }

    scene.audioTracks.push(audioTrack);
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error adding audio track to scene:",
      JSON.stringify({ projectId, sceneId, error }, null, 2)
    );
    throw error;
  }
}

/**
 * Update an audio track in a scene
 */
export async function updateAudioTrack(
  projectId: string,
  sceneId: string,
  audioTrackId: string,
  updates: Partial<AudioTrack>
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene || !scene.audioTracks) {
      return null;
    }

    const trackIndex = scene.audioTracks.findIndex((t) => t.id === audioTrackId);
    if (trackIndex === -1) {
      return null;
    }

    scene.audioTracks[trackIndex] = {
      ...scene.audioTracks[trackIndex],
      ...updates,
      updatedAt: new Date().toISOString(),
    };
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error updating audio track:",
      JSON.stringify({ projectId, sceneId, audioTrackId, error }, null, 2)
    );
    throw error;
  }
}

/**
 * Delete an audio track from a scene
 */
export async function deleteAudioTrack(
  projectId: string,
  sceneId: string,
  audioTrackId: string
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene || !scene.audioTracks) {
      return null;
    }

    scene.audioTracks = scene.audioTracks.filter((t) => t.id !== audioTrackId);
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error deleting audio track:",
      JSON.stringify({ projectId, sceneId, audioTrackId, error }, null, 2)
    );
    throw error;
  }
}

/**
 * Update scene numbers after reordering
 */
export async function reorderScenes(projectId: string, sceneIds: string[]): Promise<void> {
  try {
    const scenes = await listScenesForProject(projectId);
    const sceneMap = new Map(scenes.map((s) => [s.id, s]));

    await Promise.all(
      sceneIds.map(async (sceneId, index) => {
        const scene = sceneMap.get(sceneId);
        if (scene && scene.sceneNumber !== index + 1) {
          scene.sceneNumber = index + 1;
          scene.updatedAt = new Date().toISOString();
          await saveScene(projectId, scene);
        }
      })
    );
  } catch (error) {
    console.error("Error reordering scenes:", JSON.stringify({ projectId, error }, null, 2));
    throw error;
  }
}

/**
 * Add a generated image to a scene
 */
export async function addGeneratedImageToScene(
  projectId: string,
  sceneId: string,
  image: GeneratedImage
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene) {
      return null;
    }

    // Initialize generatedImages if needed
    if (!scene.generatedImages) {
      scene.generatedImages = [];
    }
    scene.generatedImages.push(image);
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error adding image to scene:",
      JSON.stringify({ projectId, sceneId, error }, null, 2)
    );
    throw error;
  }
}

/**
 * Add a generated video to a scene (legacy - prefer addShotToScene)
 */
export async function addGeneratedVideoToScene(
  projectId: string,
  sceneId: string,
  video: GeneratedVideo
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene) {
      return null;
    }

    // Initialize generatedVideos if needed
    if (!scene.generatedVideos) {
      scene.generatedVideos = [];
    }
    scene.generatedVideos.push(video);
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error adding video to scene:",
      JSON.stringify({ projectId, sceneId, error }, null, 2)
    );
    throw error;
  }
}

/**
 * Update a generated video's status (legacy - prefer updateShotVideoStatus)
 */
export async function updateVideoStatus(
  projectId: string,
  sceneId: string,
  videoId: string,
  status: GeneratedVideo["status"],
  updates?: Partial<GeneratedVideo>
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene || !scene.generatedVideos) {
      return null;
    }

    const videoIndex = scene.generatedVideos.findIndex((v) => v.id === videoId);
    if (videoIndex === -1) {
      return null;
    }

    scene.generatedVideos[videoIndex] = {
      ...scene.generatedVideos[videoIndex],
      ...updates,
      status,
    };
    scene.updatedAt = new Date().toISOString();

    await saveScene(projectId, scene);
    return scene;
  } catch (error) {
    console.error(
      "Error updating video status:",
      JSON.stringify({ projectId, sceneId, videoId, error }, null, 2)
    );
    throw error;
  }
}

// ============================================================================
// MIGRATION HELPERS
// ============================================================================

/**
 * Check if a scene needs migration from legacy generatedVideos to shots
 */
export function sceneNeedsMigration(scene: Scene): boolean {
  // Scene needs migration if it has legacy generatedVideos but no shots
  const hasLegacyVideos = Boolean(scene.generatedVideos && scene.generatedVideos.length > 0);
  const hasNoShots = !scene.shots || scene.shots.length === 0;
  return hasLegacyVideos && hasNoShots;
}

/**
 * Migrate a scene from legacy generatedVideos to the new shots-based architecture
 * This converts each generatedVideo to a Shot
 */
export function migrateSceneToShots(scene: Scene): Scene {
  // If scene already has shots, no migration needed
  if (scene.shots && scene.shots.length > 0) {
    return scene;
  }

  // If no legacy videos, just ensure shots and audioTracks exist
  if (!scene.generatedVideos || scene.generatedVideos.length === 0) {
    return {
      ...scene,
      shots: scene.shots || [],
      audioTracks: scene.audioTracks || [],
    };
  }

  const now = new Date().toISOString();

  // Convert each generatedVideo to a Shot
  const shots: Shot[] = scene.generatedVideos.map((video, index) => ({
    id: `shot-migrated-${video.id}`,
    order: index,
    prompt: video.prompt,
    sourceType: "generated" as VideoSourceType,
    generationMode: "text-only" as GenerationMode,
    video: {
      url: video.videoUrl,
      status: video.status,
      durationMs: video.duration ? video.duration * 1000 : 5000, // Convert seconds to ms
      error: video.error,
    },
    createdAt: video.createdAt,
    updatedAt: now,
  }));

  return {
    ...scene,
    shots,
    audioTracks: scene.audioTracks || [],
    transitionOut: scene.transitionOut || { type: "none", durationMs: 0 },
    // Keep legacy data for reference
    generatedVideos: scene.generatedVideos,
    generatedImages: scene.generatedImages,
    updatedAt: now,
  };
}

/**
 * Migrate a scene and save it
 */
export async function migrateAndSaveScene(
  projectId: string,
  sceneId: string
): Promise<Scene | null> {
  try {
    const scene = await getScene(projectId, sceneId);
    if (!scene) {
      return null;
    }

    if (!sceneNeedsMigration(scene)) {
      // No migration needed, but ensure arrays exist
      if (!scene.shots) scene.shots = [];
      if (!scene.audioTracks) scene.audioTracks = [];
      return scene;
    }

    console.log(
      "[migrateAndSaveScene] Migrating scene:",
      JSON.stringify(
        { projectId, sceneId, videoCount: scene.generatedVideos?.length || 0 },
        null,
        2
      )
    );

    const migratedScene = migrateSceneToShots(scene);
    await saveScene(projectId, migratedScene);

    console.log(
      "[migrateAndSaveScene] Migration complete:",
      JSON.stringify({ projectId, sceneId, shotCount: migratedScene.shots.length }, null, 2)
    );

    return migratedScene;
  } catch (error) {
    console.error("Error migrating scene:", JSON.stringify({ projectId, sceneId, error }, null, 2));
    throw error;
  }
}

/**
 * Migrate all scenes for a project
 */
export async function migrateProjectScenes(projectId: string): Promise<number> {
  try {
    const project = await getProject(projectId);
    if (!project || !project.scenes) {
      return 0;
    }

    let migratedCount = 0;
    const updatedScenes: Scene[] = [];

    for (const scene of project.scenes) {
      if (sceneNeedsMigration(scene)) {
        const migratedScene = migrateSceneToShots(scene);
        updatedScenes.push(migratedScene);
        migratedCount++;
      } else {
        // Ensure arrays exist even if no migration needed
        updatedScenes.push({
          ...scene,
          shots: scene.shots || [],
          audioTracks: scene.audioTracks || [],
        });
      }
    }

    if (migratedCount > 0) {
      await saveProject(projectId, { ...project, scenes: updatedScenes });
      console.log(
        "[migrateProjectScenes] Migration complete:",
        JSON.stringify({ projectId, migratedCount }, null, 2)
      );
    }

    return migratedCount;
  } catch (error) {
    console.error("Error migrating project scenes:", JSON.stringify({ projectId, error }, null, 2));
    throw error;
  }
}
