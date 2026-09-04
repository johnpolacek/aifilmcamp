import { readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { checkVideoStatus } from "@/lib/ai/gemini";
import { uploadImageFromBuffer } from "@/lib/s3";
import { isVideoGenerationEnabled } from "@/lib/utils/video-generation";

/**
 * Extract a frame from the middle of a video using ffmpeg
 */
async function extractVideoThumbnail(
  videoBuffer: Buffer,
  durationMs: number
): Promise<Buffer | null> {
  console.log(
    "[extractVideoThumbnail] Starting thumbnail extraction:",
    JSON.stringify(
      {
        videoBufferSize: videoBuffer.length,
        durationMs,
        durationSeconds: durationMs / 1000,
      },
      null,
      2
    )
  );

  try {
    const ffmpeg = await import("fluent-ffmpeg").catch(() => null);
    if (!ffmpeg) {
      console.log("[extractVideoThumbnail] ffmpeg not available for thumbnail extraction");
      return null;
    }

    console.log("[extractVideoThumbnail] ffmpeg module loaded successfully");

    // Create temporary files
    const tempVideoPath = join(tmpdir(), `video-${Date.now()}.mp4`);
    const tempImagePath = join(tmpdir(), `thumbnail-${Date.now()}.jpg`);

    console.log(
      "[extractVideoThumbnail] Created temp files:",
      JSON.stringify({ tempVideoPath, tempImagePath }, null, 2)
    );

    try {
      // Write video buffer to temp file
      writeFileSync(tempVideoPath, videoBuffer);
      console.log(
        "[extractVideoThumbnail] Video buffer written to temp file:",
        JSON.stringify({ tempVideoPath, bufferSize: videoBuffer.length }, null, 2)
      );

      // Calculate middle timestamp (in seconds)
      const durationSeconds = durationMs / 1000;
      const middleTime = durationSeconds / 2;

      console.log(
        "[extractVideoThumbnail] Extracting frame at middle:",
        JSON.stringify({ durationSeconds, middleTime }, null, 2)
      );

      // Extract frame at middle of video
      await new Promise<void>((resolve, reject) => {
        ffmpeg
          .default(tempVideoPath)
          .seekInput(middleTime)
          .frames(1)
          .output(tempImagePath)
          .on("end", () => {
            console.log("[extractVideoThumbnail] Frame extraction completed successfully");
            resolve();
          })
          .on("error", (err: Error) => {
            console.error(
              "[extractVideoThumbnail] ffmpeg error:",
              JSON.stringify({ error: err.message, stack: err.stack }, null, 2)
            );
            reject(err);
          })
          .run();
      });

      // Read the thumbnail image
      const thumbnailBuffer = Buffer.from(readFileSync(tempImagePath));
      console.log(
        "[extractVideoThumbnail] Thumbnail extracted successfully:",
        JSON.stringify(
          {
            thumbnailBufferSize: thumbnailBuffer.length,
            tempImagePath,
          },
          null,
          2
        )
      );

      return thumbnailBuffer;
    } finally {
      // Clean up temp files
      try {
        unlinkSync(tempVideoPath);
        unlinkSync(tempImagePath);
      } catch (cleanupError) {
        console.error(
          "[video-status] Error cleaning up temp files:",
          JSON.stringify(
            { error: cleanupError instanceof Error ? cleanupError.message : String(cleanupError) },
            null,
            2
          )
        );
      }
    }
  } catch (error) {
    console.error(
      "[video-status] Error extracting thumbnail:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );
    return null;
  }
}

export async function GET(request: Request) {
  try {
    // Check if video generation is enabled (localhost/development only)
    if (!isVideoGenerationEnabled()) {
      return NextResponse.json(
        { success: false, error: "Video generation is only available in development mode" },
        { status: 403 }
      );
    }

    // Check authentication
    const { userId } = await auth();
    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    // Get query parameters
    const { searchParams } = new URL(request.url);
    const operationId = searchParams.get("operationId");
    const projectId = searchParams.get("projectId");
    const sceneId = searchParams.get("sceneId");
    const videoId = searchParams.get("videoId");
    const thumbnailPath = searchParams.get("thumbnailPath"); // Predictable path from generate-video

    if (!operationId) {
      return NextResponse.json(
        { success: false, error: "Operation ID is required" },
        { status: 400 }
      );
    }

    console.log(
      "[video-status] Checking status:",
      JSON.stringify({ operationId, projectId, sceneId, videoId, thumbnailPath }, null, 2)
    );

    // Check video status
    const result = await checkVideoStatus(operationId);

    if (!result.success) {
      console.error(
        "[video-status] Check failed:",
        JSON.stringify({ error: result.error }, null, 2)
      );
      return NextResponse.json(
        { success: false, error: result.error || "Failed to check video status" },
        { status: 500 }
      );
    }

    // If video is completed, get the video data and store in S3
    // Veo 3.1 can return either a URL (if GCS output configured) or base64-encoded bytes (default)
    let finalVideoUrl = result.videoUrl;
    let thumbnailUrl: string | undefined;

    console.log(
      "[video-status] Processing video completion:",
      JSON.stringify(
        {
          status: result.status,
          hasVideoUrl: !!result.videoUrl,
          hasVideoBase64: !!result.videoBase64,
          base64Length: result.videoBase64?.length,
          videoUrl: result.videoUrl?.substring(0, 100),
          projectId,
          sceneId,
          durationMs: result.durationMs,
        },
        null,
        2
      )
    );

    // Handle completed video - either from URL or base64 bytes
    if (
      result.status === "completed" &&
      (result.videoUrl || result.videoBase64) &&
      projectId &&
      sceneId
    ) {
      try {
        let videoBuffer: Buffer | null = null;

        // CASE 1: Video returned as base64-encoded bytes (Veo 3.1 default)
        if (result.videoBase64) {
          console.log(
            "[video-status] Processing base64-encoded video:",
            JSON.stringify({ base64Length: result.videoBase64.length }, null, 2)
          );
          videoBuffer = Buffer.from(result.videoBase64, "base64");
          console.log(
            "[video-status] Video buffer decoded from base64:",
            JSON.stringify({ bufferSize: videoBuffer.length }, null, 2)
          );
        }
        // CASE 2: Video returned as URL (GCS bucket configured)
        else if (result.videoUrl) {
          console.log(
            "[video-status] Downloading video from URL:",
            JSON.stringify({ videoUrl: result.videoUrl.substring(0, 100) }, null, 2)
          );

          // Get API key for authenticated download
          const apiKey =
            process.env.GOOGLE_GENERATIVE_AI_API_KEY || process.env.GOOGLE_GEMINI_API_KEY;

          // Download video and upload to S3 for permanent storage
          // The Google API video URL requires API key authentication
          const downloadUrl = result.videoUrl.includes("?")
            ? `${result.videoUrl}&key=${apiKey}`
            : `${result.videoUrl}?key=${apiKey}`;

          const videoResponse = await fetch(downloadUrl);
          console.log(
            "[video-status] Video download response:",
            JSON.stringify(
              {
                ok: videoResponse.ok,
                status: videoResponse.status,
                contentType: videoResponse.headers.get("content-type"),
                contentLength: videoResponse.headers.get("content-length"),
              },
              null,
              2
            )
          );

          if (videoResponse.ok) {
            videoBuffer = Buffer.from(await videoResponse.arrayBuffer());
          } else {
            const errorBody = await videoResponse.text().catch(() => "");
            console.error(
              "[video-status] Video download failed:",
              JSON.stringify(
                {
                  status: videoResponse.status,
                  statusText: videoResponse.statusText,
                  errorBody: errorBody.substring(0, 500),
                },
                null,
                2
              )
            );

            return NextResponse.json(
              {
                success: false,
                status: "failed",
                error: `Failed to download video from Google (${videoResponse.status}). Please try generating again.`,
                operationId,
              },
              { status: 500 }
            );
          }
        }

        if (videoBuffer) {
          // Add timestamp to video key to bust CloudFront cache when replacing shots
          // S3 Path Convention: projects/{projectId}/scenes/{sceneId}/videos/{filename}
          const timestamp = Date.now();
          const videoKey = `projects/${projectId}/scenes/${sceneId}/videos/${videoId || operationId}-${timestamp}.mp4`;

          console.log(
            "[video-status] Video buffer received:",
            JSON.stringify(
              {
                bufferSize: videoBuffer.length,
                videoKey,
                timestamp,
              },
              null,
              2
            )
          );

          // Upload to S3 using the file upload function
          const { uploadFileFromBuffer } = await import("@/lib/s3");
          finalVideoUrl = await uploadFileFromBuffer(videoBuffer, videoKey, "video/mp4");

          console.log(
            "[video-status] Video uploaded to S3:",
            JSON.stringify(
              {
                videoKey,
                finalVideoUrl,
                s3Path: `s3://aifilmcamp-public/${videoKey}`,
              },
              null,
              2
            )
          );

          // Generate thumbnail from middle of video
          const durationMs = result.durationMs || 8000; // Default to 8 seconds if not provided
          console.log(
            "[video-status] Starting thumbnail generation:",
            JSON.stringify({ durationMs, videoBufferSize: videoBuffer.length }, null, 2)
          );

          const thumbnailBuffer = await extractVideoThumbnail(videoBuffer, durationMs);

          if (thumbnailBuffer) {
            // Use the predictable thumbnailPath if provided, otherwise generate one
            // S3 Path Convention: projects/{projectId}/scenes/{sceneId}/thumbnails/{filename}
            const thumbnailKey =
              thumbnailPath ||
              `projects/${projectId}/scenes/${sceneId}/thumbnails/${videoId || operationId}-${timestamp}.jpg`;
            console.log(
              "[video-status] Uploading thumbnail to S3:",
              JSON.stringify(
                {
                  thumbnailKey,
                  thumbnailBufferSize: thumbnailBuffer.length,
                  usingPredictablePath: !!thumbnailPath,
                },
                null,
                2
              )
            );

            thumbnailUrl = await uploadImageFromBuffer(thumbnailBuffer, thumbnailKey, "image/jpeg");

            console.log(
              "[video-status] Thumbnail generated and uploaded successfully:",
              JSON.stringify({ thumbnailKey, thumbnailUrl }, null, 2)
            );
          } else {
            console.log("[video-status] Thumbnail generation returned null - no thumbnail created");
          }
        } else {
          console.error("[video-status] No video buffer available");
          return NextResponse.json(
            {
              success: false,
              status: "failed",
              error: "No video data available. Please try generating again.",
              operationId,
            },
            { status: 500 }
          );
        }
      } catch (uploadError) {
        // Failed to process video - return error
        console.error(
          "[video-status] Failed to process video:",
          JSON.stringify(
            {
              error: uploadError instanceof Error ? uploadError.message : String(uploadError),
              stack: uploadError instanceof Error ? uploadError.stack : undefined,
            },
            null,
            2
          )
        );

        return NextResponse.json(
          {
            success: false,
            status: "failed",
            error: "Failed to process video. Please try generating again.",
            operationId,
          },
          { status: 500 }
        );
      }
    } else {
      console.log(
        "[video-status] Skipping thumbnail generation:",
        JSON.stringify(
          {
            status: result.status,
            hasVideoUrl: !!result.videoUrl,
            hasProjectId: !!projectId,
            hasSceneId: !!sceneId,
          },
          null,
          2
        )
      );
    }

    const responseData = {
      success: true,
      status: result.status,
      videoUrl: finalVideoUrl,
      thumbnailUrl,
      operationId,
      durationMs: result.durationMs,
    };

    console.log(
      "[video-status] Returning response:",
      JSON.stringify(
        {
          ...responseData,
          videoUrl: responseData.videoUrl?.substring(0, 100),
          thumbnailUrl: responseData.thumbnailUrl?.substring(0, 100),
        },
        null,
        2
      )
    );

    return NextResponse.json(responseData);
  } catch (error) {
    console.error(
      "[video-status] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );

    return NextResponse.json({ success: false, error: "Internal server error" }, { status: 500 });
  }
}
