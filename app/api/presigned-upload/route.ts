import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { generatePresignedUploadUrl } from "@/lib/s3";

// File type configurations
const ALLOWED_TYPES = {
  image: {
    mimeTypes: ["image/jpeg", "image/png", "image/gif", "image/webp"],
    maxSize: 20 * 1024 * 1024, // 20MB
  },
  video: {
    mimeTypes: ["video/mp4", "video/webm", "video/quicktime", "video/x-msvideo"],
    maxSize: 500 * 1024 * 1024, // 500MB
  },
  audio: {
    mimeTypes: [
      "audio/mpeg",
      "audio/mp3",
      "audio/wav",
      "audio/ogg",
      "audio/aac",
      "audio/x-m4a",
      "audio/mp4",
    ],
    maxSize: 50 * 1024 * 1024, // 50MB
  },
} as const;

type MediaType = keyof typeof ALLOWED_TYPES;

export async function POST(request: Request) {
  try {
    const { userId } = await auth();

    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    const body = await request.json();
    const { projectId, sceneId, mediaType, contentType, fileName, fileSize } = body;

    // Validate required fields
    if (!projectId || !sceneId) {
      return NextResponse.json(
        { success: false, error: "Project ID and Scene ID are required" },
        { status: 400 }
      );
    }

    if (!mediaType || !["image", "video", "audio"].includes(mediaType)) {
      return NextResponse.json(
        { success: false, error: "Invalid media type. Must be 'image', 'video', or 'audio'" },
        { status: 400 }
      );
    }

    if (!contentType || !fileName) {
      return NextResponse.json(
        { success: false, error: "Content type and file name are required" },
        { status: 400 }
      );
    }

    const typeConfig = ALLOWED_TYPES[mediaType as MediaType];

    // Validate content type
    if (!(typeConfig.mimeTypes as readonly string[]).includes(contentType)) {
      return NextResponse.json(
        {
          success: false,
          error: `Invalid ${mediaType} type. Allowed: ${typeConfig.mimeTypes.join(", ")}`,
        },
        { status: 400 }
      );
    }

    // Validate file size if provided
    if (fileSize && fileSize > typeConfig.maxSize) {
      const maxSizeMB = Math.round(typeConfig.maxSize / (1024 * 1024));
      return NextResponse.json(
        {
          success: false,
          error: `${mediaType.charAt(0).toUpperCase() + mediaType.slice(1)} must be less than ${maxSizeMB}MB`,
        },
        { status: 400 }
      );
    }

    // Generate unique filename
    const timestamp = Date.now();
    const randomId = Math.random().toString(36).substring(2, 9);
    const extension = fileName.split(".").pop() || getDefaultExtension(mediaType);
    const filename = `${mediaType}-${timestamp}-${randomId}.${extension}`;
    const key = `projects/${projectId}/scenes/${sceneId}/${mediaType}s/${filename}`;

    // Generate presigned URL
    const { uploadUrl, publicUrl } = await generatePresignedUploadUrl(key, contentType);

    // Generate a unique ID for the uploaded media
    const mediaId = `uploaded-${timestamp}-${randomId}`;

    console.log(
      `[presigned-upload] Generated presigned URL for ${mediaType}:`,
      JSON.stringify({ key, mediaId, contentType, fileSize }, null, 2)
    );

    return NextResponse.json({
      success: true,
      uploadUrl,
      publicUrl,
      key,
      mediaId,
      mediaType,
    });
  } catch (error) {
    console.error("[presigned-upload] Error:", JSON.stringify({ error }, null, 2));
    return NextResponse.json(
      { success: false, error: "Failed to generate upload URL" },
      { status: 500 }
    );
  }
}

function getDefaultExtension(mediaType: string): string {
  switch (mediaType) {
    case "image":
      return "jpg";
    case "video":
      return "mp4";
    case "audio":
      return "mp3";
    default:
      return "bin";
  }
}
