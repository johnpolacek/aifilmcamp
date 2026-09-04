import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { uploadFileFromBuffer, uploadImageFromBuffer } from "@/lib/s3";

export async function POST(request: Request) {
  try {
    const { userId } = await auth();

    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    const formData = await request.formData();
    const file = formData.get("file") as File;
    const projectId = formData.get("projectId") as string;
    const sceneId = formData.get("sceneId") as string;
    const mediaType = formData.get("mediaType") as "image" | "video" | "audio";

    if (!file) {
      return NextResponse.json({ success: false, error: "No file provided" }, { status: 400 });
    }

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

    // Validate file type
    const allowedImageTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"];
    const allowedVideoTypes = ["video/mp4", "video/webm", "video/quicktime", "video/x-msvideo"];
    const allowedAudioTypes = [
      "audio/mpeg",
      "audio/mp3",
      "audio/wav",
      "audio/ogg",
      "audio/aac",
      "audio/x-m4a",
      "audio/mp4",
    ];

    if (mediaType === "image" && !allowedImageTypes.includes(file.type)) {
      return NextResponse.json(
        { success: false, error: "Invalid image type. Allowed: JPEG, PNG, GIF, WebP" },
        { status: 400 }
      );
    }

    if (mediaType === "video" && !allowedVideoTypes.includes(file.type)) {
      return NextResponse.json(
        { success: false, error: "Invalid video type. Allowed: MP4, WebM, MOV, AVI" },
        { status: 400 }
      );
    }

    if (mediaType === "audio" && !allowedAudioTypes.includes(file.type)) {
      return NextResponse.json(
        { success: false, error: "Invalid audio type. Allowed: MP3, WAV, OGG, AAC, M4A" },
        { status: 400 }
      );
    }

    // Validate file size
    const maxImageSize = 20 * 1024 * 1024; // 20MB for images
    const maxVideoSize = 500 * 1024 * 1024; // 500MB for videos
    const maxAudioSize = 50 * 1024 * 1024; // 50MB for audio

    if (mediaType === "image" && file.size > maxImageSize) {
      return NextResponse.json(
        { success: false, error: "Image must be less than 20MB" },
        { status: 400 }
      );
    }

    if (mediaType === "video" && file.size > maxVideoSize) {
      return NextResponse.json(
        { success: false, error: "Video must be less than 500MB" },
        { status: 400 }
      );
    }

    if (mediaType === "audio" && file.size > maxAudioSize) {
      return NextResponse.json(
        { success: false, error: "Audio must be less than 50MB" },
        { status: 400 }
      );
    }

    // Generate unique filename
    const timestamp = Date.now();
    const randomId = Math.random().toString(36).substring(2, 9);
    const getDefaultExtension = () => {
      if (mediaType === "image") return "jpg";
      if (mediaType === "video") return "mp4";
      return "mp3";
    };
    const extension = file.name.split(".").pop() || getDefaultExtension();
    const filename = `${mediaType}-${timestamp}-${randomId}.${extension}`;
    const key = `projects/${projectId}/scenes/${sceneId}/${mediaType}s/${filename}`;

    // Convert file to buffer
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    let url: string;

    if (mediaType === "image") {
      // Use image optimization for images
      url = await uploadImageFromBuffer(buffer, key, file.type);
    } else {
      // Upload video/audio directly without optimization
      url = await uploadFileFromBuffer(buffer, key, file.type);
    }

    // Generate a unique ID for the uploaded media
    const mediaId = `uploaded-${timestamp}-${randomId}`;

    console.log(
      `[upload-media] Successfully uploaded ${mediaType}:`,
      JSON.stringify({ key, url, mediaId }, null, 2)
    );

    return NextResponse.json({
      success: true,
      mediaType,
      id: mediaId,
      url,
      filename: file.name,
    });
  } catch (error) {
    console.error("[upload-media] Error:", JSON.stringify({ error }, null, 2));
    return NextResponse.json({ success: false, error: "Failed to upload media" }, { status: 500 });
  }
}
