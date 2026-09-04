import { google } from "@ai-sdk/google";
import { generateImage as aiGenerateImage } from "ai";
import { GoogleAuth } from "google-auth-library";
import type { GenerationMode } from "@/lib/scenes";
import { isVideoGenerationEnabled } from "@/lib/utils/video-generation";

/**
 * Google Gemini AI Service
 * Uses Vercel AI SDK for image generation
 * Uses Vertex AI REST API for Veo 3.1 video generation (supports service account auth)
 */

// Initialize Google Auth client (lazy initialization)
let authClient: GoogleAuth | null = null;

function getAuthClient(): GoogleAuth {
  if (!authClient) {
    // Check if we have service account key as JSON string (works for both local and production)
    const serviceAccountKey = process.env.GOOGLE_SERVICE_ACCOUNT_KEY;

    if (serviceAccountKey) {
      // Parse JSON string and use it directly
      try {
        const keyData = JSON.parse(serviceAccountKey);
        authClient = new GoogleAuth({
          credentials: keyData,
          scopes: ["https://www.googleapis.com/auth/cloud-platform"],
        });
      } catch (error) {
        console.error(
          "[getAuthClient] Failed to parse GOOGLE_SERVICE_ACCOUNT_KEY:",
          JSON.stringify({ error }, null, 2)
        );
        throw new Error("Invalid GOOGLE_SERVICE_ACCOUNT_KEY format");
      }
    } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      // Fallback: Use file path (local development only)
      authClient = new GoogleAuth({
        keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
        scopes: ["https://www.googleapis.com/auth/cloud-platform"],
      });
    } else {
      // Fallback: Try Application Default Credentials (if running on GCP)
      authClient = new GoogleAuth({
        scopes: ["https://www.googleapis.com/auth/cloud-platform"],
      });
    }
  }
  return authClient;
}

// ============================================================================
// IMAGE GENERATION TYPES
// ============================================================================

/**
 * Image generation options
 */
export interface ImageGenerationOptions {
  prompt: string;
  aspectRatio?: "1:1" | "16:9" | "9:16" | "4:3" | "3:4";
  numberOfImages?: number;
}

/**
 * Image generation result
 */
export interface ImageGenerationResult {
  success: boolean;
  images?: Array<{
    base64: string;
    mimeType: string;
  }>;
  error?: string;
}

// ============================================================================
// VIDEO GENERATION TYPES (Veo 3.1)
// ============================================================================

/**
 * Video generation options for Veo 3.1
 * Supports multiple generation modes:
 * - text-only: Generate from text prompt only
 * - start-frame: Generate from start frame image + prompt
 * - start-end-frame: Generate from start and end frame images + prompt
 * - reference-images: Generate using up to 3 reference images + prompt
 */
export interface VideoGenerationOptions {
  prompt: string;
  aspectRatio?: "16:9" | "9:16";
  durationSeconds?: 4 | 6 | 8;

  // Generation mode
  generationMode?: GenerationMode;

  // Image inputs based on mode
  startFrameImage?: string; // Base64 or URL for start frame
  endFrameImage?: string; // Base64 or URL for end frame
  referenceImages?: string[]; // Up to 3 reference images (base64 or URL)
}

/**
 * Video generation result
 */
export interface VideoGenerationResult {
  success: boolean;
  videoId?: string; // Job ID for polling
  videoUrl?: string;
  videoBase64?: string; // Base64-encoded video data (Veo 3.1 default response)
  status?: "pending" | "processing" | "completed" | "failed";
  durationMs?: number;
  error?: string;
}

// ============================================================================
// IMAGE ANALYSIS (for reference-based generation)
// ============================================================================

/**
 * Analyze reference images and generate a style/content description
 * Uses Gemini's vision capabilities to understand the images via Vertex AI
 */
