/** Client-safe scene planning and asset types. */

/**
 * Prompt-first shot planning interface used in the default workflow.
 */
export interface PromptShot {
  id: string;
  shotNumber: number;
  title: string;
  framing: string;
  cameraMovement: string;
  action: string;
  continuityNotes?: string;
  durationEstimateSeconds?: number;
  referenceAssetIds?: string[];
  prompt: string;
}

// ============================================================================
// SCENE INTERFACE
// ============================================================================

/**
 * Generated image asset
 */
export interface GeneratedImage {
  id: string;
  prompt: string;
  imageUrl: string;
  model: "nano-banana-pro" | "imagen-3" | "other";
  createdAt: string;
}

/**
 * Historical generated video asset, retained for project exports
 */
export interface GeneratedVideo {
  id: string;
  prompt: string;
  videoUrl: string;
  thumbnailUrl?: string;
  model: "veo-3.1" | "veo-2" | "other";
  status: "pending" | "processing" | "completed" | "failed";
  duration?: number; // Duration in seconds
  createdAt: string;
  completedAt?: string;
  error?: string;
}

/**
 * Scene interface - represents a single scene in a film project
 */
export interface Scene {
  id: string;
  projectId: string;
  sceneNumber: number;
  title: string;
  screenplay: string; // Scene-specific screenplay text
  summary?: string;
  dramaticPurpose?: string;
  emotionalBeat?: string;
  visualIntent?: string;
  characters: string[]; // Character IDs present in this scene
  locationId?: string; // Reference to a project location by name
  promptShots?: PromptShot[];

  // Asset metadata retained for existing project media
  generatedImages?: GeneratedImage[];
  generatedVideos?: GeneratedVideo[];

  createdAt: string;
  updatedAt: string;
}

export function createNewPromptShot(shotNumber: number): PromptShot {
  return {
    id: `prompt-shot-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
    shotNumber,
    title: `Shot ${shotNumber}`,
    framing: "",
    cameraMovement: "",
    action: "",
    continuityNotes: "",
    durationEstimateSeconds: 4,
    referenceAssetIds: [],
    prompt: "",
  };
}
