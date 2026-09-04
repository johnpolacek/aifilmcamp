import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { deleteObjectFromS3, extractS3KeyFromUrl } from "@/lib/s3";

export async function POST(request: Request) {
  try {
    const { userId } = await auth();

    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    const body = await request.json();
    const { videoUrl, thumbnailUrl } = body;

    if (!videoUrl) {
      return NextResponse.json({ success: false, error: "Video URL is required" }, { status: 400 });
    }

    console.log(
      "[delete-video] Deleting video:",
      JSON.stringify(
        { videoUrl: videoUrl.substring(0, 100), thumbnailUrl: thumbnailUrl?.substring(0, 100) },
        null,
        2
      )
    );

    // Extract S3 key from video URL
    const videoKey = extractS3KeyFromUrl(videoUrl);
    if (!videoKey) {
      console.error(
        "[delete-video] Failed to extract S3 key from video URL:",
        JSON.stringify({ videoUrl: videoUrl.substring(0, 100) }, null, 2)
      );
      return NextResponse.json(
        { success: false, error: "Invalid video URL format" },
        { status: 400 }
      );
    }

    // Delete video from S3
    await deleteObjectFromS3(videoKey);
    console.log(
      "[delete-video] Video deleted successfully:",
      JSON.stringify({ videoKey }, null, 2)
    );

    // Delete thumbnail if provided
    if (thumbnailUrl) {
      const thumbnailKey = extractS3KeyFromUrl(thumbnailUrl);
      if (thumbnailKey) {
        try {
          await deleteObjectFromS3(thumbnailKey);
          console.log(
            "[delete-video] Thumbnail deleted successfully:",
            JSON.stringify({ thumbnailKey }, null, 2)
          );
        } catch (thumbnailError) {
          // Log but don't fail if thumbnail deletion fails
          console.error(
            "[delete-video] Failed to delete thumbnail (non-critical):",
            JSON.stringify(
              {
                thumbnailKey,
                error:
                  thumbnailError instanceof Error ? thumbnailError.message : String(thumbnailError),
              },
              null,
              2
            )
          );
        }
      }
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error(
      "[delete-video] Error deleting video:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );
    return NextResponse.json({ success: false, error: "Failed to delete video" }, { status: 500 });
  }
}
