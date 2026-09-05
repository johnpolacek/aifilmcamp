import { type NextRequest, NextResponse } from "next/server";
import { getPostsForProject } from "@/lib/posts";
import { getUserProfile } from "@/lib/profiles";
import { getProjectByUsernameAndSlug } from "@/lib/projects";
import { generateRSSFeed } from "@/lib/rss";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ username: string; projectSlug: string }> }
) {
  try {
    const { username, projectSlug } = await params;

    // Get project data
    const projectData = await getProjectByUsernameAndSlug(username, projectSlug);
    if (!projectData) {
      return NextResponse.json({ error: "Project not found" }, { status: 404 });
    }

    const { project, id } = projectData;

    // Get user profile
    const userProfile = await getUserProfile(username);
    if (!userProfile) {
      return NextResponse.json({ error: "User profile not found" }, { status: 404 });
    }

    // Get posts for this project
    const posts = await getPostsForProject(id);

    // Get base URL from request
    const url = new URL(request.url);
    const baseUrl = `${url.protocol}//${url.host}`;

    // Generate RSS feed
    const rssFeed = await generateRSSFeed(posts, { ...project, id }, userProfile, baseUrl);

    return new NextResponse(rssFeed, {
      status: 200,
      headers: {
        "Content-Type": "application/rss+xml; charset=utf-8",
        "Cache-Control": "public, s-maxage=3600, stale-while-revalidate=86400",
      },
    });
  } catch (error) {
    console.error("Error generating RSS feed:", error);
    return NextResponse.json({ error: "Failed to generate RSS feed" }, { status: 500 });
  }
}
