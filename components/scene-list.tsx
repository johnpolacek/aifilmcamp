"use client";

import { Edit, Film, Loader2, Plus } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { ExtractConfirmDialog } from "@/components/extract-confirm-dialog";
import type { Character, Location } from "@/components/project-form";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import type { Scene } from "@/lib/scenes-client";

interface SceneListProps {
  projectId: string;
  scenes: Scene[];
  characters: Character[];
  locations?: Location[];
  screenplayText?: string;
  onScenesChange: (scenes: Scene[]) => void;
}

export function SceneList({
  projectId,
  scenes,
  characters,
  locations,
  screenplayText,
  onScenesChange,
}: SceneListProps) {
  const router = useRouter();
  const [isExtracting, setIsExtracting] = useState(false);
  const [showConfirmDialog, setShowConfirmDialog] = useState(false);

  const performExtraction = async () => {
    if (!screenplayText || screenplayText.trim().length === 0) {
      toast.error("No screenplay text to extract scenes from. Please add a screenplay first.");
      return;
    }

    setIsExtracting(true);
    const loadingToast = toast.loading("Extracting scenes from screenplay...");

    try {
      // Get location and character names for automatic matching
      const locationNames = locations?.map((loc) => loc.name).filter(Boolean) || [];
      const characterNames = characters?.map((char) => char.name).filter(Boolean) || [];

      const response = await fetch("/api/scenes/extract", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          screenplayText,
          projectId,
          locationNames,
          characterNames,
        }),
      });

      const data = await response.json();

      if (data.success && data.scenes) {
        // Replace all scenes with extracted scenes
        onScenesChange(data.scenes);
        toast.success(`Extracted ${data.scenes.length} scenes from screenplay`, {
          id: loadingToast,
        });
      } else {
        toast.error(data.error || "Failed to extract scenes", { id: loadingToast });
      }
    } catch (error) {
      console.error("[SceneList] Error extracting scenes:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to extract scenes", { id: loadingToast });
    } finally {
      setIsExtracting(false);
      setShowConfirmDialog(false);
    }
  };

  const handleExtractScenes = () => {
    if (!screenplayText || screenplayText.trim().length === 0) {
      toast.error("No screenplay text to extract scenes from. Please add a screenplay first.");
      return;
    }

    // If there are existing scenes, show confirmation dialog
    if (scenes.length > 0) {
      setShowConfirmDialog(true);
    } else {
      // No existing scenes, proceed directly
      performExtraction();
    }
  };

  const handleAddScene = async () => {
    const newSceneNumber = scenes.length + 1;
    const now = new Date().toISOString();
    const newScene: Scene = {
      id: `scene-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
      projectId,
      sceneNumber: newSceneNumber,
      title: "New Scene",
      screenplay: "",
      summary: "",
      dramaticPurpose: "",
      emotionalBeat: "",
      visualIntent: "",
      characters: [],
      promptShots: [],
      generatedImages: [],
      generatedVideos: [],
      createdAt: now,
      updatedAt: now,
    };

    // Save the new scene first, then navigate to edit page
    const loadingToast = toast.loading("Creating scene...");
    try {
      const response = await fetch(`/api/scenes/${newScene.id}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          projectId,
          scene: newScene,
        }),
      });

      const data = await response.json();

      if (data.success) {
        onScenesChange([...scenes, newScene]);
        toast.success("Scene created", { id: loadingToast });
        router.push(`/dashboard/projects/${projectId}/scenes/${newScene.id}/edit`);
      } else {
        toast.error(data.error || "Failed to create scene", { id: loadingToast });
      }
    } catch (error) {
      console.error("[SceneList] Error creating scene:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to create scene", { id: loadingToast });
    }
  };

  return (
    <div className="space-y-4">
      {/* Scene List */}
      {scenes.length > 0 ? (
        <div className="flex flex-col gap-2">
          {scenes.map((scene) => (
            <Link key={scene.id} href={`/dashboard/projects/${projectId}/scenes/${scene.id}/edit`}>
              <Card className="group bg-muted/30 border-border hover:bg-muted/50 py-2 transition-colors cursor-pointer">
                <CardContent className="pl-4 py-0 flex items-center gap-4">
                  <div className="pt-0.5 shrink-0">
                    <Edit className="h-4 w-4 text-primary opacity-0 group-hover:opacity-100 transition-all duration-500" />
                  </div>
                  <span className="text-sm text-muted-foreground font-medium shrink-0 w-8">
                    #{scene.sceneNumber}
                  </span>
                  <h4 className="font-medium truncate min-w-0">{scene.title}</h4>
                  {scene.screenplay && (
                    <div className="flex-1 min-w-0 hidden sm:block">
                      <p className="font-mono text-xs text-muted-foreground truncate">
                        {scene.screenplay.substring(0, 200)}...
                      </p>
                    </div>
                  )}
                  <div className="flex items-center gap-4 text-sm text-muted-foreground shrink-0">
                    {(scene.promptShots?.length || 0) > 0 && (
                      <span>{scene.promptShots?.length} prompts</span>
                    )}
                    {scene.generatedImages && scene.generatedImages.length > 0 && (
                      <span>{scene.generatedImages.length} assets</span>
                    )}
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      ) : (
        <div className="text-center py-8 text-muted-foreground">
          <Film className="h-12 w-12 mx-auto mb-4 opacity-50" />
          <p>No scenes yet. Add your first scene or sync from the script breakdown.</p>
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex gap-2">
        <Button type="button" variant="outline" onClick={handleAddScene} className="bg-transparent">
          <Plus className="h-4 w-4 mr-2" />
          Add Scene
        </Button>
        {screenplayText && screenplayText.trim().length > 0 && (
          <Button
            type="button"
            variant="secondary"
            onClick={handleExtractScenes}
            disabled={isExtracting}
            className="flex-1"
          >
            {isExtracting ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                Extracting...
              </>
            ) : (
              <>
                <Film className="h-4 w-4 mr-2" />
                Extract from Screenplay
              </>
            )}
          </Button>
        )}
      </div>

      {/* Confirmation Dialog */}
      <ExtractConfirmDialog
        open={showConfirmDialog}
        onOpenChange={setShowConfirmDialog}
        title="Replace All Scenes?"
        description={`This will replace all ${scenes.length} existing scene${scenes.length !== 1 ? "s" : ""} with scenes extracted from the screenplay. This action cannot be undone.`}
        confirmLabel="Replace All Scenes"
        isLoading={isExtracting}
        onConfirm={performExtraction}
      />
    </div>
  );
}
