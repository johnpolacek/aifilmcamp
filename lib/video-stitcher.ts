/**
 * Video Stitching Service
 * Combines multiple scene videos into a single film
 */

import type { GeneratedVideo, Scene } from "./scenes";

export interface StitchOptions {
  projectId: string;
  sceneIds?: string[]; // If not provided, uses all scenes with completed videos
  transition?: "none" | "fade" | "crossfade"; // Future: transition types
}

export interface StitchResult {
  success: boolean;
  filmUrl?: string;
  filmId?: string;
  duration?: number;
  sceneCount?: number;
  error?: string;
}

/**
 * Get all completed videos from scenes
 */
export function getCompletedVideos(scenes: Scene[]): GeneratedVideo[] {
  return scenes
    .sort((a, b) => a.sceneNumber - b.sceneNumber)
    .flatMap((scene) =>
      (scene.generatedVideos || []).filter((v) => v.status === "completed" && v.videoUrl)
    );
}

/**
 * Stitch scene videos into a single film
 *
 * Note: Client-side video stitching has limitations. For production use,
 * consider using server-side video processing with FFmpeg or a video API.
 *
 * This implementation creates a playlist/manifest approach that can be
 * used with a video player that supports playlists.
 */
export async function stitchScenes(scenes: Scene[], options: StitchOptions): Promise<StitchResult> {
  const { projectId, sceneIds } = options;

  try {
    // Filter scenes if specific IDs provided
    let targetScenes = scenes;
    if (sceneIds && sceneIds.length > 0) {
      targetScenes = scenes.filter((s) => sceneIds.includes(s.id));
    }

    // Get completed videos
    const videos = getCompletedVideos(targetScenes);

    if (videos.length === 0) {
      return {
        success: false,
        error: "No completed videos found in scenes",
      };
    }

    // Create a film manifest
    const filmId = `film-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
    const manifest = {
      id: filmId,
      projectId,
      createdAt: new Date().toISOString(),
      videos: videos.map((v, index) => ({
        order: index,
        videoId: v.id,
        videoUrl: v.videoUrl,
        duration: v.duration,
        prompt: v.prompt,
      })),
      totalDuration: videos.reduce((sum, v) => sum + (v.duration || 0), 0),
    };

    // For now, we return the manifest data
    // In a production implementation, this would upload the manifest to S3
    // and optionally trigger server-side video concatenation

    console.log(
      "[stitchScenes] Created film manifest:",
      JSON.stringify({ filmId, sceneCount: videos.length }, null, 2)
    );

    return {
      success: true,
      filmId,
      sceneCount: videos.length,
      duration: manifest.totalDuration,
      // For now, use the first video URL as placeholder
      // In production, this would be the URL of the stitched video
      filmUrl: videos[0]?.videoUrl,
    };
  } catch (error) {
    console.error(
      "[stitchScenes] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );

    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to stitch videos",
    };
  }
}

/**
 * Create a video playlist for playback
 * This can be used with video players that support playlists
 */
export function createVideoPlaylist(scenes: Scene[]): {
  videos: Array<{
    sceneNumber: number;
    title: string;
    videoUrl: string;
    duration?: number;
  }>;
} {
  const sortedScenes = [...scenes].sort((a, b) => a.sceneNumber - b.sceneNumber);

  const videos = sortedScenes
    .map((scene) => {
      const completedVideo = scene.generatedVideos?.find(
        (v) => v.status === "completed" && v.videoUrl
      );

      if (completedVideo) {
        return {
          sceneNumber: scene.sceneNumber,
          title: scene.title,
          videoUrl: completedVideo.videoUrl,
          duration: completedVideo.duration,
        };
      }
      return null;
    })
    .filter((v): v is NonNullable<typeof v> => v !== null);

  return { videos };
}
