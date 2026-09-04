/**
 * Video Composer Types
 * These types define the interface between the Next.js app and the video composer service
 */

export interface CompositionRequest {
  jobId: string;
  projectId: string;
  sceneId: string;
  webhookUrl: string; // Callback URL when complete
  shots: CompositionShot[];
  audioTracks: CompositionAudioTrack[];
  masterVolume?: number; // Master volume control (0.0 to 2.0, default: 1.0)
}

export interface CompositionShot {
  id: string;
  order: number;
  videoUrl: string;
  durationMs: number;
  trimStartMs: number;
  trimEndMs: number;
  audioMuted: boolean;
  fadeInType?: "none" | "black" | "white";
  fadeOutType?: "none" | "black" | "white";
  fadeDurationMs?: number;
}

export interface CompositionAudioTrack {
  id: string;
  sourceUrl: string;
  startTimeMs: number;
  durationMs: number;
  trimStartMs: number;
  volume: number;
  muted: boolean;
}

export interface CompositionResult {
  jobId: string;
  status: "completed" | "failed";
  videoUrl?: string;
  thumbnailUrl?: string;
  durationMs?: number;
  error?: string;
}

export interface JobStatus {
  jobId: string;
  status: "processing" | "completed" | "failed";
  progress?: number;
  error?: string;
}