export async function analyzeReferenceImages(
  imageUrls: string[]
): Promise<{ success: boolean; description?: string; error?: string }> {
  if (!imageUrls || imageUrls.length === 0) {
    return { success: false, error: "No images provided" };
  }

  try {
    const projectId = process.env.GOOGLE_CLOUD_PROJECT_ID;
    const location = process.env.GOOGLE_CLOUD_LOCATION || "us-central1";

    if (!projectId) {
      return { success: false, error: "GOOGLE_CLOUD_PROJECT_ID not configured" };
    }

    // Get authenticated client
    const auth = getAuthClient();
    const client = await auth.getClient();
    const accessToken = await client.getAccessToken();

    if (!accessToken.token) {
      return { success: false, error: "Failed to obtain access token" };
    }

    // Prepare images for Gemini
    const imageParts = await Promise.all(
      imageUrls.slice(0, 3).map(async (url) => {
        const response = await fetch(url);
        if (!response.ok) {
          throw new Error(`Failed to fetch image: ${url}`);
        }
        const buffer = await response.arrayBuffer();
        const base64 = Buffer.from(buffer).toString("base64");
        const mimeType = response.headers.get("content-type") || "image/png";
        return {
          inlineData: {
            mimeType,
            data: base64,
          },
        };
      })
    );

    // Call Gemini via Vertex AI to analyze the images
    const endpoint = `https://${location}-aiplatform.googleapis.com/v1/projects/${projectId}/locations/${location}/publishers/google/models/gemini-2.0-flash:generateContent`;

    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              ...imageParts,
              {
                text: `Analyze these reference images and provide a concise description (2-3 sentences) that captures:
1. The visual style (lighting, color palette, artistic style)
2. Key character/subject details (appearance, clothing, features)
3. The overall mood and atmosphere

Format your response as a brief style guide that could be used to generate a similar image. Start directly with the description, no preamble.`,
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.3,
          maxOutputTokens: 200,
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        "[analyzeReferenceImages] Vertex AI error:",
        JSON.stringify({ status: response.status, error: errorText }, null, 2)
      );
      return { success: false, error: "Failed to analyze images" };
    }

    const data = await response.json();
    const description = data.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!description) {
      return { success: false, error: "No description generated" };
    }

    console.log(
      "[analyzeReferenceImages] Generated description:",
      JSON.stringify({ description: description.substring(0, 100) }, null, 2)
    );

    return { success: true, description: description.trim() };
  } catch (error) {
    console.error(
      "[analyzeReferenceImages] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );
    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to analyze images",
    };
  }
}

/**
 * Generate an image using Google Gemini (Imagen 3 / Nano Banana Pro)
 * Uses Vercel AI SDK's generateImage
 */
export async function generateImage(
  options: ImageGenerationOptions
): Promise<ImageGenerationResult> {
  const { prompt, aspectRatio = "16:9", numberOfImages = 1 } = options;

  if (!prompt) {
    return { success: false, error: "Prompt is required" };
  }

  try {
    // Use Vercel AI SDK with Google provider
    // Note: Using imagen-3.0-generate-002 for image generation
    const result = await aiGenerateImage({
      model: google.image("imagen-3.0-generate-002"),
      prompt,
      n: numberOfImages,
      aspectRatio,
    });

    if (!result.images || result.images.length === 0) {
      return { success: false, error: "No images generated" };
    }

    const images = result.images.map((img) => ({
      base64: img.base64,
      mimeType: "image/png",
    }));

    return {
      success: true,
      images,
    };
  } catch (error) {
    console.error(
      "[generateImage] Error:",
      JSON.stringify(
        {
          error: error instanceof Error ? error.message : String(error),
          prompt: prompt.substring(0, 100),
        },
        null,
        2
      )
    );

    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to generate image",
    };
  }
}

/**
 * Convert image URL or base64 to the format expected by Veo API
 */
