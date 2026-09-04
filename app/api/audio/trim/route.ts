import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { uploadFileFromBuffer } from "@/lib/s3";

/**
 * POST /api/audio/trim
 *
 * Trim an audio file to specified in/out points.
 * Creates a new trimmed audio file and returns its URL.
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
    const { projectId, sceneId, trackId, audioUrl, trimStartMs, trimEndMs, durationMs } = body;

    if (!projectId || !sceneId || !trackId) {
      return NextResponse.json(
        { success: false, error: "Project ID, Scene ID, and Track ID are required" },
        { status: 400 }
      );
    }

    if (!audioUrl) {
      return NextResponse.json({ success: false, error: "Audio URL is required" }, { status: 400 });
    }

    if (trimStartMs === undefined && trimEndMs === undefined) {
      return NextResponse.json(
        { success: false, error: "At least one trim value (trimStartMs or trimEndMs) is required" },
        { status: 400 }
      );
    }

    const trimStart = trimStartMs || 0;
    const trimEnd = trimEndMs || 0;
    const fullDuration = durationMs || 5000;
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
      "[audio-trim] Starting trim:",
      JSON.stringify(
        {
          projectId,
          sceneId,
          trackId,
          trimStartMs: trimStart,
          trimEndMs: trimEnd,
          fullDuration,
          effectiveDuration,
          audioUrl: audioUrl.substring(0, 100),
        },
        null,
        2
      )
    );

    // Download the audio
    const audioResponse = await fetch(audioUrl);
    if (!audioResponse.ok) {
      return NextResponse.json({ success: false, error: "Failed to fetch audio" }, { status: 400 });
    }

    const audioBuffer = Buffer.from(await audioResponse.arrayBuffer());

    // Try to use ffmpeg for audio trimming
    let trimmedBuffer: Buffer;

    try {
      const ffmpeg = await import("fluent-ffmpeg").catch(() => null);

      if (ffmpeg) {
        trimmedBuffer = await trimAudioWithFfmpeg(
          audioBuffer,
          ffmpeg.default,
          trimStart / 1000, // Convert to seconds
          effectiveDuration / 1000 // Convert to seconds
        );
      } else {
        console.log("[audio-trim] ffmpeg not available");
        return NextResponse.json(
          {
            success: false,
            error: "Audio trimming requires ffmpeg which is not available in this environment.",
          },
          { status: 501 }
        );
      }
    } catch (ffmpegError) {
      console.error(
        "[audio-trim] ffmpeg error:",
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
            "Failed to trim audio. " +
            (ffmpegError instanceof Error ? ffmpegError.message : String(ffmpegError)),
        },
        { status: 500 }
      );
    }

    // Upload the trimmed audio to S3
    const timestamp = Date.now();
    const audioKey = `projects/${projectId}/scenes/${sceneId}/audios/trimmed-${trackId}-${timestamp}.mp3`;
    const trimmedAudioUrl = await uploadFileFromBuffer(trimmedBuffer, audioKey, "audio/mpeg");

    console.log(
      "[audio-trim] Audio trimmed and uploaded:",
      JSON.stringify({ audioKey, trimmedAudioUrl }, null, 2)
    );

    return NextResponse.json({
      success: true,
      trimmedAudioUrl,
      durationMs: effectiveDuration,
    });
  } catch (error) {
    console.error(
      "[audio-trim] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );

    return NextResponse.json({ success: false, error: "Internal server error" }, { status: 500 });
  }
}

/**
 * Trim audio using ffmpeg
 */
async function trimAudioWithFfmpeg(
  audioBuffer: Buffer,
  ffmpeg: typeof import("fluent-ffmpeg"),
  startSeconds: number,
  durationSeconds: number
): Promise<Buffer> {
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const { writeFile, unlink, readFile } = await import("node:fs/promises");
  const { randomUUID } = await import("node:crypto");

  // Determine input format from buffer magic bytes
  const isWav = audioBuffer[0] === 0x52 && audioBuffer[1] === 0x49; // "RI" for RIFF
  const isOgg = audioBuffer[0] === 0x4f && audioBuffer[1] === 0x67; // "Og" for Ogg
  const inputExt = isWav ? "wav" : isOgg ? "ogg" : "mp3";

  // Write audio to temp file
  const tempDir = tmpdir();
  const inputPath = join(tempDir, `input-${randomUUID()}.${inputExt}`);
  const outputPath = join(tempDir, `output-${randomUUID()}.mp3`);

  await writeFile(inputPath, audioBuffer);

  return new Promise((resolve, reject) => {
    ffmpeg(inputPath)
      .setStartTime(startSeconds)
      .setDuration(durationSeconds)
      .audioCodec("libmp3lame")
      .audioBitrate(192)
      .outputOptions([
        "-ar 44100", // Sample rate
        "-ac 2", // Stereo
      ])
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
