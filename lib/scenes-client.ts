/**
 * Client-safe scene utilities
 * These functions and types can be used in client components
 * without importing server-side dependencies (S3, etc.)
 */

// ============================================================================
// TRANSITION TYPES
// ============================================================================

/**
 * Transition types between shots
 */
export type TransitionType =
  | "none" // Hard cut
  | "cross-dissolve" // Blend between shots
  | "fade-to-black" // Fade out to black
  | "fade-from-black" // Fade in from black
  | "fade-to-white" // Fade out to white
  | "fade-from-white"; // Fade in from white

/**
 * Transition configuration
 */
export interface Transition {
  type: TransitionType;
  durationMs: number; // 500-2000ms typically
}

// ============================================================================
// SHOT TYPES
// ============================================================================

/**
 * Video generation modes for Veo 3.1
 */
export type GenerationMode =
  | "text-only" // Generate from text prompt only
  | "start-frame" // Generate from start frame image + prompt
  | "start-end-frame" // Generate from start and end frame images + prompt
  | "reference-images"; // Generate using up to 3 reference images + prompt

/**
 * Video source type
 */
export type VideoSourceType = "uploaded" | "generated";

/**
 * Video status in a shot
 */
export interface ShotVideo {
  url: string;
  status: "pending" | "processing" | "completed" | "failed";
  operationId?: string; // For polling Veo status
  durationMs?: number; // Video duration for timeline
  thumbnailUrl?: string; // Thumbnail extracted from middle of video
  error?: string;
}

/**
 * Reference image type for video generation
 */
export type ReferenceImageType = "location" | "character";

/**
 * Reference image with type and URL
 */
export interface ReferenceImage {
  url: string;
  type: ReferenceImageType;
  name?: string; // Optional name for display (e.g., character or location name)
}

/**
 * Shot interface - represents a single shot/clip in a scene's timeline
 */
export interface Shot {
  id: string;
  order: number; // Position in timeline
  prompt: string; // Text prompt for generation

  // Video source configuration
  sourceType: VideoSourceType;
  generationMode?: GenerationMode;
  durationSeconds?: 4 | 6 | 8; // Video duration in seconds (default: 8)

  // Images for generation
  startFrameImage?: string; // URL for start frame
  endFrameImage?: string; // URL for end frame
  referenceImages?: string[]; // Up to 3 reference/ingredient images (legacy - URL only)
  typedReferenceImages?: ReferenceImage[]; // Up to 3 typed reference images (location/character)

  // Final video
  video?: ShotVideo;

  // Original video (preserved when trimming creates a new file)
  originalVideo?: ShotVideo;

  // Video trimming values (used for creating trimmed video file)
  trimStartMs?: number; // Trim from beginning of video
  trimEndMs?: number; // Trim from end of video

  // Timeline position (calculated from order + durations)
  startTimeMs?: number;

  // Audio settings
  audioMuted?: boolean; // When true, video plays silently (e.g., after detaching audio)

  // Fade effects
  fadeInType?: "none" | "black" | "white"; // Fade in from black/white at start
  fadeOutType?: "none" | "black" | "white"; // Fade out to black/white at end
  fadeDurationMs?: number; // Duration of fade effect in milliseconds (default: 500ms)

  createdAt: string;
  updatedAt: string;
}

// ============================================================================
// AUDIO TRACK TYPES
// ============================================================================

/**
 * Audio source type
 */
export type AudioSourceType = "imported" | "extracted";

/**
 * Audio track interface - represents an audio layer in the timeline
 */
export interface AudioTrack {
  id: string;
  name: string;
  sourceType: AudioSourceType;
  sourceUrl: string; // URL to audio file
  sourceVideoShotId?: string; // If extracted, which shot it came from

  // Original audio (preserved when trimming creates a new file)
  originalSourceUrl?: string; // Original audio URL before trimming
  originalDurationMs?: number; // Original audio duration before trimming

  // Timeline positioning
  startTimeMs: number; // Where audio starts on timeline
  durationMs: number; // Audio duration
  trimStartMs?: number; // Trim from beginning of source
  trimEndMs?: number; // Trim from end of source

  // Audio settings
  volume: number; // 0.0 to 1.0
  muted: boolean;

  createdAt: string;
  updatedAt: string;
}

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
 * Generated image from AI (legacy - used for reference images)
 */
