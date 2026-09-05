import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { analyzeReferenceImages, generateImage } from "@/lib/ai/gemini";
import { uploadImageFromBuffer } from "@/lib/s3";

export async function POST(request: Request) {
  try {
    // Check authentication
    const { userId } = await auth();
    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    // Parse request body
    const body = await request.json();
    const { prompt, projectId, sceneId, aspectRatio = "16:9", referenceImages } = body;

    if (!prompt) {
      return NextResponse.json({ success: false, error: "Prompt is required" }, { status: 400 });
    }

    if (!projectId || !sceneId) {
      return NextResponse.json(
        { success: false, error: "Project ID and Scene ID are required" },
        { status: 400 }
      );
    }

    // Build the enhanced prompt
    let enhancedPrompt = prompt;

    // If reference images are provided, analyze them and enhance the prompt
    if (referenceImages && Array.isArray(referenceImages) && referenceImages.length > 0) {
      console.log(
        "[generate-image] Analyzing reference images:",
        JSON.stringify({ count: referenceImages.length }, null, 2)
      );

      const analysisResult = await analyzeReferenceImages(referenceImages);
      if (analysisResult.success && analysisResult.description) {
        // Prepend the style description to the prompt
        enhancedPrompt = `Style reference: ${analysisResult.description}\n\nGenerate: ${prompt}`;
        console.log(
          "[generate-image] Enhanced prompt with reference analysis:",
          JSON.stringify({ enhancedPrompt: enhancedPrompt.substring(0, 200) }, null, 2)
        );
      }
    }

    console.log(
      "[generate-image] Starting image generation:",
      JSON.stringify(
        { prompt: enhancedPrompt.substring(0, 100), projectId, sceneId, aspectRatio },
        null,
        2
      )
    );

    // Generate image using Gemini
    const result = await generateImage({
      prompt: enhancedPrompt,
      aspectRatio,
      numberOfImages: 1,
    });

    if (!result.success || !result.images || result.images.length === 0) {
      console.error(
        "[generate-image] Generation failed:",
        JSON.stringify({ error: result.error }, null, 2)
      );
      return NextResponse.json(
        { success: false, error: result.error || "Failed to generate image" },
        { status: 500 }
      );
    }

    // Upload image to S3
    const imageId = `img-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
    const imageBuffer = Buffer.from(result.images[0].base64, "base64");
    const imageKey = `generated/images/${projectId}/${sceneId}/${imageId}.png`;

    const imageUrl = await uploadImageFromBuffer(imageBuffer, imageKey);

    console.log(
      "[generate-image] Image uploaded successfully:",
      JSON.stringify({ imageId, imageUrl }, null, 2)
    );

    return NextResponse.json({
      success: true,
      image: {
        id: imageId,
        prompt,
        imageUrl,
        model: "imagen-3" as const,
        createdAt: new Date().toISOString(),
      },
    });
  } catch (error) {
    console.error(
      "[generate-image] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );

    return NextResponse.json({ success: false, error: "Internal server error" }, { status: 500 });
  }
}
