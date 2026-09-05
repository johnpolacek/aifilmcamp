import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { deleteScene, saveScene } from "@/lib/scenes";

export async function PUT(request: Request, { params }: { params: Promise<{ sceneId: string }> }) {
  try {
    const { userId } = await auth();

    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    const { sceneId } = await params;
    const body = await request.json();
    const { projectId, scene } = body;

    if (!projectId || !scene) {
      return NextResponse.json(
        { success: false, error: "Project ID and scene data are required" },
        { status: 400 }
      );
    }

    if (scene.id !== sceneId) {
      return NextResponse.json({ success: false, error: "Scene ID mismatch" }, { status: 400 });
    }

    await saveScene(projectId, scene);

    console.log("[scenes/[sceneId]] Scene saved:", JSON.stringify({ projectId, sceneId }, null, 2));

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("[scenes/[sceneId]] Error saving scene:", JSON.stringify({ error }, null, 2));
    return NextResponse.json({ success: false, error: "Failed to save scene" }, { status: 500 });
  }
}

export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ sceneId: string }> }
) {
  try {
    const { userId } = await auth();

    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    const { sceneId } = await params;
    const body = await request.json();
    const { projectId } = body;

    if (!projectId) {
      return NextResponse.json(
        { success: false, error: "Project ID is required" },
        { status: 400 }
      );
    }

    await deleteScene(projectId, sceneId);

    console.log(
      "[scenes/[sceneId]] Scene deleted:",
      JSON.stringify({ projectId, sceneId }, null, 2)
    );

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("[scenes/[sceneId]] Error deleting scene:", JSON.stringify({ error }, null, 2));
    return NextResponse.json({ success: false, error: "Failed to delete scene" }, { status: 500 });
  }
}
