import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { generateVideo } from "@/lib/ai/gemini";
import type { GenerationMode } from "@/lib/scenes";
import { isVideoGenerationEnabled } from "@/lib/utils/video-generation";

/**
 * POST /api/ai/generate-video
 *
 * Generate a video using Veo 3.1 with support for multiple generation modes:
 * - text-only: Generate from text prompt only
 * - start-frame: Generate from start frame image + prompt
 * - start-end-frame: Generate from start and end frame images + prompt
 * - reference-images: Generate using up to 3 reference images + prompt
 *
 * NOTE: This endpoint is only available in development/localhost environments
 */
export async function POST(request: Request) {
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

    // Parse request body
    const body = await request.json();
    const {
      prompt,
      projectId,
      sceneId,
      shotId, // Optional - for shot-based workflow
      aspectRatio = "16:9",
      durationSeconds = 8,
      // Generation mode configuration
      generationMode = "text-only" as GenerationMode,
      startFrameImage,
      endFrameImage,
      referenceImages,
    } = body;

    if (!prompt) {
      return NextResponse.json({ success: false, error: "Prompt is required" }, { status: 400 });
    }

    if (!projectId || !sceneId) {
      return NextResponse.json(
        { success: false, error: "Project ID and Scene ID are required" },
        { status: 400 }
      );
    }

    // Validate generation mode requirements
    if (generationMode === "start-frame" && !startFrameImage) {
      return NextResponse.json(
        { success: false, error: "Start frame image is required for start-frame generation mode" },
        { status: 400 }
      );
    }

    if (generationMode === "start-end-frame" && (!startFrameImage || !endFrameImage)) {
      return NextResponse.json(
        {
          success: false,
          error: "Start and end frame images are required for start-end-frame generation mode",
        },
        { status: 400 }
      );
    }

    if (
      generationMode === "reference-images" &&
      (!referenceImages || referenceImages.length === 0)
    ) {
      return NextResponse.json(
        {
          success: false,
          error: "At least one reference image is required for reference-images generation mode",
        },
        { status: 400 }
      );
    }

    console.log(
      "[generate-video] Starting Veo 3.1 video generation:",
      JSON.stringify(
        {
          prompt: prompt.substring(0, 100),
          projectId,
          sceneId,
          shotId,
          aspectRatio,
          durationSeconds,
          generationMode,
          hasStartFrame: !!startFrameImage,
          hasEndFrame: !!endFrameImage,
          referenceCount: referenceImages?.length || 0,
        },
        null,
        2
      )
    );

    // Start video generation (async - returns job ID)
    const result = await generateVideo({
      prompt,
      aspectRatio,
      durationSeconds,
      generationMode,
      startFrameImage,
      endFrameImage,
      referenceImages,
    });

    if (!result.success) {
      console.error(
        "[generate-video] Generation failed:",
        JSON.stringify({ error: result.error }, null, 2)
      );
      return NextResponse.json(
        { success: false, error: result.error || "Failed to start video generation" },
        { status: 500 }
      );
    }

    // Create video record with predictable IDs
    const timestamp = Date.now();
    const randomSuffix = Math.random().toString(36).substring(2, 9);
    const videoId = `vid-${timestamp}-${randomSuffix}`;

    // Generate predictable thumbnail ID upfront - this is what frontend will poll for
    // S3 Path Convention: projects/{projectId}/scenes/{sceneId}/thumbnails/{filename}
    const thumbnailId = `thumb-${timestamp}-${randomSuffix}`;
    const thumbnailPath = `projects/${projectId}/scenes/${sceneId}/thumbnails/${thumbnailId}.jpg`;

    // Build the full thumbnail URL that frontend will check
    const s3Bucket = process.env.AWS_S3_BUCKET || "aifilmcamp-public";
    const cloudfrontDomain = process.env.CLOUDFRONT_DOMAIN;
    const thumbnailUrl = cloudfrontDomain
      ? `https://${cloudfrontDomain}/${thumbnailPath}`
      : `https://${s3Bucket}.s3.amazonaws.com/${thumbnailPath}`;

    console.log(
      "[generate-video] Video generation started:",
      JSON.stringify(
        {
          videoId,
          operationId: result.videoId,
          generationMode,
          thumbnailId,
          thumbnailUrl,
        },
        null,
        2
      )
    );

    return NextResponse.json({
      success: true,
      video: {
        id: videoId,
        prompt,
        operationId: result.videoId, // The operation ID for polling
        model: "veo-3.1" as const,
        status: "processing" as const,
        generationMode,
        createdAt: new Date().toISOString(),
      },
      // Predictable thumbnail URL for frontend to poll
      thumbnailId,
      thumbnailUrl,
      thumbnailPath,
      // Include shotId if provided for client-side tracking
      shotId,
    });
  } catch (error) {
    console.error(
      "[generate-video] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );

    return NextResponse.json({ success: false, error: "Internal server error" }, { status: 500 });
  }
}