async function prepareImageForVeo(
  imageInput: string
): Promise<{ mimeType: string; data: string } | null> {
  try {
    // If it's already base64 data
    if (imageInput.startsWith("data:")) {
      const matches = imageInput.match(/^data:([^;]+);base64,(.+)$/);
      if (matches) {
        return {
          mimeType: matches[1],
          data: matches[2],
        };
      }
    }

    // If it's a URL, fetch and convert to base64
    if (imageInput.startsWith("http://") || imageInput.startsWith("https://")) {
      const response = await fetch(imageInput);
      if (!response.ok) {
        console.error(
          "[prepareImageForVeo] Failed to fetch image:",
          JSON.stringify({ url: imageInput }, null, 2)
        );
        return null;
      }
      const buffer = await response.arrayBuffer();
      const base64 = Buffer.from(buffer).toString("base64");
      const contentType = response.headers.get("content-type") || "image/png";
      return {
        mimeType: contentType,
        data: base64,
      };
    }

    // Assume it's raw base64
    return {
      mimeType: "image/png",
      data: imageInput,
    };
  } catch (error) {
    console.error(
      "[prepareImageForVeo] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );
    return null;
  }
}

/**
 * Generate a video using Google Veo 3.1 via Vertex AI REST API
 * Uses v1beta1 endpoint for predictLongRunning (async generation)
 * Returns operation name for status polling
 *
 * Supports multiple generation modes:
 * - text-only: Generate from text prompt only
 * - start-frame: Generate from start frame image + prompt
 * - reference-images: Generate using up to 3 reference images + prompt
 */
export async function generateVideo(
  options: VideoGenerationOptions
): Promise<VideoGenerationResult> {
  const {
    prompt,
    aspectRatio = "16:9",
    durationSeconds = 8,
    generationMode = "text-only",
    startFrameImage,
    endFrameImage,
    referenceImages,
  } = options;

  if (!prompt) {
    return { success: false, error: "Prompt is required" };
  }

  // Safety check: Only allow video generation in development/localhost
  if (!isVideoGenerationEnabled()) {
    return { success: false, error: "Video generation is only available in development mode" };
  }

  try {
    const projectId = process.env.GOOGLE_CLOUD_PROJECT_ID;
    const location = process.env.GOOGLE_CLOUD_LOCATION || "us-central1";

    if (!projectId) {
      return { success: false, error: "GOOGLE_CLOUD_PROJECT_ID not configured" };
    }

    // Get authenticated client using service account
    const auth = getAuthClient();
    const client = await auth.getClient();
    const accessToken = await client.getAccessToken();

    if (!accessToken.token) {
      return { success: false, error: "Failed to obtain access token" };
    }

    // Note: When using reference images, duration MUST be 8 seconds per API docs
    const effectiveDuration = generationMode === "reference-images" ? 8 : durationSeconds;

    // Build Vertex AI request payload in instances/parameters format
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const instance: any = {
      prompt,
    };

    // Add images based on generation mode
    if (generationMode === "start-frame" && startFrameImage) {
      const preparedImage = await prepareImageForVeo(startFrameImage);
      if (preparedImage) {
        instance.image = {
          bytesBase64Encoded: preparedImage.data,
          mimeType: preparedImage.mimeType,
        };
      }
    } else if (generationMode === "start-end-frame" && startFrameImage) {
      const preparedStartImage = await prepareImageForVeo(startFrameImage);
      if (preparedStartImage) {
        instance.image = {
          bytesBase64Encoded: preparedStartImage.data,
          mimeType: preparedStartImage.mimeType,
        };
      }
      if (endFrameImage) {
        console.log(
          "[generateVideo] Warning: End frame support may require different parameter format"
        );
      }
    } else if (
      generationMode === "reference-images" &&
      referenceImages &&
      referenceImages.length > 0
    ) {
      // Use referenceImages field with proper referenceType values
      const maxReferenceImages = Math.min(referenceImages.length, 3);
      console.log(
        "[generateVideo] Reference images mode - preparing images:",
        JSON.stringify(
          { referenceCount: referenceImages.length, usingCount: maxReferenceImages },
          null,
          2
        )
      );

      const preparedReferenceImages = await Promise.all(
        referenceImages.slice(0, maxReferenceImages).map(async (img) => {
          const prepared = await prepareImageForVeo(img);
          if (!prepared) {
            throw new Error(`Failed to prepare reference image: ${img.substring(0, 50)}...`);
          }
          return {
            image: {
              bytesBase64Encoded: prepared.data,
              mimeType: prepared.mimeType,
            },
            // Veo 3.1 only supports "asset" (subject) reference images, NOT "style"
            referenceType: "asset",
          };
        })
      );

      instance.referenceImages = preparedReferenceImages;
    }

    // Build full request body in Vertex AI format
    const requestBody = {
      instances: [instance],
      parameters: {
        aspectRatio,
        durationSeconds: effectiveDuration,
        sampleCount: 1,
      },
    };

    console.log(
      "[generateVideo] Starting Veo 3.1 generation via Vertex AI:",
      JSON.stringify(
        {
          mode: generationMode,
          promptLength: prompt.length,
          hasImage: !!instance.image,
          referenceImageCount: instance.referenceImages?.length || 0,
          durationSeconds: effectiveDuration,
        },
        null,
        2
      )
    );

    // Call Vertex AI REST API for video generation using v1beta1
    const endpoint = `https://${location}-aiplatform.googleapis.com/v1beta1/projects/${projectId}/locations/${location}/publishers/google/models/veo-3.1-generate-preview:predictLongRunning`;

    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        "[generateVideo] Vertex AI API error:",
        JSON.stringify({ status: response.status, error: errorText.substring(0, 500) }, null, 2)
      );
      return {
        success: false,
        error: `Vertex AI API error: ${response.status} - ${errorText.substring(0, 200)}`,
      };
    }

    const data = await response.json();
    const operationName = data.name;

    if (!operationName) {
      console.error(
        "[generateVideo] No operation name in response:",
        JSON.stringify(data, null, 2)
      );
      return {
        success: false,
        error: "No operation name returned from Vertex AI",
      };
    }

    console.log(
      "[generateVideo] Video generation started:",
      JSON.stringify({ operationName }, null, 2)
    );

    return {
      success: true,
      videoId: operationName,
      status: "processing",
    };
  } catch (error) {
    console.error(
      "[generateVideo] Error:",
      JSON.stringify(
        {
          error: error instanceof Error ? error.message : String(error),
          prompt: prompt.substring(0, 100),
        },
        null,
        2
      )
    );

    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to start video generation",
    };
  }
}