export interface GeneratedImage {
  id: string;
  prompt: string;
  imageUrl: string;
  model: "nano-banana-pro" | "imagen-3" | "other";
  createdAt: string;
}

/**
 * Generated video from AI (legacy - migrated to Shot)
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
 * Composite video (rendered from timeline)
 */
export interface CompositeVideo {
  url: string;
  thumbnailUrl?: string;
  durationMs: number;
  renderedAt: string;
  jobId?: string;
}

/**
 * Composite video rendering status
 */
export type CompositeStatus = "pending" | "processing" | "completed" | "failed";

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

  // Timeline content (new shot-based architecture)
  shots: Shot[]; // Legacy video timeline
  audioTracks: AudioTrack[]; // Legacy audio layers
  removedShots?: Shot[]; // Legacy media library

  // Audio settings
  masterVolume?: number; // Master volume control (0.0 to 2.0, default: 1.0)

  // Transition to next scene
  transitionOut: Transition;

  // Composite video (rendered from timeline)
  compositeVideo?: CompositeVideo;
  compositeStatus?: CompositeStatus;
  compositeError?: string;

  // Legacy fields (kept for migration compatibility)
  generatedImages?: GeneratedImage[];
  generatedVideos?: GeneratedVideo[];

  createdAt: string;
  updatedAt: string;
}

// ============================================================================
// CLIENT-SAFE HELPER FUNCTIONS
// ============================================================================

/**
 * Get the effective duration of a shot after trimming
 * Returns the playable duration (full duration minus trim from start and end)
 *
 * IMPORTANT: If originalVideo exists, the current video file is already trimmed,
 * so video.durationMs IS the effective duration (don't double-subtract trim values).
 * Only calculate from trim values when there's no originalVideo (trim not yet applied).
 */
export function getEffectiveDuration(shot: Shot): number {
  // If we have an originalVideo, the current video is already trimmed
  // The trim values were baked in when the trimmed video file was created
  if (shot.originalVideo) {
    return shot.video?.durationMs || 5000;
  }

  // No originalVideo means trim hasn't been applied to the file yet
  // Calculate effective duration from trim values
  const fullDuration = shot.video?.durationMs || 5000;
  const trimStart = shot.trimStartMs || 0;
  const trimEnd = shot.trimEndMs || 0;
  // Ensure we don't go negative
  return Math.max(0, fullDuration - trimStart - trimEnd);
}

/**
 * Create a new shot with default values
 */
export function createNewShot(order: number): Shot {
  const now = new Date().toISOString();
  return {
    id: `shot-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
    order,
    prompt: "",
    sourceType: "generated",
    generationMode: "text-only",
    createdAt: now,
    updatedAt: now,
  };
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

/**
 * Create a new audio track
 */
export function createNewAudioTrack(
  name: string,
  sourceType: AudioSourceType,
  sourceUrl: string,
  startTimeMs: number = 0,
  durationMs: number = 0
): AudioTrack {
  const now = new Date().toISOString();
  return {
    id: `audio-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
    name,
    sourceType,
    sourceUrl,
    startTimeMs,
    durationMs,
    volume: 1.0,
    muted: false,
    createdAt: now,
    updatedAt: now,
  };
}

/**
 * Calculate timeline positions for all shots in a scene
 * Based on effective video durations (after trimming)
 */
export function calculateTimelinePositions(shots: Shot[]): Shot[] {
  let currentTimeMs = 0;

  return shots.map((shot) => {
    const updatedShot = {
      ...shot,
      startTimeMs: currentTimeMs,
    };

    // Add effective duration (respects trim settings)
    currentTimeMs += getEffectiveDuration(shot);

    return updatedShot;
  });
}

/**
 * Get total timeline duration for a scene (shots only, transition is to next scene)
 * Uses effective duration (after trimming) for each shot
 */
export function getSceneDuration(scene: Scene): number {
  if (!scene.shots || scene.shots.length === 0) {
    return 0;
  }

  let totalMs = 0;
  scene.shots.forEach((shot) => {
    // Add effective duration (respects trim settings)
    totalMs += getEffectiveDuration(shot);
  });

  return totalMs;
}

/**
 * Get the default transition (cut/none)
 */
export function getDefaultTransition(): Transition {
  return {
    type: "none",
    durationMs: 0,
  };
}
