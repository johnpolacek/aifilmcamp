import { randomUUID } from "node:crypto";
import { mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import ffmpeg from "fluent-ffmpeg";
import { downloadFile } from "./downloader.js";
import { createJob, updateJob } from "./job-store.js";
import type { CompositionAudioTrack, CompositionRequest, CompositionResult } from "./types.js";
import { uploadToS3 } from "./uploader.js";

/**
 * Process a video composition request
 * Downloads source files, composites with FFmpeg, uploads result
 */
export async function processComposition(request: CompositionRequest): Promise<void> {
  const workDir = join("/tmp", `compose-${randomUUID()}`);

  // Initialize job tracking
  createJob(request.jobId);

  console.log(
    "[composer] Starting composition:",
    JSON.stringify(
      {
        jobId: request.jobId,
        workDir,
        shotCount: request.shots.length,
        audioTrackCount: request.audioTracks?.length || 0,
      },
      null,
      2
    )
  );

  try {
    await mkdir(workDir, { recursive: true });

    // 1. Download all source files
    const videoFiles: string[] = [];
    const sortedShots = request.shots.sort((a, b) => a.order - b.order);
    const totalDownloads =
      sortedShots.length + (request.audioTracks?.filter((t) => !t.muted).length || 0);
    let downloadedCount = 0;

    updateJob(request.jobId, {
      status: "downloading",
      stage: `Downloading files (0/${totalDownloads})`,
      progress: 0,
    });

    for (const shot of sortedShots) {
      const localPath = join(workDir, `shot-${shot.order}.mp4`);
      await downloadFile(shot.videoUrl, localPath);
      videoFiles.push(localPath);
      downloadedCount++;
      updateJob(request.jobId, {
        stage: `Downloading files (${downloadedCount}/${totalDownloads})`,
        progress: Math.round((downloadedCount / totalDownloads) * 20), // Downloads are 0-20%
      });
    }

    const audioFiles: { path: string; track: CompositionAudioTrack }[] = [];
    for (const track of request.audioTracks || []) {
      if (!track.muted) {
        const localPath = join(workDir, `audio-${track.id}.mp3`);
        await downloadFile(track.sourceUrl, localPath);
        audioFiles.push({ path: localPath, track });
        downloadedCount++;
        updateJob(request.jobId, {
          stage: `Downloading files (${downloadedCount}/${totalDownloads})`,
          progress: Math.round((downloadedCount / totalDownloads) * 20),
        });
      }
    }

    console.log(
      "[composer] Downloads complete:",
      JSON.stringify(
        {
          videoFiles: videoFiles.length,
          audioFiles: audioFiles.length,
        },
        null,
        2
      )
    );

    // 2. Compose with FFmpeg
    updateJob(request.jobId, {
      status: "processing",
      stage: "Compositing video...",
      progress: 20,
    });

    const outputPath = join(workDir, "output.mp4");
    await composeWithFfmpeg(request, videoFiles, audioFiles, outputPath);

    console.log("[composer] FFmpeg composition complete");

    // 3. Generate thumbnail
    updateJob(request.jobId, {
      stage: "Generating thumbnail...",
      progress: 90,
    });

    const thumbnailPath = join(workDir, "thumbnail.jpg");
    await generateThumbnail(outputPath, thumbnailPath);

    console.log("[composer] Thumbnail generated");

    // 4. Upload to S3
    updateJob(request.jobId, {
      status: "uploading",
      stage: "Uploading to cloud...",
      progress: 92,
    });

    const timestamp = Date.now();
    const videoKey = `projects/${request.projectId}/scenes/${request.sceneId}/composite-${timestamp}.mp4`;
    const thumbKey = `projects/${request.projectId}/scenes/${request.sceneId}/composite-thumb-${timestamp}.jpg`;

    const [videoUrl, thumbnailUrl] = await Promise.all([
      uploadToS3(outputPath, videoKey, "video/mp4"),
      uploadToS3(thumbnailPath, thumbKey, "image/jpeg"),
    ]);

    // 5. Get duration
    const durationMs = await getVideoDuration(outputPath);

    updateJob(request.jobId, {
      status: "completed",
      stage: "Complete!",
      progress: 100,
    });

    console.log(
      "[composer] Composition complete:",
      JSON.stringify(
        {
          jobId: request.jobId,
          videoUrl,
          thumbnailUrl,
          durationMs,
        },
        null,
        2
      )
    );

    // 6. Notify via webhook
    await sendWebhook(request.webhookUrl, {
      jobId: request.jobId,
      status: "completed",
      videoUrl,
      thumbnailUrl,
      durationMs,
    });
  } catch (error) {
    console.error(
      "[composer] Composition failed:",
      JSON.stringify(
        {
          jobId: request.jobId,
          error: error instanceof Error ? error.message : String(error),
          stack: error instanceof Error ? error.stack : undefined,
        },
        null,
        2
      )
    );

    updateJob(request.jobId, {
      status: "failed",
      stage: "Failed",
      error: error instanceof Error ? error.message : "Unknown error",
    });

    await sendWebhook(request.webhookUrl, {
      jobId: request.jobId,
      status: "failed",
      error: error instanceof Error ? error.message : "Unknown error",
    });
  } finally {
    // Cleanup
    await rm(workDir, { recursive: true, force: true }).catch(() => {});
  }
}

/**
 * Compose videos and audio using FFmpeg
 */
async function composeWithFfmpeg(
  request: CompositionRequest,
  videoFiles: string[],
  audioFiles: { path: string; track: CompositionAudioTrack }[],
  outputPath: string
): Promise<void> {
  const { jobId } = request;
  const shots = request.shots.sort((a, b) => a.order - b.order);

  // Probe actual video durations for accurate fade timing
  const actualDurations: number[] = [];
  for (const videoFile of videoFiles) {
    try {
      const durationMs = await getVideoDuration(videoFile);
      actualDurations.push(durationMs);
    } catch (err) {
      console.error(
        "[composer] Failed to probe video duration:",
        JSON.stringify(
          { videoFile, error: err instanceof Error ? err.message : String(err) },
          null,
          2
        )
      );
      actualDurations.push(0); // Will fall back to shot.durationMs
    }
  }

  console.log("[composer] Probed video durations:", JSON.stringify({ actualDurations }, null, 2));

  // Calculate total video duration for audio track positioning
  let _totalVideoDurationMs = 0;
  for (const shot of shots) {
    const effectiveDuration = shot.durationMs - shot.trimStartMs - shot.trimEndMs;
    _totalVideoDurationMs += effectiveDuration;
  }

  return new Promise((resolve, reject) => {
    const command = ffmpeg();

    // Add video inputs
    shots.forEach((_, i) => {
      command.input(videoFiles[i]);
    });

    // Add audio inputs
    audioFiles.forEach(({ path }) => {
      command.input(path);
    });

    // Build filter complex
    const filters: string[] = [];
    const videoLabels: string[] = [];
    const audioLabels: string[] = [];

    // Process each video shot
    shots.forEach((shot, i) => {
      const trimStart = shot.trimStartMs / 1000;
      const storedDuration = (shot.durationMs - shot.trimStartMs - shot.trimEndMs) / 1000;

      // Use actual probed duration if available, otherwise fall back to stored duration
      const actualDurationMs = actualDurations[i] || shot.durationMs;
      const actualDuration = actualDurationMs / 1000;

      // For fade calculations, use the smaller of stored vs actual to be safe
      // This ensures fade out starts early enough to complete before video ends
      const needsTrim = shot.trimStartMs > 0 || shot.trimEndMs > 0;
      const effectiveDuration = needsTrim
        ? storedDuration
        : Math.min(storedDuration, actualDuration);

      const vLabel = `v${i}`;
      const aLabel = `a${i}`;
      const fadeDuration = (shot.fadeDurationMs || 500) / 1000;
      const fadeInType = shot.fadeInType || "none";
      const fadeOutType = shot.fadeOutType || "none";

      console.log(
        "[composer] Processing shot fade effects:",
        JSON.stringify(
          {
            shotId: shot.id,
            order: shot.order,
            durationMs: shot.durationMs,
            actualDurationMs,
            trimStartMs: shot.trimStartMs,
            trimEndMs: shot.trimEndMs,
            storedDuration,
            actualDuration,
            effectiveDuration,
            needsTrim,
            fadeInType,
            fadeOutType,
            fadeDurationMs: shot.fadeDurationMs,
            fadeDurationSeconds: fadeDuration,
          },
          null,
          2
        )
      );

      // Build video filter chain
      // When trim values are 0, skip the trim filter to avoid issues with already-trimmed videos
      let videoFilter = needsTrim
        ? `[${i}:v]trim=start=${trimStart}:duration=${storedDuration},setpts=PTS-STARTPTS,format=yuv420p`
        : `[${i}:v]setpts=PTS-STARTPTS,format=yuv420p`;

      // Apply fade in if needed
      if (fadeInType !== "none") {
        const color = fadeInType === "white" ? ":c=white" : "";
        videoFilter += `,fade=t=in:st=0:d=${fadeDuration}${color}`;
      }

      // Apply fade out if needed
      if (fadeOutType !== "none") {
        // Use effective duration (actual video duration) for fade out timing
        // This ensures the fade actually appears at the end of the video
        const fadeOutStart = Math.max(0, effectiveDuration - fadeDuration);
        const color = fadeOutType === "white" ? ":c=white" : "";
        videoFilter += `,fade=t=out:st=${fadeOutStart}:d=${fadeDuration}${color}`;
        console.log(
          "[composer] Fade out filter:",
          JSON.stringify(
            {
              needsTrim,
              storedDuration,
              actualDuration,
              effectiveDuration,
              fadeOutStart,
              fadeDuration,
              color: color || "black",
              filterPart: `fade=t=out:st=${fadeOutStart}:d=${fadeDuration}${color}`,
            },
            null,
            2
          )
        );
      }

      videoFilter += `[${vLabel}]`;
      filters.push(videoFilter);

      // Handle video audio - use effectiveDuration to match the video output
      const audioDuration = needsTrim ? storedDuration : effectiveDuration;
      if (shot.audioMuted) {
        // Generate silent audio matching video duration
        filters.push(
          `anullsrc=channel_layout=stereo:sample_rate=44100,atrim=duration=${audioDuration}[${aLabel}]`
        );
      } else {
        // Trim audio from video
        filters.push(
          `[${i}:a]atrim=start=${trimStart}:duration=${audioDuration},asetpts=PTS-STARTPTS,aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[${aLabel}]`
        );
      }

      videoLabels.push(`[${vLabel}]`);
      audioLabels.push(`[${aLabel}]`);
    });

    // Concatenate all video segments
    const concatVideoInput = videoLabels.join("");
    const concatAudioInput = audioLabels.join("");
    filters.push(`${concatVideoInput}concat=n=${shots.length}:v=1:a=0[outv]`);
    filters.push(`${concatAudioInput}concat=n=${shots.length}:v=0:a=1[concat_audio]`);

    // Handle additional audio tracks (overlay on concatenated video audio)
    if (audioFiles.length > 0) {
      // Process each audio track with proper timing
      const audioTrackLabels: string[] = ["[concat_audio]"];

      audioFiles.forEach(({ track }, i) => {
        const inputIndex = shots.length + i;
        const startSeconds = track.startTimeMs / 1000;
        const trimStartSeconds = track.trimStartMs / 1000;
        const durationSeconds = track.durationMs / 1000;
        const trackLabel = `at${i}`;

        // Delay and trim the audio track
        // Use precise millisecond values without rounding to prevent sync drift
        const delayMs = startSeconds * 1000;
        filters.push(
          `[${inputIndex}:a]atrim=start=${trimStartSeconds}:duration=${durationSeconds},asetpts=PTS-STARTPTS,adelay=${delayMs}|${delayMs},volume=${track.volume}[${trackLabel}]`
        );
        audioTrackLabels.push(`[${trackLabel}]`);
      });

      // Mix all audio tracks together
      filters.push(
        `${audioTrackLabels.join("")}amix=inputs=${audioTrackLabels.length}:duration=longest:dropout_transition=0[mixed_audio]`
      );

      // Apply master volume to mixed audio
      const masterVolume = request.masterVolume ?? 1.0;
      if (masterVolume !== 1.0) {
        filters.push(`[mixed_audio]volume=${masterVolume}[outa]`);
      } else {
        filters.push(`[mixed_audio]acopy[outa]`);
      }
    } else {
      // No additional audio tracks, just use concatenated audio
      // Apply master volume to concatenated audio
      const masterVolume = request.masterVolume ?? 1.0;
      if (masterVolume !== 1.0) {
        filters.push(`[concat_audio]volume=${masterVolume}[outa]`);
      } else {
        filters.push(`[concat_audio]acopy[outa]`);
      }
    }

    console.log("[composer] FFmpeg filter complex:", JSON.stringify({ filters }, null, 2));

    command
      .complexFilter(filters)
      .outputOptions([
        "-map",
        "[outv]",
        "-map",
        "[outa]",
        "-c:v",
        "libx264",
        "-preset",
        "fast",
        "-crf",
        "23",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-movflags",
        "+faststart",
        "-y", // Overwrite output file
      ])
      .output(outputPath)
      .on("start", (commandLine) => {
        console.log("[composer] FFmpeg command:", JSON.stringify({ commandLine }, null, 2));
      })
      .on("progress", (progress) => {
        if (progress.percent) {
          // FFmpeg progress can go over 100% due to audio processing
          // Normalize to 20-90% range (downloads are 0-20%, upload is 90-100%)
          const normalizedProgress = Math.min(100, progress.percent);
          const mappedProgress = 20 + Math.round((normalizedProgress / 100) * 70);
          console.log(
            `[composer] Progress: ${Math.round(progress.percent)}% (mapped: ${mappedProgress}%)`
          );
          updateJob(jobId, {
            stage: `Encoding video... ${Math.min(100, Math.round(progress.percent))}%`,
            progress: mappedProgress,
          });
        }
      })
      .on("end", () => resolve())
      .on("error", (err, stdout, stderr) => {
        console.error(
          "[composer] FFmpeg error:",
          JSON.stringify(
            {
              error: err.message,
              stdout,
              stderr,
            },
            null,
            2
          )
        );
        reject(err);
      })
      .run();
  });
}

/**
 * Generate a thumbnail from the video
 */
async function generateThumbnail(videoPath: string, outputPath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    ffmpeg(videoPath)
      .seekInput(1) // 1 second in
      .frames(1)
      .outputOptions(["-vf", "scale=640:-1"])
      .output(outputPath)
      .on("end", () => resolve())
      .on("error", reject)
      .run();
  });
}

/**
 * Get video duration in milliseconds
 */
async function getVideoDuration(videoPath: string): Promise<number> {
  return new Promise((resolve, reject) => {
    ffmpeg.ffprobe(videoPath, (err, metadata) => {
      if (err) reject(err);
      else resolve(Math.round((metadata.format.duration || 0) * 1000));
    });
  });
}

/**
 * Send webhook notification
 */
async function sendWebhook(url: string, result: CompositionResult): Promise<void> {
  console.log("[composer] Sending webhook:", JSON.stringify({ url, result }, null, 2));

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(result),
    });

    if (!response.ok) {
      console.error(
        "[composer] Webhook failed:",
        JSON.stringify(
          {
            status: response.status,
            statusText: response.statusText,
          },
          null,
          2
        )
      );
    } else {
      console.log("[composer] Webhook sent successfully");
    }
  } catch (error) {
    console.error(
      "[composer] Webhook error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );
  }
}
