import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { uploadFileFromBuffer } from "@/lib/s3";

/**
 * POST /api/audio/extract
 *
 * Extract audio from a video file.
 * Note: This requires ffmpeg to be available in the environment.
 * In serverless environments, consider using a cloud-based transcoding service.
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
    const { projectId, sceneId, shotId, videoUrl } = body;

    if (!projectId || !sceneId || !shotId) {
      return NextResponse.json(
        { success: false, error: "Project ID, Scene ID, and Shot ID are required" },
        { status: 400 }
      );
    }

    if (!videoUrl) {
      return NextResponse.json({ success: false, error: "Video URL is required" }, { status: 400 });
    }

    console.log(
      "[audio-extract] Starting extraction:",
      JSON.stringify({ projectId, sceneId, shotId, videoUrl: videoUrl.substring(0, 100) }, null, 2)
    );

    // Download the video
    const videoResponse = await fetch(videoUrl);
    if (!videoResponse.ok) {
      return NextResponse.json({ success: false, error: "Failed to fetch video" }, { status: 400 });
    }

    const videoBuffer = Buffer.from(await videoResponse.arrayBuffer());

    // Try to use ffmpeg for audio extraction
    // In serverless environments, you may need to use a different approach
    let audioBuffer: Buffer;

    try {
      // Attempt to use fluent-ffmpeg if available
      const ffmpeg = await import("fluent-ffmpeg").catch(() => null);

      if (ffmpeg) {
        // Use ffmpeg to extract audio
        audioBuffer = await extractAudioWithFfmpeg(videoBuffer, ffmpeg.default);
      } else {
        // Fallback: Return the video URL and let the client handle audio
        // In a production environment, you would use a cloud transcoding service
        console.log("[audio-extract] ffmpeg not available, using fallback");

        // For now, we'll store the video as "audio" source
        // The client can use the video's audio track directly
        const _audioKey = `audio/${projectId}/${sceneId}/${shotId}-extracted.mp3`;

        // Since we can't extract audio without ffmpeg,
        // we'll return an error suggesting the user upload audio directly
        return NextResponse.json(
          {
            success: false,
            error: "Audio extraction requires ffmpeg. Please upload an audio file directly.",
            fallbackVideoUrl: videoUrl,
          },
          { status: 501 }
        );
      }
    } catch (ffmpegError) {
      console.error(
        "[audio-extract] ffmpeg error:",
        JSON.stringify(
          { error: ffmpegError instanceof Error ? ffmpegError.message : String(ffmpegError) },
          null,
          2
        )
      );

      return NextResponse.json(
        {
          success: false,
          error: "Failed to extract audio. Please upload an audio file directly.",
        },
        { status: 500 }
      );
    }

    // Upload the extracted audio to S3
    const audioKey = `audio/${projectId}/${sceneId}/${shotId}-extracted.mp3`;
    const audioUrl = await uploadFileFromBuffer(audioBuffer, audioKey, "audio/mpeg");

    console.log(
      "[audio-extract] Audio extracted and uploaded:",
      JSON.stringify({ audioKey, audioUrl }, null, 2)
    );

    return NextResponse.json({
      success: true,
      audioUrl,
      sourceVideoShotId: shotId,
    });
  } catch (error) {
    console.error(
      "[audio-extract] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );

    return NextResponse.json({ success: false, error: "Internal server error" }, { status: 500 });
  }
}

/**
 * Extract audio from video using ffmpeg
 */
async function extractAudioWithFfmpeg(
  videoBuffer: Buffer,
  ffmpeg: typeof import("fluent-ffmpeg")
): Promise<Buffer> {
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const { writeFile, unlink, readFile } = await import("node:fs/promises");
  const { randomUUID } = await import("node:crypto");

  // Write video to temp file
  const tempDir = tmpdir();
  const videoPath = join(tempDir, `video-${randomUUID()}.mp4`);
  const audioPath = join(tempDir, `audio-${randomUUID()}.mp3`);

  await writeFile(videoPath, videoBuffer);

  return new Promise((resolve, reject) => {
    ffmpeg(videoPath)
      .noVideo()
      .audioCodec("libmp3lame")
      .audioBitrate(128)
      .output(audioPath)
      .on("end", async () => {
        try {
          const audioBuffer = await readFile(audioPath);
          // Clean up temp files
          await unlink(videoPath).catch(() => {});
          await unlink(audioPath).catch(() => {});
          resolve(audioBuffer);
        } catch (readError) {
          reject(readError);
        }
      })
      .on("error", async (err: Error) => {
        // Clean up temp files
        await unlink(videoPath).catch(() => {});
        await unlink(audioPath).catch(() => {});
        reject(err);
      })
      .run();
  });
}
