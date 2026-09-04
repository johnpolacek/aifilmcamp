import { NextResponse } from "next/server";
import { getScene, saveScene } from "@/lib/scenes";

/**
 * POST /api/scenes/[sceneId]/compose/webhook
 * Webhook called by the video composer when composition is complete
 */
export async function POST(request: Request, { params }: { params: Promise<{ sceneId: string }> }) {
  try {
    const { sceneId } = await params;
    const { searchParams } = new URL(request.url);
    const projectId = searchParams.get("projectId");

    if (!projectId) {
      console.error("[compose-webhook] Missing projectId");
      return NextResponse.json({ error: "projectId query param is required" }, { status: 400 });
    }

    const result = await request.json();

    console.log(
      "[compose-webhook] Received result:",
      JSON.stringify(
        {
          sceneId,
          projectId,
          status: result.status,
          jobId: result.jobId,
          hasVideoUrl: !!result.videoUrl,
          hasThumbnailUrl: !!result.thumbnailUrl,
          durationMs: result.durationMs,
          error: result.error,
        },
        null,
        2
      )
    );

    const scene = await getScene(projectId, sceneId);
    if (!scene) {
      console.error(
        "[compose-webhook] Scene not found:",
        JSON.stringify({ projectId, sceneId }, null, 2)
      );
      return NextResponse.json({ error: "Scene not found" }, { status: 404 });
    }

    if (result.status === "completed") {
      await saveScene(projectId, {
        ...scene,
        compositeStatus: "completed",
        compositeVideo: {
          url: result.videoUrl,
          thumbnailUrl: result.thumbnailUrl,
          durationMs: result.durationMs,
          renderedAt: new Date().toISOString(),
          jobId: result.jobId,
        },
        compositeError: undefined,
        updatedAt: new Date().toISOString(),
      });

      console.log(
        "[compose-webhook] Scene updated with composite video:",
        JSON.stringify({ sceneId, videoUrl: result.videoUrl }, null, 2)
      );
    } else {
      await saveScene(projectId, {
        ...scene,
        compositeStatus: "failed",
        compositeError: result.error || "Unknown error",
        updatedAt: new Date().toISOString(),
      });

      console.error(
        "[compose-webhook] Composition failed:",
        JSON.stringify({ sceneId, error: result.error }, null, 2)
      );
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error(
      "[compose-webhook] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );
    return NextResponse.json({ error: "Failed to process webhook" }, { status: 500 });
  }
}
