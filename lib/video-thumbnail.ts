/**
 * Client-side video thumbnail generation
 * Extracts a frame from the middle of a video file using Canvas API
 * Works in all deployment environments (including serverless)
 */

export interface ThumbnailResult {
  success: boolean;
  thumbnailBlob?: Blob;
  thumbnailDataUrl?: string;
  durationMs?: number;
  error?: string;
}

/**
 * Generate a thumbnail from a video file by extracting a frame from the middle
 * @param videoFile - The video File object
 * @param options - Optional configuration
 * @returns Promise with thumbnail data
 */
export async function generateThumbnailFromFile(
  videoFile: File,
  options: {
    seekToMiddle?: boolean;
    seekToSeconds?: number;
    maxWidth?: number;
    quality?: number;
  } = {}
): Promise<ThumbnailResult> {
  const { seekToMiddle = true, seekToSeconds, maxWidth = 1280, quality = 0.85 } = options;

  console.log(
    "[generateThumbnailFromFile] Starting thumbnail generation:",
    JSON.stringify(
      {
        fileName: videoFile.name,
        fileSize: videoFile.size,
        fileType: videoFile.type,
        seekToMiddle,
        seekToSeconds,
        maxWidth,
        quality,
      },
      null,
      2
    )
  );

  return new Promise((resolve) => {
    const video = document.createElement("video");
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");
    let resolved = false;
    let timeoutId: ReturnType<typeof setTimeout>;

    const cleanup = (videoUrl: string) => {
      if (timeoutId) clearTimeout(timeoutId);
      URL.revokeObjectURL(videoUrl);
      video.onloadedmetadata = null;
      video.onloadeddata = null;
      video.onseeked = null;
      video.onerror = null;
    };

    const safeResolve = (result: ThumbnailResult) => {
      if (!resolved) {
        resolved = true;
        resolve(result);
      }
    };

    if (!ctx) {
      console.error("[generateThumbnailFromFile] Could not get canvas context");
      safeResolve({ success: false, error: "Could not get canvas context" });
      return;
    }

    // Create object URL for the video file
    const videoUrl = URL.createObjectURL(videoFile);

    // Set up video element - these properties help with loading
    video.preload = "auto"; // Use "auto" instead of "metadata" for better compatibility
    video.muted = true;
    video.playsInline = true;
    video.autoplay = false;

    // Some browsers need crossOrigin even for blob URLs
    video.crossOrigin = "anonymous";

    // Function to extract frame once video is ready
    const extractFrame = () => {
      if (resolved) return;

      try {
        // Calculate dimensions maintaining aspect ratio
        let width = video.videoWidth;
        let height = video.videoHeight;

        if (!width || !height) {
          console.warn(
            "[generateThumbnailFromFile] Video dimensions not available - continuing without thumbnail"
          );
          cleanup(videoUrl);
          safeResolve({ success: false, error: "Video dimensions not available" });
          return;
        }

        if (width > maxWidth) {
          const scale = maxWidth / width;
          width = maxWidth;
          height = Math.round(height * scale);
        }

        canvas.width = width;
        canvas.height = height;

        console.log(
          "[generateThumbnailFromFile] Extracting frame:",
          JSON.stringify(
            {
              originalWidth: video.videoWidth,
              originalHeight: video.videoHeight,
              canvasWidth: width,
              canvasHeight: height,
              currentTime: video.currentTime,
            },
            null,
            2
          )
        );

        // Draw the video frame to canvas
        ctx.drawImage(video, 0, 0, width, height);

        // Convert canvas to blob
        canvas.toBlob(
          (blob) => {
            // Clean up
            cleanup(videoUrl);

            if (blob) {
              // Also create data URL for immediate preview
              const thumbnailDataUrl = canvas.toDataURL("image/jpeg", quality);

              console.log(
                "[generateThumbnailFromFile] Thumbnail generated successfully:",
                JSON.stringify(
                  {
                    blobSize: blob.size,
                    dataUrlLength: thumbnailDataUrl.length,
                    durationMs: Math.round(video.duration * 1000),
                  },
                  null,
                  2
                )
              );

              safeResolve({
                success: true,
                thumbnailBlob: blob,
                thumbnailDataUrl,
                durationMs: Math.round(video.duration * 1000),
              });
            } else {
              console.error("[generateThumbnailFromFile] Failed to create blob");
              safeResolve({ success: false, error: "Failed to create thumbnail blob" });
            }
          },
          "image/jpeg",
          quality
        );
      } catch (error) {
        cleanup(videoUrl);
        console.error(
          "[generateThumbnailFromFile] Error extracting frame:",
          JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
        );
        safeResolve({
          success: false,
          error: error instanceof Error ? error.message : "Failed to extract frame",
        });
      }
    };

    // Handle seek completed - extract frame
    video.onseeked = extractFrame;

    // Handle metadata loaded - get duration and seek to middle
    const handleMetadataLoaded = () => {
      if (resolved) return;

      const durationMs = Math.round(video.duration * 1000);
      const seekTime = seekToSeconds ?? (seekToMiddle ? video.duration / 2 : 0.1);

      console.log(
        "[generateThumbnailFromFile] Video metadata loaded:",
        JSON.stringify(
          {
            duration: video.duration,
            durationMs,
            videoWidth: video.videoWidth,
            videoHeight: video.videoHeight,
            seekTime,
          },
          null,
          2
        )
      );

      // Seek to the desired time
      video.currentTime = seekTime;
    };

    video.onloadedmetadata = handleMetadataLoaded;

    // Also listen for loadeddata as a fallback - some browsers fire this but not loadedmetadata
    video.onloadeddata = () => {
      if (resolved) return;
      console.log("[generateThumbnailFromFile] Video data loaded (fallback)");

      // If we have metadata, try to seek
      if (video.duration && video.videoWidth && video.videoHeight) {
        handleMetadataLoaded();
      }
    };

    // Handle errors
    video.onerror = () => {
      cleanup(videoUrl);
      console.error(
        "[generateThumbnailFromFile] Video load error:",
        JSON.stringify({ error: video.error?.message, code: video.error?.code }, null, 2)
      );
      safeResolve({
        success: false,
        error: video.error?.message || "Failed to load video",
      });
    };

    // Set src and explicitly call load()
    video.src = videoUrl;
    video.load();

    // Timeout after 30 seconds
    timeoutId = setTimeout(() => {
      if (!resolved) {
        cleanup(videoUrl);
        console.warn(
          "[generateThumbnailFromFile] Timeout waiting for video to load - continuing without thumbnail"
        );
        safeResolve({ success: false, error: "Timeout waiting for video to load" });
      }
    }, 30000);
  });
}

