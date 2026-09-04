import { readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { uploadImageFromBuffer } from "@/lib/s3";

/**
 * Extract a frame from the middle of a video using ffmpeg
 */
async function extractVideoThumbnail(
  videoBuffer: Buffer,
  durationMs: number
): Promise<Buffer | null> {
  console.log(
    "[generate-thumbnail] Starting thumbnail extraction:",
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
      console.log("[generate-thumbnail] ffmpeg not available for thumbnail extraction");
      return null;
    }

    console.log("[generate-thumbnail] ffmpeg module loaded successfully");

    // Create temporary files
    const tempVideoPath = join(tmpdir(), `video-${Date.now()}.mp4`);
    const tempImagePath = join(tmpdir(), `thumbnail-${Date.now()}.jpg`);

    console.log(
      "[generate-thumbnail] Created temp files:",
      JSON.stringify({ tempVideoPath, tempImagePath }, null, 2)
    );

    try {
      // Write video buffer to temp file
      writeFileSync(tempVideoPath, videoBuffer);
      console.log(
        "[generate-thumbnail] Video buffer written to temp file:",
        JSON.stringify({ tempVideoPath, bufferSize: videoBuffer.length }, null, 2)
      );

      // Calculate middle timestamp (in seconds)
      const durationSeconds = durationMs / 1000;
      const middleTime = durationSeconds / 2;

      console.log(
        "[generate-thumbnail] Extracting frame at middle:",
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
            console.log("[generate-thumbnail] Frame extraction completed successfully");
            resolve();
          })
          .on("error", (err: Error) => {
            console.error(
              "[generate-thumbnail] ffmpeg error:",
              JSON.stringify({ error: err.message, stack: err.stack }, null, 2)
            );
            reject(err);
          })
          .run();
      });

      // Read the thumbnail image
      const thumbnailBuffer = Buffer.from(readFileSync(tempImagePath));
      console.log(
        "[generate-thumbnail] Thumbnail extracted successfully:",
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
          "[generate-thumbnail] Error cleaning up temp files:",
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
      "[generate-thumbnail] Error extracting thumbnail:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );
    return null;
  }
}

export async function POST(request: Request) {
  try {
    // Check authentication
    const { userId } = await auth();
    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    // Parse request body
    const body = await request.json();
    const { videoUrl, projectId, sceneId, videoId, durationMs } = body;

    if (!videoUrl) {
      return NextResponse.json({ success: false, error: "Video URL is required" }, { status: 400 });
    }

    if (!projectId || !sceneId) {
      return NextResponse.json(
        { success: false, error: "Project ID and Scene ID are required" },
        { status: 400 }
      );
    }

    console.log(
      "[generate-thumbnail] Generating thumbnail for uploaded video:",
      JSON.stringify(
        {
          videoUrl: videoUrl.substring(0, 100),
          projectId,
          sceneId,
          videoId,
          durationMs,
        },
        null,
        2
      )
    );

    // Download video
    const videoResponse = await fetch(videoUrl);
    if (!videoResponse.ok) {
      console.error(
        "[generate-thumbnail] Failed to download video:",
        JSON.stringify(
          {
            status: videoResponse.status,
            statusText: videoResponse.statusText,
          },
          null,
          2
        )
      );
      return NextResponse.json(
        { success: false, error: "Failed to download video" },
        { status: 400 }
      );
    }

    const videoBuffer = Buffer.from(await videoResponse.arrayBuffer());
    console.log(
      "[generate-thumbnail] Video downloaded:",
      JSON.stringify({ bufferSize: videoBuffer.length }, null, 2)
    );

    // Generate thumbnail from middle of video
    const videoDurationMs = durationMs || 8000; // Default to 8 seconds if not provided
    const thumbnailBuffer = await extractVideoThumbnail(videoBuffer, videoDurationMs);

    if (!thumbnailBuffer) {
      console.log("[generate-thumbnail] Thumbnail generation returned null");
      return NextResponse.json(
        { success: false, error: "Failed to generate thumbnail" },
        { status: 500 }
      );
    }

    // Upload thumbnail to S3
    // S3 Path Convention: projects/{projectId}/scenes/{sceneId}/thumbnails/{filename}
    const thumbnailKey = `projects/${projectId}/scenes/${sceneId}/thumbnails/${videoId || `video-${Date.now()}`}.jpg`;
    console.log(
      "[generate-thumbnail] Uploading thumbnail to S3:",
      JSON.stringify({ thumbnailKey, thumbnailBufferSize: thumbnailBuffer.length }, null, 2)
    );

    const thumbnailUrl = await uploadImageFromBuffer(thumbnailBuffer, thumbnailKey, "image/jpeg");

    console.log(
      "[generate-thumbnail] Thumbnail generated and uploaded successfully:",
      JSON.stringify({ thumbnailKey, thumbnailUrl }, null, 2)
    );

    return NextResponse.json({
      success: true,
      thumbnailUrl,
    });
  } catch (error) {
    console.error(
      "[generate-thumbnail] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );

    return NextResponse.json({ success: false, error: "Internal server error" }, { status: 500 });
  }
}
