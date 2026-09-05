import { type NextRequest, NextResponse } from "next/server";
import { exportPostAsHTML, exportPostAsHTMLDocument } from "@/lib/export-posts";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { markdown, title, author } = body;

    if (!markdown) {
      return NextResponse.json({ error: "Markdown content is required" }, { status: 400 });
    }

    // Create a temporary post object for the export function
    const tempPost = {
      id: "",
      projectId: "",
      title: title || "Untitled",
      content: markdown,
      createdAt: new Date().toISOString(),
    };

    let html: string;
    if (title || author) {
      html = await exportPostAsHTMLDocument(tempPost, { title, author });
    } else {
      html = await exportPostAsHTML(tempPost);
    }

    return NextResponse.json({ html });
  } catch (error) {
    console.error("Error exporting HTML:", error);
    return NextResponse.json({ error: "Failed to export HTML" }, { status: 500 });
  }
}
