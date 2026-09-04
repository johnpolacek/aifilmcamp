import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { uploadFileFromBuffer } from "@/lib/s3";

/**
 * POST /api/video/trim
 *
 * Trim a video file to specified in/out points.
 * Creates a new trimmed video file and returns its URL.
 */
export async function POST(request: Request) {
  try {
    // Check authentication
    const { userId } = await auth();
    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    // Parse request body
    const body = await request.json();
    const { projectId, sceneId, shotId, videoUrl, trimStartMs, trimEndMs, durationMs } = body;

    if (!projectId || !sceneId || !shotId) {
      return NextResponse.json(
        { success: false, error: "Project ID, Scene ID, and Shot ID are required" },
        { status: 400 }
      );
    }

    if (!videoUrl) {
      return NextResponse.json({ success: false, error: "Video URL is required" }, { status: 400 });
    }

    if (trimStartMs === undefined && trimEndMs === undefined) {
      return NextResponse.json(
        { success: false, error: "At least one trim value (trimStartMs or trimEndMs) is required" },
        { status: 400 }
      );
    }

    const trimStart = trimStartMs || 0;
    const trimEnd = trimEndMs || 0;
    const fullDuration = durationMs || 8000;
    const effectiveDuration = fullDuration - trimStart - trimEnd;

    if (effectiveDuration <= 0) {
      return NextResponse.json(
        {
          success: false,
          error: "Invalid trim values - resulting duration would be zero or negative",
        },
        { status: 400 }
      );
    }

    console.log(
      "[video-trim] Starting trim:",
      JSON.stringify(
        {
          projectId,
          sceneId,
          shotId,
          trimStartMs: trimStart,
          trimEndMs: trimEnd,
          fullDuration,
          effectiveDuration,
          videoUrl: videoUrl.substring(0, 100),
        },
        null,
        2
      )
    );

    // Download the video
    const videoResponse = await fetch(videoUrl);
    if (!videoResponse.ok) {
      return NextResponse.json({ success: false, error: "Failed to fetch video" }, { status: 400 });
    }

    const videoBuffer = Buffer.from(await videoResponse.arrayBuffer());

    // Try to use ffmpeg for video trimming
    let trimmedBuffer: Buffer;

    try {
      const ffmpeg = await import("fluent-ffmpeg").catch(() => null);

      if (ffmpeg) {
        trimmedBuffer = await trimVideoWithFfmpeg(
          videoBuffer,
          ffmpeg.default,
          trimStart / 1000, // Convert to seconds
          effectiveDuration / 1000 // Convert to seconds
        );
      } else {
        console.log("[video-trim] ffmpeg not available");
        return NextResponse.json(
          {
            success: false,
            error: "Video trimming requires ffmpeg which is not available in this environment.",
          },
          { status: 501 }
        );
      }
    } catch (ffmpegError) {
      console.error(
        "[video-trim] ffmpeg error:",
        JSON.stringify(
          { error: ffmpegError instanceof Error ? ffmpegError.message : String(ffmpegError) },
          null,
          2
        )
      );

      return NextResponse.json(
        {
          success: false,
          error:
            "Failed to trim video. " +
            (ffmpegError instanceof Error ? ffmpegError.message : String(ffmpegError)),
        },
        { status: 500 }
      );
    }

    // Upload the trimmed video to S3
    const timestamp = Date.now();
    const videoKey = `projects/${projectId}/scenes/${sceneId}/videos/trimmed-${shotId}-${timestamp}.mp4`;
    const trimmedVideoUrl = await uploadFileFromBuffer(trimmedBuffer, videoKey, "video/mp4");

    // Generate thumbnail from trimmed video (at the middle)
    let thumbnailUrl: string | undefined;
    try {
      const ffmpeg = await import("fluent-ffmpeg").catch(() => null);
      if (ffmpeg) {
        const thumbnailBuffer = await extractThumbnailWithFfmpeg(
          trimmedBuffer,
          ffmpeg.default,
          effectiveDuration / 1000 / 2 // Middle of trimmed video
        );
        const thumbnailKey = `projects/${projectId}/scenes/${sceneId}/thumbnails/trimmed-${shotId}-${timestamp}.jpg`;
        thumbnailUrl = await uploadFileFromBuffer(thumbnailBuffer, thumbnailKey, "image/jpeg");
      }
    } catch (thumbError) {
      console.error("[video-trim] Thumbnail generation failed:", thumbError);
      // Continue without thumbnail
    }

    console.log(
      "[video-trim] Video trimmed and uploaded:",
      JSON.stringify({ videoKey, trimmedVideoUrl, thumbnailUrl }, null, 2)
    );

    return NextResponse.json({
      success: true,
      trimmedVideoUrl,
      thumbnailUrl,
      durationMs: effectiveDuration,
    });
  } catch (error) {
    console.error(
      "[video-trim] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );

    return NextResponse.json({ success: false, error: "Internal server error" }, { status: 500 });
  }
}

/**
 * Trim video using ffmpeg
 */
async function trimVideoWithFfmpeg(
  videoBuffer: Buffer,
  ffmpeg: typeof import("fluent-ffmpeg"),
  startSeconds: number,
  durationSeconds: number
): Promise<Buffer> {
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const { writeFile, unlink, readFile } = await import("node:fs/promises");
  const { randomUUID } = await import("node:crypto");

  // Write video to temp file
  const tempDir = tmpdir();
  const inputPath = join(tempDir, `input-${randomUUID()}.mp4`);
  const outputPath = join(tempDir, `output-${randomUUID()}.mp4`);

  await writeFile(inputPath, videoBuffer);

  return new Promise((resolve, reject) => {
    ffmpeg(inputPath)
      .setStartTime(startSeconds)
      .setDuration(durationSeconds)
      .videoCodec("libx264")
      .audioCodec("aac")
      .outputOptions(["-preset fast", "-crf 23", "-movflags +faststart"])
      .output(outputPath)
      .on("end", async () => {
        try {
          const outputBuffer = await readFile(outputPath);
          // Clean up temp files
          await unlink(inputPath).catch(() => {});
          await unlink(outputPath).catch(() => {});
          resolve(outputBuffer);
        } catch (readError) {
          reject(readError);
        }
      })
      .on("error", async (err: Error) => {
        // Clean up temp files
        await unlink(inputPath).catch(() => {});
        await unlink(outputPath).catch(() => {});
        reject(err);
      })
      .run();
  });
}

/**
 * Extract thumbnail from video using ffmpeg
 */
async function extractThumbnailWithFfmpeg(
  videoBuffer: Buffer,
  ffmpeg: typeof import("fluent-ffmpeg"),
  seekSeconds: number
): Promise<Buffer> {
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const { writeFile, unlink, readFile } = await import("node:fs/promises");
  const { randomUUID } = await import("node:crypto");

  const tempDir = tmpdir();
  const inputPath = join(tempDir, `thumb-input-${randomUUID()}.mp4`);
  const outputPath = join(tempDir, `thumb-output-${randomUUID()}.jpg`);

  await writeFile(inputPath, videoBuffer);

  return new Promise((resolve, reject) => {
    ffmpeg(inputPath)
      .seekInput(seekSeconds)
      .frames(1)
      .outputOptions(["-vf", "scale=320:-1"])
      .output(outputPath)
      .on("end", async () => {
        try {
          const outputBuffer = await readFile(outputPath);
          await unlink(inputPath).catch(() => {});
          await unlink(outputPath).catch(() => {});
          resolve(outputBuffer);
        } catch (readError) {
          reject(readError);
        }
      })
      .on("error", async (err: Error) => {
        await unlink(inputPath).catch(() => {});
        await unlink(outputPath).catch(() => {});
        reject(err);
      })
      .run();
  });
}
