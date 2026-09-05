"use client";

import { ArrowLeft, Download, FileText, Pencil } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { ScreenplayElement } from "@/lib/types/screenplay";
import { cn } from "@/lib/utils";

interface ScreenplayViewerProps {
  projectId: string;
  elements: ScreenplayElement[];
  projectTitle?: string;
  username?: string;
  isOwner?: boolean;
  backUrl?: string;
  backLabel?: string;
}

/**
 * Get CSS classes for element type styling (read-only view)
 */
function getElementStyles(type: ScreenplayElement["type"]): string {
  switch (type) {
    case "scene_heading":
      return "font-bold uppercase tracking-wide text-primary pt-4";
    case "action":
      return "font-normal";
    case "character":
      return "uppercase font-semibold mt-6 text-center";
    case "parenthetical":
      return "italic text-muted-foreground text-sm text-center";
    case "dialogue":
      return "text-left";
    case "transition":
      return "uppercase text-right font-semibold text-muted-foreground mt-4";
    default:
      return "";
  }
}

/**
 * Get wrapper classes for centering blocks
 */
function getWrapperStyles(type: ScreenplayElement["type"]): string {
  switch (type) {
    case "character":
      return "flex justify-center";
    case "parenthetical":
      return "flex justify-center";
    case "dialogue":
      return "flex justify-center";
    default:
      return "";
  }
}

/**
 * Get max-width for element types
 */
function getMaxWidth(type: ScreenplayElement["type"]): string {
  switch (type) {
    case "dialogue":
      return "w-full max-w-[35ch]";
    case "parenthetical":
      return "w-full max-w-[35ch]";
    case "character":
      return "w-full max-w-[35ch]";
    default:
      return "w-full";
  }
}

/**
 * Read-only screenplay viewer component
 * Displays a formatted screenplay for viewing/sharing
 */
export function ScreenplayViewer({
  projectId,
  elements,
  projectTitle,
  username,
  isOwner = false,
  backUrl,
  backLabel = "Back",
}: ScreenplayViewerProps) {
  // Calculate statistics
  const wordCount = elements.reduce((count, el) => {
    return (
      count +
      el.content
        .trim()
        .split(/\s+/)
        .filter((w) => w.length > 0).length
    );
  }, 0);
  const sceneCount = elements.filter((el) => el.type === "scene_heading").length;
  const pageCount = Math.ceil(wordCount / 250);

  // Export as plain text
  const handleExportText = async () => {
    const { elementsToText } = await import("@/lib/screenplay-parser");
    const text = elementsToText(elements);
    const blob = new Blob([text], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${projectTitle || "screenplay"}.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <div className="fixed top-0 left-0 right-0 z-50 bg-background/95 backdrop-blur border-b border-border">
        <div className="container mx-auto px-4 py-3 flex items-center justify-between">
          <div className="flex items-center gap-4">
            {backUrl && (
              <>
                <Link
                  href={backUrl}
                  className="flex items-center gap-2 text-muted-foreground hover:text-foreground transition-colors"
                >
                  <ArrowLeft className="h-4 w-4" />
                  <span className="hidden sm:inline">{backLabel}</span>
                </Link>
                <div className="h-4 w-px bg-border" />
              </>
            )}
            <div className="flex items-center gap-2">
              <FileText className="h-5 w-5 text-primary" />
              <h1 className="font-semibold truncate max-w-[200px] sm:max-w-none">
                {projectTitle || "Screenplay"}
              </h1>
            </div>
            {username && (
              <span className="text-sm text-muted-foreground hidden sm:inline">by {username}</span>
            )}
          </div>

          <div className="flex items-center gap-2">
            {/* Stats */}
            <div className="hidden md:flex items-center gap-4 text-sm text-muted-foreground mr-4">
              <span>{sceneCount} scenes</span>
              <span>~{pageCount} pages</span>
              <span>{wordCount} words</span>
            </div>

            {/* Actions */}
            <Button variant="outline" size="sm" onClick={handleExportText}>
              <Download className="h-4 w-4 mr-2" />
              <span className="hidden sm:inline">Export</span>
            </Button>

            {isOwner && (
              <Button asChild size="sm">
                <Link href={`/dashboard/projects/${projectId}/screenplay`}>
                  <Pencil className="h-4 w-4 mr-2" />
                  <span className="hidden sm:inline">Edit</span>
                </Link>
              </Button>
            )}
          </div>
        </div>
      </div>

      {/* Screenplay content */}
      <div className="pt-20 pb-16">
        <div className="container mx-auto px-4 max-w-5xl">
          <Card className="bg-card/50">
            <CardHeader className="pb-2 border-b border-border">
              <CardTitle className="text-center">
                <span className="text-2xl font-bold">{projectTitle || "Untitled"}</span>
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {/* Elements */}
              <div className="py-8 px-6 sm:px-12 font-mono text-sm leading-relaxed space-y-1">
                {elements.length === 0 ? (
                  <div className="text-center text-muted-foreground py-12">
                    <FileText className="h-12 w-12 mx-auto mb-4 opacity-50" />
                    <p>No screenplay content yet.</p>
                  </div>
                ) : (
                  elements.map((element, index) => {
                    // Calculate scene number by counting scene headings up to this index
                    const sceneNumber = elements
                      .slice(0, index + 1)
                      .filter((el) => el.type === "scene_heading").length;

                    // Add extra spacing when action follows dialogue
                    const prevElement = index > 0 ? elements[index - 1] : null;
                    const needsExtraSpacing =
                      element.type === "action" && prevElement?.type === "dialogue";

                    return (
                      <div
                        key={element.id}
                        className={cn(
                          "py-0.5 relative",
                          getWrapperStyles(element.type),
                          needsExtraSpacing && "pt-4"
                        )}
                      >
                        <p
                          className={cn(
                            "whitespace-pre-wrap",
                            getMaxWidth(element.type),
                            getElementStyles(element.type)
                          )}
                        >
                          {element.content || "\u00A0"}
                        </p>
                        {element.type === "scene_heading" && sceneNumber > 0 && (
                          <span className="hidden lg:block absolute top-1/2 -translate-y-1/2 -left-8 text-xs text-muted-foreground font-mono -translate-x-full xl:pr-4">
                            SCENE #{sceneNumber}
                          </span>
                        )}
                      </div>
                    );
                  })
                )}
              </div>

              {/* Footer stats */}
              <div className="border-t border-border px-6 py-4 text-center text-sm text-muted-foreground">
                {sceneCount} scenes • ~{pageCount} pages • {wordCount} words
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