/**
 * Check the status of a video generation job using Vertex AI REST API
 * Uses the :fetchPredictOperation POST endpoint for Publisher Models (Veo)
 */
export async function checkVideoStatus(videoId: string): Promise<VideoGenerationResult> {
  if (!videoId) {
    return { success: false, error: "Video ID is required" };
  }

  try {
    const projectId = process.env.GOOGLE_CLOUD_PROJECT_ID;
    const location = process.env.GOOGLE_CLOUD_LOCATION || "us-central1";

    if (!projectId) {
      return { success: false, error: "GOOGLE_CLOUD_PROJECT_ID not configured" };
    }

    // Get authenticated client
    const auth = getAuthClient();
    const client = await auth.getClient();
    const accessToken = await client.getAccessToken();

    if (!accessToken.token) {
      return { success: false, error: "Failed to obtain access token" };
    }

    // Use :fetchPredictOperation endpoint (POST with operationName in body)
    // This is required for Publisher Models (like Veo) which use UUID-based operation IDs
    const endpoint = `https://${location}-aiplatform.googleapis.com/v1beta1/projects/${projectId}/locations/${location}/publishers/google/models/veo-3.1-generate-preview:fetchPredictOperation`;

    console.log(
      "[checkVideoStatus] Polling operation:",
      JSON.stringify(
        {
          endpoint,
          operationName: videoId,
        },
        null,
        2
      )
    );

    const response = await fetch(endpoint, {
      method: "POST", // Must be POST, not GET
      headers: {
        Authorization: `Bearer ${accessToken.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ operationName: videoId }), // Full operation name in body
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        "[checkVideoStatus] API error:",
        JSON.stringify(
          {
            status: response.status,
            statusText: response.statusText,
            error: errorText.substring(0, 500),
          },
          null,
          2
        )
      );
      return {
        success: false,
        videoId,
        error: `API Error: ${response.status} - ${errorText.substring(0, 200)}`,
      };
    }

    const data = await response.json();

    console.log(
      "[checkVideoStatus] Operation response:",
      JSON.stringify(
        {
          done: data.done,
          hasError: !!data.error,
          hasResponse: !!data.response,
        },
        null,
        2
      )
    );

    // Check if operation is done
    if (data.done) {
      if (data.error) {
        console.error("[checkVideoStatus] Operation failed:", JSON.stringify(data.error, null, 2));
        return {
          success: false,
          videoId,
          status: "failed",
          error: data.error.message || "Video generation failed",
        };
      }

      // Check for RAI filtering
      const generateVideoResponse = data.response?.generateVideoResponse;
      if (generateVideoResponse?.raiMediaFilteredCount > 0) {
        const filterReasons = generateVideoResponse.raiMediaFilteredReasons || [];
        return {
          success: false,
          videoId,
          status: "failed",
          error: filterReasons[0] || "Video was blocked by safety filters.",
        };
      }

      // Extract video from response - can be either a URL or base64-encoded bytes
      // Veo 3.1 returns bytesBase64Encoded by default unless outputStorageUri is configured
      let videoUrl: string | undefined;
      let videoBase64: string | undefined;

      // Try to find video in various response formats
      const videoSources = [
        data.response?.predictions?.[0],
        data.response?.generatedSamples?.[0]?.video,
        generateVideoResponse?.generatedSamples?.[0]?.video,
        data.response?.videos?.[0],
      ];

      for (const source of videoSources) {
        if (!source) continue;

        // Check for URL first
        if (source.uri || source.videoUri) {
          videoUrl = source.uri || source.videoUri;
          break;
        }

        // Check for base64-encoded video (Veo 3.1 default)
        if (source.bytesBase64Encoded) {
          videoBase64 = source.bytesBase64Encoded;
          break;
        }
      }

      if (!videoUrl && !videoBase64) {
        console.error(
          "[checkVideoStatus] No video data in response:",
          JSON.stringify(
            {
              responseKeys: Object.keys(data.response || {}),
              fullResponse: data.response,
            },
            null,
            2
          )
        );
        return {
          success: false,
          videoId,
          status: "failed",
          error: "No video data in response",
        };
      }

      if (videoUrl) {
        console.log(
          "[checkVideoStatus] Video ready (URL):",
          JSON.stringify(
            {
              videoUrl: videoUrl.substring(0, 100),
            },
            null,
            2
          )
        );
      } else {
        console.log(
          "[checkVideoStatus] Video ready (base64):",
          JSON.stringify(
            {
              base64Length: videoBase64?.length,
            },
            null,
            2
          )
        );
      }

      return {
        success: true,
        videoId,
        videoUrl,
        videoBase64,
        status: "completed",
      };
    }

    // Still processing
    console.log("[checkVideoStatus] Operation still processing");
    return {
      success: true,
      videoId,
      status: "processing",
    };
  } catch (error) {
    console.error(
      "[checkVideoStatus] Error:",
      JSON.stringify(
        {
          error: error instanceof Error ? error.message : String(error),
          videoId,
        },
        null,
        2
      )
    );

    return {
      success: false,
      videoId,
      error: error instanceof Error ? error.message : "Failed to check video status",
    };
  }
}
