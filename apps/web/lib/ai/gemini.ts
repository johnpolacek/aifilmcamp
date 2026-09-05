import { google } from "@ai-sdk/google";
import { generateImage as aiGenerateImage } from "ai";
import { GoogleAuth } from "google-auth-library";

/**
 * Google Gemini AI Service
 * Uses Vercel AI SDK for image generation
 * Uses Vertex AI for reference image analysis
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
