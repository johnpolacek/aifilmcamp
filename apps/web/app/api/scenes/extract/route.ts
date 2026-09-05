import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { parsedScenesToScenes, parseScreenplay } from "@/lib/screenplay-parser";

export async function POST(request: Request) {
  try {
    // Check authentication
    const { userId } = await auth();
    if (!userId) {
      return NextResponse.json({ success: false, error: "Unauthorized" }, { status: 401 });
    }

    // Parse request body
    const body = await request.json();
    const { screenplayText, projectId, locationNames, characterNames } = body;

    if (!screenplayText) {
      return NextResponse.json(
        { success: false, error: "Screenplay text is required" },
        { status: 400 }
      );
    }

    if (!projectId) {
      return NextResponse.json(
        { success: false, error: "Project ID is required" },
        { status: 400 }
      );
    }

    console.log(
      "[extract-scenes] Parsing screenplay:",
      JSON.stringify(
        {
          projectId,
          textLength: screenplayText.length,
          locationCount: locationNames?.length || 0,
          characterCount: characterNames?.length || 0,
        },
        null,
        2
      )
    );

    // Parse the screenplay, passing character names for narrative matching
    const parseResult = parseScreenplay(screenplayText, characterNames || []);

    if (!parseResult.success) {
      return NextResponse.json(
        { success: false, error: parseResult.error || "Failed to parse screenplay" },
        { status: 400 }
      );
    }

    // Convert to Scene objects, passing project location names for automatic matching
    // Note: Character matching happens during parseScreenplay, so characters are already in parsed.scenes
    const scenes = parsedScenesToScenes(projectId, parseResult.scenes, true, locationNames || []);

    console.log(
      "[extract-scenes] Extracted scenes:",
      JSON.stringify({ projectId, sceneCount: scenes.length }, null, 2)
    );

    return NextResponse.json({
      success: true,
      scenes,
      count: scenes.length,
    });
  } catch (error) {
    console.error(
      "[extract-scenes] Error:",
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
    );

    return NextResponse.json({ success: false, error: "Internal server error" }, { status: 500 });
  }
}