/**
 * Generate a thumbnail from a video URL by extracting a frame from the middle
 * Note: This only works for videos that allow cross-origin access
 * @param videoUrl - The video URL
 * @param options - Optional configuration
 * @returns Promise with thumbnail data
 */
export async function generateThumbnailFromUrl(
  videoUrl: string,
  options: {
    seekToMiddle?: boolean;
    seekToSeconds?: number;
    maxWidth?: number;
    quality?: number;
  } = {}
): Promise<ThumbnailResult> {
  const { seekToMiddle = true, seekToSeconds, maxWidth = 1280, quality = 0.85 } = options;

  console.log(
    "[generateThumbnailFromUrl] Starting thumbnail generation from URL:",
    JSON.stringify(
      {
        videoUrl: videoUrl.substring(0, 100),
        seekToMiddle,
        seekToSeconds,
        maxWidth,
        quality,
      },
      null,
      2
    )
  );

  return new Promise((resolve) => {
    const video = document.createElement("video");
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");

    if (!ctx) {
      console.error("[generateThumbnailFromUrl] Could not get canvas context");
      resolve({ success: false, error: "Could not get canvas context" });
      return;
    }

    video.src = videoUrl;
    video.crossOrigin = "anonymous"; // Required for cross-origin videos
    video.preload = "metadata";
    video.muted = true;
    video.playsInline = true;

    // Handle metadata loaded - get duration and seek to middle
    video.onloadedmetadata = () => {
      const durationMs = Math.round(video.duration * 1000);
      const seekTime = seekToSeconds ?? (seekToMiddle ? video.duration / 2 : 0.1);

      console.log(
        "[generateThumbnailFromUrl] Video metadata loaded:",
        JSON.stringify(
          {
            duration: video.duration,
            durationMs,
            videoWidth: video.videoWidth,
            videoHeight: video.videoHeight,
            seekTime,
          },
          null,
          2
        )
      );

      video.currentTime = seekTime;
    };

    // Handle seek completed - extract frame
    video.onseeked = () => {
      try {
        // Calculate dimensions maintaining aspect ratio
        let width = video.videoWidth;
        let height = video.videoHeight;

        if (width > maxWidth) {
          const scale = maxWidth / width;
          width = maxWidth;
          height = Math.round(height * scale);
        }

        canvas.width = width;
        canvas.height = height;

        console.log(
          "[generateThumbnailFromUrl] Extracting frame:",
          JSON.stringify(
            {
              originalWidth: video.videoWidth,
              originalHeight: video.videoHeight,
              canvasWidth: width,
              canvasHeight: height,
              currentTime: video.currentTime,
            },
            null,
            2
          )
        );

        // Draw the video frame to canvas
        ctx.drawImage(video, 0, 0, width, height);

        // Convert canvas to blob
        canvas.toBlob(
          (blob) => {
            if (blob) {
              // Also create data URL for immediate preview
              const thumbnailDataUrl = canvas.toDataURL("image/jpeg", quality);

              console.log(
                "[generateThumbnailFromUrl] Thumbnail generated successfully:",
                JSON.stringify(
                  {
                    blobSize: blob.size,
                    dataUrlLength: thumbnailDataUrl.length,
                    durationMs: Math.round(video.duration * 1000),
                  },
                  null,
                  2
                )
              );

              resolve({
                success: true,
                thumbnailBlob: blob,
                thumbnailDataUrl,
                durationMs: Math.round(video.duration * 1000),
              });
            } else {
              console.error("[generateThumbnailFromUrl] Failed to create blob");
              resolve({ success: false, error: "Failed to create thumbnail blob" });
            }
          },
          "image/jpeg",
          quality
        );
      } catch (error) {
        console.error(
          "[generateThumbnailFromUrl] Error extracting frame:",
          JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
        );
        resolve({
          success: false,
          error: error instanceof Error ? error.message : "Failed to extract frame",
        });
      }
    };

    // Handle errors
    video.onerror = () => {
      console.error(
        "[generateThumbnailFromUrl] Video load error:",
        JSON.stringify({ error: video.error?.message }, null, 2)
      );
      resolve({
        success: false,
        error: video.error?.message || "Failed to load video",
      });
    };

    // Timeout after 30 seconds
    setTimeout(() => {
      console.error("[generateThumbnailFromUrl] Timeout waiting for video");
      resolve({ success: false, error: "Timeout waiting for video to load" });
    }, 30000);
  });
}
