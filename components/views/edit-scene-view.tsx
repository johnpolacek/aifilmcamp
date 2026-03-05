"use client";

import {
  ArrowLeft,
  Check,
  Download,
  Edit,
  Film,
  Image as ImageIcon,
  Loader2,
  PlayCircle,
  Plus,
  Sparkles,
  Trash2,
  Video,
  X,
  FileDown,
  Volume2,
} from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import JSZip from "jszip";
import { AudioTrackModal } from "@/components/audio-track-modal";
import type { Character, Location } from "@/components/project-form";
import { ScenePlayer, type ScenePlayerHandle } from "@/components/scene-player";
import { ScreenplayElementComponent } from "@/components/screenplay-element";
import { ShotEditorDialog } from "@/components/shot-editor-modal";
import Timeline from "@/components/timeline";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Slider } from "@/components/ui/slider";
import { getImageUrl, getPublicUrl } from "@/lib/image-utils";
import type { AudioTrack, GenerationMode, Scene, Shot, ShotVideo } from "@/lib/scenes-client";
import { createNewShot, getEffectiveDuration } from "@/lib/scenes-client";
import { elementsToText, parseScreenplayToElements } from "@/lib/screenplay-parser";
import type { ScreenplayElement, ScreenplayElementType } from "@/lib/types/screenplay";
import { createScreenplayElement, ELEMENT_TYPE_LABELS } from "@/lib/types/screenplay";
import { uploadFile } from "@/lib/upload-utils";
import { generateThumbnailFromFile, generateThumbnailFromUrl } from "@/lib/video-thumbnail";
import { cn } from "@/lib/utils";
import { isVideoGenerationEnabled } from "@/lib/utils/video-generation";

// ============================================================================
// TYPES
// ============================================================================

interface EditSceneViewProps {
  scene: Scene;
  projectId: string;
  projectTitle: string;
  characters: Character[];
  locations: Location[];
  username: string;
}

// ============================================================================
// SCREENPLAY FORMATTING HELPERS
// ============================================================================

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

interface LibraryImage {
  url: string;
  label: string;
  category: "character" | "location" | "generated";
}

interface ImageInputZoneProps {
  onImageUrl: (url: string) => void;
  onUploadFile: (file: File) => Promise<void>;
  projectId: string;
  sceneId: string;
  disabled?: boolean;
  placeholder?: string;
  libraryImages?: LibraryImage[];
}

function ImageInputZone({
  onImageUrl,
  onUploadFile,
  projectId,
  sceneId,
  disabled,
  placeholder = "Describe the image you want to generate...",
  libraryImages = [],
}: ImageInputZoneProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [mode, setMode] = useState<"upload" | "generate" | "library">(
    libraryImages.length > 0 ? "library" : "upload"
  );
  const [isDragOver, setIsDragOver] = useState(false);
  const [generatePrompt, setGeneratePrompt] = useState("");
  const [isGenerating, setIsGenerating] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [selectedReferenceImages, setSelectedReferenceImages] = useState<string[]>([]);

  const toggleReferenceImage = useCallback((url: string) => {
    setSelectedReferenceImages((prev) => {
      if (prev.includes(url)) {
        return prev.filter((u) => u !== url);
      }
      if (prev.length >= 3) {
        toast.error("Maximum 3 reference images allowed");
        return prev;
      }
      return [...prev, url];
    });
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  }, []);

  const handleDragLeave = useCallback(() => {
    setIsDragOver(false);
  }, []);

  const handleDrop = useCallback(
    async (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragOver(false);
      const file = e.dataTransfer.files?.[0];
      if (file?.type.startsWith("image/")) {
        setIsUploading(true);
        try {
          await onUploadFile(file);
        } finally {
          setIsUploading(false);
        }
      }
    },
    [onUploadFile]
  );

  const handleFileChange = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) {
        setIsUploading(true);
        try {
          await onUploadFile(file);
        } finally {
          setIsUploading(false);
        }
      }
    },
    [onUploadFile]
  );

  const handleClick = useCallback(() => {
    if (!disabled && !isUploading) {
      inputRef.current?.click();
    }
  }, [disabled, isUploading]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if ((e.key === "Enter" || e.key === " ") && !disabled && !isUploading) {
        e.preventDefault();
        inputRef.current?.click();
      }
    },
    [disabled, isUploading]
  );

  const handleGenerate = useCallback(async () => {
    if (!generatePrompt.trim() || isGenerating) return;

    setIsGenerating(true);
    try {
      const response = await fetch("/api/ai/generate-image", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt: generatePrompt,
          projectId,
          sceneId,
          aspectRatio: "16:9",
          referenceImages: selectedReferenceImages.length > 0 ? selectedReferenceImages : undefined,
        }),
      });

      const data = await response.json();
      if (data.success && data.image?.imageUrl) {
        onImageUrl(data.image.imageUrl);
        setGeneratePrompt("");
        setSelectedReferenceImages([]);
        toast.success("Image generated successfully!");
      } else {
        toast.error(data.error || "Failed to generate image");
      }
    } catch (error) {
      console.error("[ImageInputZone] Generate error:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to generate image");
    } finally {
      setIsGenerating(false);
    }
  }, [generatePrompt, isGenerating, projectId, sceneId, onImageUrl, selectedReferenceImages]);

  const isDisabled = disabled || isGenerating || isUploading;

  return (
    <div className="space-y-2">
      {/* Mode Toggle */}
      <div className="flex gap-1 p-0.5 bg-muted rounded-md w-fit">
        {libraryImages.length > 0 && (
          <button
            type="button"
            onClick={() => setMode("library")}
            className={cn(
              "px-3 py-1 text-xs font-medium rounded transition-colors flex items-center gap-1",
              mode === "library"
                ? "bg-background text-foreground shadow-sm"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            <ImageIcon className="h-3 w-3" />
            Library
          </button>
        )}
        <button
          type="button"
          onClick={() => setMode("upload")}
          className={cn(
            "px-3 py-1 text-xs font-medium rounded transition-colors",
            mode === "upload"
              ? "bg-background text-foreground shadow-sm"
              : "text-muted-foreground hover:text-foreground"
          )}
        >
          Upload
        </button>
        <button
          type="button"
          onClick={() => setMode("generate")}
          className={cn(
            "px-3 py-1 text-xs font-medium rounded transition-colors flex items-center gap-1",
            mode === "generate"
              ? "bg-background text-foreground shadow-sm"
              : "text-muted-foreground hover:text-foreground"
          )}
        >
          <Sparkles className="h-3 w-3" />
          Generate
        </button>
      </div>

      {/* Upload Mode */}
      {mode === "upload" && (
        <>
          <button
            type="button"
            disabled={isDisabled}
            onClick={handleClick}
            onKeyDown={handleKeyDown}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
            className={cn(
              "w-full aspect-video rounded-lg border-2 border-dashed flex flex-col items-center justify-center gap-2 cursor-pointer transition-colors bg-transparent",
              isDragOver
                ? "border-primary bg-primary/5"
                : "border-muted-foreground/30 hover:border-primary/50",
              isDisabled && "opacity-50 cursor-not-allowed"
            )}
          >
            {isUploading ? (
              <>
                <Loader2 className="h-8 w-8 text-muted-foreground animate-spin" />
                <span className="text-sm text-muted-foreground">Uploading...</span>
              </>
            ) : (
              <>
                <ImageIcon className="h-8 w-8 text-muted-foreground" />
                <span className="text-sm text-muted-foreground">Drop image or click to upload</span>
              </>
            )}
          </button>
          <input
            ref={inputRef}
            type="file"
            accept="image/*"
            onChange={handleFileChange}
            className="hidden"
            disabled={isDisabled}
          />
        </>
      )}

      {/* Generate Mode */}
      {mode === "generate" && (
        <div className="space-y-3">
          {/* Reference Images Selection */}
          {libraryImages.length > 0 && (
            <div className="space-y-1.5">
              <p className="text-xs text-muted-foreground">
                Optional: Select up to 3 reference images for style/character consistency
              </p>
              <div className="flex gap-1.5 flex-wrap">
                {libraryImages.slice(0, 9).map((img, index) => (
                  <button
                    key={index}
                    type="button"
                    onClick={() => toggleReferenceImage(img.url)}
                    disabled={isDisabled}
                    className={cn(
                      "relative w-12 h-12 rounded overflow-hidden border-2 transition-all",
                      selectedReferenceImages.includes(img.url)
                        ? "border-primary ring-2 ring-primary/30"
                        : "border-transparent hover:border-muted-foreground/50"
                    )}
                  >
                    <Image src={img.url} alt={img.label} fill className="object-cover" />
                    {selectedReferenceImages.includes(img.url) && (
                      <div className="absolute inset-0 bg-primary/20 flex items-center justify-center">
                        <span className="text-primary font-bold text-xs">
                          {selectedReferenceImages.indexOf(img.url) + 1}
                        </span>
                      </div>
                    )}
                  </button>
                ))}
              </div>
              {selectedReferenceImages.length > 0 && (
                <p className="text-xs text-primary">
                  {selectedReferenceImages.length} reference image
                  {selectedReferenceImages.length !== 1 ? "s" : ""} selected
                </p>
              )}
            </div>
          )}

          {/* Prompt Input */}
          <div className="flex gap-2">
            <Input
              value={generatePrompt}
              onChange={(e) => setGeneratePrompt(e.target.value)}
              placeholder={placeholder}
              disabled={isDisabled}
              className="flex-1 text-sm"
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  handleGenerate();
                }
              }}
            />
            <Button
              type="button"
              size="sm"
              onClick={handleGenerate}
              disabled={isDisabled || !generatePrompt.trim()}
              className="shrink-0"
            >
              {isGenerating ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Sparkles className="h-4 w-4" />
              )}
            </Button>
          </div>
          {isGenerating && (
            <div className="aspect-video rounded-lg border-2 border-dashed border-primary/50 bg-primary/5 flex flex-col items-center justify-center gap-2">
              <Loader2 className="h-8 w-8 text-primary animate-spin" />
              <span className="text-sm text-muted-foreground">Generating image...</span>
            </div>
          )}
        </div>
      )}

      {/* Library Mode */}
      {mode === "library" && libraryImages.length > 0 && (
        <div className="space-y-2">
          <div className="grid grid-cols-3 gap-2 max-h-[300px] overflow-y-auto p-1">
            {libraryImages.map((img, index) => (
              <button
                key={index}
                type="button"
                onClick={() => onImageUrl(img.url)}
                disabled={isDisabled}
                className="relative aspect-video rounded-lg overflow-hidden border-2 border-transparent hover:border-primary transition-colors group"
              >
                <Image src={img.url} alt={img.label} fill className="object-cover" />
                <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors flex items-center justify-center">
                  <span className="text-white text-xs font-medium opacity-0 group-hover:opacity-100 transition-opacity px-2 text-center">
                    {img.label}
                  </span>
                </div>
                <span
                  className={cn(
                    "absolute top-1 left-1 text-[10px] px-1.5 py-0.5 rounded font-medium text-white",
                    img.category === "location" && "bg-emerald-500/80",
                    img.category === "character" && "bg-blue-500/80",
                    img.category === "generated" && "bg-purple-500/80"
                  )}
                >
                  {img.category === "location"
                    ? "Location"
                    : img.category === "character"
                      ? "Character"
                      : "Generated"}
                </span>
              </button>
            ))}
          </div>
          <p className="text-xs text-muted-foreground text-center">Click an image to select it</p>
        </div>
      )}
    </div>
  );
}

// ============================================================================
// MAIN COMPONENT
// ============================================================================

export function EditSceneView({
  scene: initialScene,
  projectId,
  characters,
  locations,
  username,
}: EditSceneViewProps) {
  const router = useRouter();
  const [scene, setScene] = useState<Scene>(() => {
    const initializedScene = {
      ...initialScene,
      shots: initialScene.shots || [],
      audioTracks: initialScene.audioTracks || [],
      generatedImages: initialScene.generatedImages || [],
      removedShots: initialScene.removedShots || [],
      transitionOut: initialScene.transitionOut || { type: "none", durationMs: 0 },
      masterVolume: initialScene.masterVolume ?? 1.0,
    };
    
    console.log(
      "[EditSceneView] Initializing scene state:",
      JSON.stringify({
        sceneId: initialScene.id,
        initialRemovedShotsCount: initialScene.removedShots?.length || 0,
        initialRemovedShots: initialScene.removedShots?.map(s => ({
          id: s.id,
          prompt: s.prompt?.substring(0, 50),
          hasVideo: !!s.video,
          videoStatus: s.video?.status,
          videoUrl: s.video?.url?.substring(0, 100),
        })) || [],
        initializedRemovedShotsCount: initializedScene.removedShots?.length || 0,
      }, null, 2)
    );
    
    return initializedScene;
  });
  const [saveStatus, setSaveStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const saveTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const lastSavedSceneRef = useRef<string>(JSON.stringify(initialScene));
  const [isDeleting, setIsDeleting] = useState(false);

  // Screenplay editing state
  const [isEditingScreenplay, setIsEditingScreenplay] = useState(false);
  const [screenplayElements, setScreenplayElements] = useState<ScreenplayElement[]>([]);
  const [focusedElementIndex, setFocusedElementIndex] = useState(0);
  const elementRefs = useRef<Map<string, HTMLTextAreaElement>>(new Map());

  // Shot editing state
  const [selectedShot, setSelectedShot] = useState<Shot | null>(null);
  const [showShotEditor, setShowShotEditor] = useState(false);
  // shotId -> { operationId, thumbnailUrl, thumbnailPath } for polling
  const [pendingShots, setPendingShots] = useState<Map<string, { operationId: string; thumbnailUrl?: string; thumbnailPath?: string }>>(new Map());
  
  // Use removedShots from scene state instead of separate state
  const removedShots = scene.removedShots || [];
  
  const [showMediaLibrary, setShowMediaLibrary] = useState(false);
  const [playingVideoId, setPlayingVideoId] = useState<string | null>(null); // Track which video is playing in Media Library
  const [shotToDelete, setShotToDelete] = useState<Shot | null>(null); // Shot pending deletion confirmation

  // Generate video dialog state
  const [showGenerateVideoDialog, setShowGenerateVideoDialog] = useState(false);
  const [generateMode, setGenerateMode] = useState<"start-end-frames" | "ingredients">(
    "start-end-frames"
  );
  const [generatePrompt, setGeneratePrompt] = useState("");
  const [startFrameImage, setStartFrameImage] = useState<string | undefined>(undefined);
  const [endFrameImage, setEndFrameImage] = useState<string | undefined>(undefined);
  const [referenceImages, setReferenceImages] = useState<string[]>([]);
  const [isGeneratingVideo, setIsGeneratingVideo] = useState(false);
  const [isUploadingImage, setIsUploadingImage] = useState(false);

  // Audio track editing state
  const [selectedAudioTrack, setSelectedAudioTrack] = useState<AudioTrack | null>(null);
  const [showAudioTrackEditor, setShowAudioTrackEditor] = useState(false);

  // Scene player state
  const [showPlayer, setShowPlayer] = useState(false);
  const scenePlayerRef = useRef<ScenePlayerHandle>(null);

  // Render scene state
  const [isRendering, setIsRendering] = useState(false);
  const [renderProgress, setRenderProgress] = useState<number | null>(null);
  const [renderStage, setRenderStage] = useState<string | null>(null);
  const [showCompositeVideoDialog, setShowCompositeVideoDialog] = useState(false);

  // Export source videos state
  const [showExportDialog, setShowExportDialog] = useState(false);
  const [isExporting, setIsExporting] = useState(false);
  const [exportProgress, setExportProgress] = useState<{ current: number; total: number } | null>(null);

  // Build library images from characters and generated images
  const libraryImages = useMemo(() => {
    const images: LibraryImage[] = [];

    // Add location images (prioritize these for scene context)
    locations.forEach((location) => {
      if (location.image) {
        const url = getImageUrl({
          type: "location",
          filename: location.image,
          username,
        });
        if (url) {
          images.push({
            url,
            label: location.name || "Location",
            category: "location",
          });
        }
      }
      // Add additional location images
      location.images?.forEach((imgFilename) => {
        if (imgFilename) {
          const url = getImageUrl({
            type: "location",
            filename: imgFilename,
            username,
          });
          if (url) {
            images.push({
              url,
              label: location.name || "Location",
              category: "location",
            });
          }
        }
      });
    });

    // Add character images
    characters.forEach((character) => {
      if (character.mainImage) {
        const url = getImageUrl({
          type: "character",
          filename: character.mainImage,
          username,
        });
        if (url) {
          images.push({
            url,
            label: character.name || "Character",
            category: "character",
          });
        }
      }
      // Add additional character images
      character.images?.forEach((imgFilename) => {
        if (imgFilename) {
          const url = getImageUrl({
            type: "character",
            filename: imgFilename,
            username,
          });
          if (url) {
            images.push({
              url,
              label: character.name || "Character",
              category: "character",
            });
          }
        }
      });
    });

    // Add generated images from the scene
    scene.generatedImages?.forEach((genImg) => {
      if (genImg.imageUrl) {
        images.push({
          url: genImg.imageUrl,
          label: genImg.prompt?.substring(0, 30) || "Generated",
          category: "generated",
        });
      }
    });

    return images;
  }, [locations, characters, scene.generatedImages, username]);

  // ============================================================================
  // RESTORE PENDING SHOTS ON PAGE LOAD
  // ============================================================================

  // Restore pending shots from scene data when component mounts
  // This handles the case where user refreshes the page during video generation
  useEffect(() => {
    const processingShots = initialScene.shots.filter(
      (shot) => shot.video?.status === "processing" && shot.video?.operationId
    );

    if (processingShots.length > 0) {
      console.log(
        "[EditSceneView] Restoring pending shots after page load:",
        JSON.stringify(
          {
            count: processingShots.length,
            shotIds: processingShots.map((s) => s.id),
            operationIds: processingShots.map((s) => s.video?.operationId),
          },
          null,
          2
        )
      );

      setPendingShots((prev) => {
        const next = new Map(prev);
        // Only add shots that aren't already in pendingShots
        for (const shot of processingShots) {
          if (shot.video?.operationId && !next.has(shot.id)) {
            // Reconstruct thumbnail path if possible (optional - polling will work without it)
            // S3 Path Convention: projects/{projectId}/scenes/{sceneId}/thumbnails/{filename}
            const thumbnailPath = shot.video?.operationId
              ? `projects/${projectId}/scenes/${initialScene.id}/thumbnails/${shot.id}.jpg`
              : undefined;
            
            // Try to construct thumbnail URL using getPublicUrl utility
            const thumbnailUrl = thumbnailPath ? getPublicUrl(thumbnailPath) : undefined;

            next.set(shot.id, {
              operationId: shot.video.operationId,
              thumbnailUrl,
              thumbnailPath,
            });
          }
        }
        return next;
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Only run once on mount

  // ============================================================================
  // POLLING FOR SHOT VIDEO COMPLETION
  // ============================================================================

  useEffect(() => {
    if (pendingShots.size === 0) return;

    const pollInterval = setInterval(async () => {
      for (const [shotId, pendingData] of pendingShots.entries()) {
        try {
          const { operationId, thumbnailUrl: predictedThumbnailUrl, thumbnailPath } = pendingData;
          
          // First, check if thumbnail exists via HEAD request (simple/fast)
          if (predictedThumbnailUrl) {
            try {
              const headResponse = await fetch(predictedThumbnailUrl, { method: 'HEAD' });
              if (headResponse.ok) {
                console.log(
                  "[EditSceneView] Thumbnail exists! Video is ready:",
                  JSON.stringify({ shotId, thumbnailUrl: predictedThumbnailUrl }, null, 2)
                );
                // Thumbnail exists - now call video-status to get the video URL
              }
            } catch (headError) {
              // HEAD request failed - thumbnail not ready yet, continue with normal polling
              console.log(
                "[EditSceneView] Thumbnail not ready yet:",
                JSON.stringify({ shotId, thumbnailUrl: predictedThumbnailUrl }, null, 2)
              );
            }
          }
          
          // Call video-status API to check/trigger backend processing
          const statusUrl = `/api/ai/video-status?operationId=${encodeURIComponent(operationId)}&projectId=${projectId}&sceneId=${scene.id}&videoId=${shotId}${thumbnailPath ? `&thumbnailPath=${encodeURIComponent(thumbnailPath)}` : ''}`;
          console.log(
            "[EditSceneView] Polling video status:",
            JSON.stringify({ shotId, operationId, statusUrl, hasThumbnailPath: !!thumbnailPath }, null, 2)
          );

          const response = await fetch(statusUrl);
          const data = await response.json();

          console.log(
            "[EditSceneView] Video status response:",
            JSON.stringify({ 
              shotId, 
              responseStatus: response.status,
              success: data.success,
              status: data.status,
              hasVideoUrl: !!data.videoUrl,
              videoUrl: data.videoUrl?.substring(0, 100),
              hasThumbnailUrl: !!data.thumbnailUrl,
              thumbnailUrl: data.thumbnailUrl?.substring(0, 100),
              durationMs: data.durationMs,
              error: data.error,
              fullResponse: data
            }, null, 2)
          );

          // Handle API errors (500 responses) as failed status
          if (!response.ok || !data.success) {
            console.error(
              "[EditSceneView] Video status API error:",
              JSON.stringify({ shotId, error: data.error, status: response.status }, null, 2)
            );
            setScene((prev) => ({
              ...prev,
              shots: prev.shots.map((s) =>
                s.id === shotId
                  ? {
                      ...s,
                      video: {
                        url: s.video?.url || "",
                        status: "failed" as const,
                        operationId: s.video?.operationId,
                        error: data.error || `API Error: ${response.status}`,
                      } as ShotVideo,
                    }
                  : s
              ),
            }));
            setPendingShots((prev) => {
              const next = new Map(prev);
              next.delete(shotId);
              return next;
            });
            toast.error(data.error || "Video generation failed");
            continue; // Skip to next pending shot
          }

          if (data.success) {
            if (data.status === "completed" && data.videoUrl) {
              console.log(
                "[EditSceneView] Video completed - checking for thumbnail:",
                JSON.stringify({ 
                  shotId, 
                  videoUrl: data.videoUrl, 
                  thumbnailUrl: data.thumbnailUrl,
                  durationMs: data.durationMs,
                }, null, 2)
              );

              // If server didn't generate thumbnail, generate client-side
              let thumbnailUrl = data.thumbnailUrl;
              if (!thumbnailUrl) {
                console.log(
                  "[EditSceneView] No server thumbnail, generating client-side:",
                  JSON.stringify({ videoUrl: data.videoUrl }, null, 2)
                );
                
                try {
                  const thumbnailResult = await generateThumbnailFromUrl(data.videoUrl);
                  
                  if (thumbnailResult.success && thumbnailResult.thumbnailBlob) {
                    // Upload thumbnail to S3
                    const thumbnailFile = new File(
                      [thumbnailResult.thumbnailBlob],
                      `thumbnail-${shotId}.jpg`,
                      { type: "image/jpeg" }
                    );
                    
                    const thumbnailUploadResult = await uploadFile(thumbnailFile, {
                      projectId,
                      sceneId: scene.id,
                      mediaType: "image",
                    });
                    
                    if (thumbnailUploadResult.success && thumbnailUploadResult.url) {
                      thumbnailUrl = thumbnailUploadResult.url;
                      console.log(
                        "[EditSceneView] Client-side thumbnail uploaded:",
                        JSON.stringify({ thumbnailUrl }, null, 2)
                      );
                    }
                  } else {
                    console.log(
                      "[EditSceneView] Client-side thumbnail generation failed:",
                      JSON.stringify({ error: thumbnailResult.error }, null, 2)
                    );
                  }
                } catch (thumbnailError) {
                  console.error(
                    "[EditSceneView] Error generating client-side thumbnail:",
                    JSON.stringify({ error: thumbnailError }, null, 2)
                  );
                  // Continue without thumbnail - video will still work
                }
              }

              console.log(
                "[EditSceneView] About to update scene state with completed video:",
                JSON.stringify({ 
                  shotId,
                  videoUrl: data.videoUrl,
                  thumbnailUrl
                }, null, 2)
              );

              setScene((prev) => {
                // Check if shot exists in current state
                const existingShot = prev.shots.find(s => s.id === shotId);
                console.log(
                  "[EditSceneView] Looking for shot in state:",
                  JSON.stringify({ 
                    shotId,
                    foundShot: !!existingShot,
                    totalShots: prev.shots.length,
                    shotIds: prev.shots.map(s => s.id)
                  }, null, 2)
                );

                if (!existingShot) {
                  console.error(
                    "[EditSceneView] Shot not found in state! Cannot update.",
                    JSON.stringify({ shotId, availableShots: prev.shots.map(s => s.id) }, null, 2)
                  );
                  return prev; // Don't update if shot not found
                }

                const updatedShots = prev.shots.map((s) =>
                  s.id === shotId
                    ? {
                        ...s,
                        video: {
                          ...s.video,
                          url: data.videoUrl,
                          thumbnailUrl, // Store thumbnail URL (server or client-generated)
                          status: "completed" as const,
                          durationMs: data.durationMs || 5000,
                        },
                        updatedAt: new Date().toISOString(),
                      }
                    : s
                );

                const updatedShot = updatedShots.find(s => s.id === shotId);
                console.log(
                  "[EditSceneView] Scene state updated successfully:",
                  JSON.stringify({ 
                    shotId,
                    updatedShot: updatedShot ? {
                      id: updatedShot.id,
                      videoUrl: updatedShot.video?.url,
                      videoThumbnailUrl: updatedShot.video?.thumbnailUrl,
                      videoStatus: updatedShot.video?.status
                    } : null
                  }, null, 2)
                );

                return {
                  ...prev,
                  shots: updatedShots,
                };
              });
              
              setPendingShots((prev) => {
                const next = new Map(prev);
                next.delete(shotId);
                console.log(
                  "[EditSceneView] Removed from pendingShots:",
                  JSON.stringify({ shotId, remainingPending: Array.from(next.keys()) }, null, 2)
                );
                return next;
              });
              
              console.log("[EditSceneView] Showing success toast for completed video");
              toast.success("Video generation completed!");
            } else if (data.status === "failed") {
              setScene((prev) => ({
                ...prev,
                shots: prev.shots.map((s) =>
                  s.id === shotId
                    ? {
                        ...s,
                        video: {
                          url: s.video?.url || "",
                          status: "failed" as const,
                          operationId: s.video?.operationId,
                          error: data.error,
                        } as ShotVideo,
                      }
                    : s
                ),
              }));
              setPendingShots((prev) => {
                const next = new Map(prev);
                next.delete(shotId);
                return next;
              });
              toast.error("Video generation failed");
            }
          }
        } catch (error) {
          console.error(
            "[EditSceneView] Error polling video status:",
            JSON.stringify({ shotId, error }, null, 2)
          );
        }
      }
    }, 5000);

    return () => clearInterval(pollInterval);
  }, [pendingShots, projectId, scene.id]);

  // ============================================================================
  // SCREENPLAY EDITING HANDLERS
  // ============================================================================

  const handleScreenplayEdit = () => {
    const elements = scene.screenplay
      ? parseScreenplayToElements(scene.screenplay)
      : [createScreenplayElement("action", "")];
    setScreenplayElements(elements.length > 0 ? elements : [createScreenplayElement("action", "")]);
    setFocusedElementIndex(0);
    setIsEditingScreenplay(true);
  };

  const handleScreenplaySave = () => {
    const plainText = elementsToText(screenplayElements);
    setScene({ ...scene, screenplay: plainText });
    setIsEditingScreenplay(false);
  };

  const handleScreenplayCancel = () => {
    setScreenplayElements([]);
    setIsEditingScreenplay(false);
  };

  const handleElementChange = useCallback((id: string, content: string) => {
    setScreenplayElements((prev) => prev.map((el) => (el.id === id ? { ...el, content } : el)));
  }, []);

  const handleElementTypeChange = useCallback((id: string, type: ScreenplayElementType) => {
    setScreenplayElements((prev) => prev.map((el) => (el.id === id ? { ...el, type } : el)));
  }, []);

  const handleElementDelete = useCallback((id: string) => {
    setScreenplayElements((prev) => {
      const index = prev.findIndex((el) => el.id === id);
      const filtered = prev.filter((el) => el.id !== id);
      if (filtered.length === 0) {
        return [createScreenplayElement("action", "")];
      }
      if (index > 0) {
        setFocusedElementIndex(index - 1);
      } else {
        setFocusedElementIndex(0);
      }
      return filtered;
    });
  }, []);

  const handleElementInsertAfter = useCallback((index: number, type: ScreenplayElementType) => {
    const newElement = createScreenplayElement(type, "");
    setScreenplayElements((prev) => {
      const updated = [...prev];
      updated.splice(index + 1, 0, newElement);
      return updated;
    });
    setFocusedElementIndex(index + 1);
  }, []);

  const getNextType = useCallback((currentType: ScreenplayElementType): ScreenplayElementType => {
    switch (currentType) {
      case "scene_heading":
        return "action";
      case "action":
        return "action";
      case "character":
        return "dialogue";
      case "parenthetical":
        return "dialogue";
      case "dialogue":
        return "character";
      case "transition":
        return "scene_heading";
      default:
        return "action";
    }
  }, []);

  const handleElementKeyDown = useCallback(
    (e: React.KeyboardEvent, index: number) => {
      const currentElement = screenplayElements[index];
      const target = e.target as HTMLTextAreaElement;
      const cursorAtStart = target.selectionStart === 0 && target.selectionEnd === 0;
      const cursorAtEnd = target.selectionStart === currentElement.content.length;

      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        const nextType = getNextType(currentElement.type);
        handleElementInsertAfter(index, nextType);
        return;
      }

      if (e.key === "Backspace" && currentElement.content === "" && screenplayElements.length > 1) {
        e.preventDefault();
        handleElementDelete(currentElement.id);
        return;
      }

      if (e.key === "Tab" && !e.shiftKey && currentElement.content === "") {
        e.preventDefault();
        const types: ScreenplayElementType[] = [
          "scene_heading",
          "action",
          "character",
          "dialogue",
          "parenthetical",
          "transition",
        ];
        const currentIndex = types.indexOf(currentElement.type);
        const nextIndex = (currentIndex + 1) % types.length;
        handleElementTypeChange(currentElement.id, types[nextIndex]);
        return;
      }

      if (e.key === "Tab" && !e.shiftKey && currentElement.content !== "") {
        if (index < screenplayElements.length - 1) {
          e.preventDefault();
          setFocusedElementIndex(index + 1);
        }
        return;
      }

      if (e.key === "Tab" && e.shiftKey) {
        if (index > 0) {
          e.preventDefault();
          setFocusedElementIndex(index - 1);
        }
        return;
      }

      if (e.key === "ArrowDown" && cursorAtEnd) {
        if (index < screenplayElements.length - 1) {
          e.preventDefault();
          setFocusedElementIndex(index + 1);
        }
        return;
      }

      if (e.key === "ArrowUp" && cursorAtStart) {
        if (index > 0) {
          e.preventDefault();
          setFocusedElementIndex(index - 1);
        }
        return;
      }
    },
    [
      screenplayElements,
      handleElementDelete,
      handleElementInsertAfter,
      handleElementTypeChange,
      getNextType,
    ]
  );

  const handleAddElement = (type: ScreenplayElementType) => {
    const newElement = createScreenplayElement(type, "");
    setScreenplayElements((prev) => [...prev, newElement]);
    setFocusedElementIndex(screenplayElements.length);
  };

  const registerElementRef = useCallback((id: string, ref: HTMLTextAreaElement | null) => {
    if (ref) {
      elementRefs.current.set(id, ref);
    } else {
      elementRefs.current.delete(id);
    }
  }, []);

  // ============================================================================
  // SHOT HANDLERS
  // ============================================================================

  const videoUploadInputRef = useRef<HTMLInputElement>(null);

  const _handleGenerateVideoClick = () => {
    setGeneratePrompt("");
    setStartFrameImage(undefined);
    setEndFrameImage(undefined);
    setReferenceImages([]);
    setGenerateMode("start-end-frames");
    setShowGenerateVideoDialog(true);
  };

  const handleImageUpload = async (file: File, type: "start" | "end" | "reference") => {
    setIsUploadingImage(true);
    try {
      const result = await uploadFile(file, {
        projectId,
        sceneId: scene.id,
        mediaType: "image",
      });

      if (result.success && result.url) {
        if (type === "start") {
          setStartFrameImage(result.url);
        } else if (type === "end") {
          setEndFrameImage(result.url);
        } else if (type === "reference") {
          if (referenceImages.length < 3) {
            setReferenceImages([...referenceImages, result.url]);
          }
        }
      } else {
        toast.error(result.error || "Failed to upload image");
      }
    } catch (error) {
      console.error("[EditSceneView] Image upload error:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to upload image");
    } finally {
      setIsUploadingImage(false);
    }
  };

  const handleGenerateVideoSubmit = async () => {
    if (!generatePrompt.trim()) {
      toast.error("Please enter a prompt");
      return;
    }

    // Validate based on mode
    if (generateMode === "start-end-frames" && (!startFrameImage || !endFrameImage)) {
      toast.error("Please upload both start and end frame images");
      return;
    }
    if (generateMode === "ingredients" && referenceImages.length === 0) {
      toast.error("Please upload at least one reference image");
      return;
    }

    setIsGeneratingVideo(true);
    const loadingToast = toast.loading("Starting video generation...");

    try {
      // Create a new shot first
      const newShot = createNewShot(scene.shots.length);
      newShot.prompt = generatePrompt;
      newShot.sourceType = "generated";
      newShot.generationMode =
        generateMode === "start-end-frames"
          ? ("start-end-frame" as GenerationMode)
          : ("reference-images" as GenerationMode);
      newShot.startFrameImage = startFrameImage;
      newShot.endFrameImage = generateMode === "start-end-frames" ? endFrameImage : undefined;
      newShot.referenceImages = generateMode === "ingredients" ? referenceImages : undefined;

      // Add shot to scene first
      setScene((prev) => ({
        ...prev,
        shots: [...prev.shots, newShot],
      }));

      // Generate video
      const response = await fetch("/api/ai/generate-video", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt: generatePrompt,
          projectId,
          sceneId: scene.id,
          shotId: newShot.id,
          aspectRatio: "16:9",
          durationSeconds: 8,
          generationMode: newShot.generationMode,
          startFrameImage: newShot.startFrameImage,
          endFrameImage: newShot.endFrameImage,
          referenceImages: newShot.referenceImages,
        }),
      });

      const data = await response.json();

      if (data.success && data.video) {
        // Update the shot with the pending video info
        setScene((prev) => ({
          ...prev,
          shots: prev.shots.map((s) =>
            s.id === newShot.id
              ? {
                  ...s,
                  video: {
                    url: "",
                    status: "processing" as const,
                    operationId: data.video.operationId,
                  },
                }
              : s
          ),
        }));

        // Add to pending shots for polling (includes thumbnailUrl for HEAD check)
        setPendingShots((prev) => {
          const next = new Map(prev);
          next.set(newShot.id, { 
            operationId: data.video.operationId,
            thumbnailUrl: data.thumbnailUrl,
            thumbnailPath: data.thumbnailPath,
          });
          return next;
        });

        toast.success("Video generation started!", { id: loadingToast });
        setShowGenerateVideoDialog(false);
        // Reset form
        setGeneratePrompt("");
        setStartFrameImage(undefined);
        setReferenceImages([]);
      } else {
        toast.error(data.error || "Failed to start video generation", { id: loadingToast });
      }
    } catch (error) {
      console.error("[EditSceneView] Error generating video:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to start video generation", { id: loadingToast });
    } finally {
      setIsGeneratingVideo(false);
    }
  };

  const _handleUploadVideoClick = () => {
    videoUploadInputRef.current?.click();
  };

  const handleVideoFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const loadingToast = toast.loading("Uploading video...");

    try {
      const result = await uploadFile(file, {
        projectId,
        sceneId: scene.id,
        mediaType: "video",
        onProgress: (percent) => {
          // Update toast with progress for large files
          if (file.size > 5 * 1024 * 1024) {
            toast.loading(`Uploading video... ${percent}%`, { id: loadingToast });
          }
        },
      });

      console.log("[EditSceneView] Upload result:", JSON.stringify(result, null, 2));
      
      if (result.success && result.url) {
        // Get video duration (default to 5 seconds if not available)
        let durationMs = 5000;
        try {
          const video = document.createElement("video");
          video.preload = "metadata";
          video.src = URL.createObjectURL(file);
          await new Promise((resolve, reject) => {
            video.onloadedmetadata = () => {
              durationMs = Math.round(video.duration * 1000);
              URL.revokeObjectURL(video.src);
              resolve(undefined);
            };
            video.onerror = reject;
          });
        } catch (error) {
          console.error(
            "[EditSceneView] Error getting video duration:",
            JSON.stringify({ error }, null, 2)
          );
          // Use default duration
        }

        // Generate thumbnail client-side from the original file
        let thumbnailUrl: string | undefined;
        try {
          console.log(
            "[EditSceneView] Generating thumbnail client-side:",
            JSON.stringify({ 
              fileName: file.name,
              fileSize: file.size,
              durationMs 
            }, null, 2)
          );

          const thumbnailResult = await generateThumbnailFromFile(file);
          
          if (thumbnailResult.success && thumbnailResult.thumbnailBlob) {
            // Update duration from video metadata
            if (thumbnailResult.durationMs) {
              durationMs = thumbnailResult.durationMs;
            }
            
            // Upload thumbnail to S3
            const thumbnailFile = new File(
              [thumbnailResult.thumbnailBlob],
              `thumbnail-${Date.now()}.jpg`,
              { type: "image/jpeg" }
            );
            
            const thumbnailUploadResult = await uploadFile(thumbnailFile, {
              projectId,
              sceneId: scene.id,
              mediaType: "image",
            });
            
            if (thumbnailUploadResult.success && thumbnailUploadResult.url) {
              thumbnailUrl = thumbnailUploadResult.url;
              console.log(
                "[EditSceneView] Thumbnail uploaded:",
                JSON.stringify({ thumbnailUrl, durationMs }, null, 2)
              );
            }
          } else {
            console.log(
              "[EditSceneView] Thumbnail generation failed:",
              JSON.stringify({ error: thumbnailResult.error }, null, 2)
            );
          }
        } catch (thumbnailError) {
          console.error(
            "[EditSceneView] Error generating thumbnail:",
            JSON.stringify({ error: thumbnailError }, null, 2)
          );
          // Continue without thumbnail - video will still work
        }

        // Create a new shot with the uploaded video
        const newShot = createNewShot(scene.shots.length);
        newShot.sourceType = "uploaded";
        newShot.video = {
          url: result.url,
          status: "completed",
          thumbnailUrl, // Include thumbnail if generated
          durationMs,
        };
        newShot.updatedAt = new Date().toISOString();
        
        console.log("[EditSceneView] Creating shot with video:", JSON.stringify({
          shotId: newShot.id,
          videoUrl: newShot.video.url,
          videoThumbnailUrl: newShot.video.thumbnailUrl,
          durationMs: newShot.video.durationMs
        }, null, 2));

        setScene((prev) => ({
          ...prev,
          shots: [...prev.shots, newShot],
        }));
        toast.success("Video uploaded successfully!", { id: loadingToast });
      } else {
        toast.error(result.error || "Failed to upload video", { id: loadingToast });
      }
    } catch (error) {
      console.error("[EditSceneView] Video upload error:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to upload video", { id: loadingToast });
    } finally {
      if (e.target) {
        e.target.value = "";
      }
    }
  };

  const handleShotClick = (shot: Shot) => {
    scenePlayerRef.current?.pause();
    setSelectedShot(shot);
    setShowShotEditor(true);
  };

  const handleAddShot = () => {
    scenePlayerRef.current?.pause();
    const newShot = createNewShot(scene.shots.length);
    setSelectedShot(newShot);
    setShowShotEditor(true);
  };

  const handleShotSave = (updatedShot: Shot) => {
    setScene((prev) => {
      const existingIndex = prev.shots.findIndex((s) => s.id === updatedShot.id);
      if (existingIndex >= 0) {
        // Update existing shot
        const newShots = [...prev.shots];
        newShots[existingIndex] = updatedShot;
        return { ...prev, shots: newShots };
      } else {
        // Add new shot
        return { ...prev, shots: [...prev.shots, updatedShot] };
      }
    });
    setShowShotEditor(false);
    setSelectedShot(null);
  };

  const handleShotDelete = (shotId: string) => {
    const shotToDelete = scene.shots.find((s) => s.id === shotId);
    
    console.log(
      "[EditSceneView] handleShotDelete called:",
      JSON.stringify({
        shotId,
        shotFound: !!shotToDelete,
        shotHasVideo: !!shotToDelete?.video,
        videoStatus: shotToDelete?.video?.status,
        videoUrl: shotToDelete?.video?.url?.substring(0, 100),
        currentRemovedShotsCount: scene.removedShots?.length || 0,
      }, null, 2)
    );
    
    setScene((prev) => {
      const updatedShots = prev.shots.filter((s) => s.id !== shotId).map((s, i) => ({ ...s, order: i }));
      const updatedRemovedShots = [...(prev.removedShots || [])];
      
      if (shotToDelete && shotToDelete.video?.url && shotToDelete.video.status === "completed") {
        // Shot has a completed video - move to removed shots instead of deleting
        updatedRemovedShots.push(shotToDelete);
        console.log(
          "[EditSceneView] Adding shot to removedShots:",
          JSON.stringify({
            shotId: shotToDelete.id,
            prompt: shotToDelete.prompt?.substring(0, 50),
            videoUrl: shotToDelete.video.url.substring(0, 100),
            newRemovedShotsCount: updatedRemovedShots.length,
          }, null, 2)
        );
        toast.success("Shot moved to Media Library");
      }
      
      return {
        ...prev,
        shots: updatedShots,
        removedShots: updatedRemovedShots,
      };
    });
    setShowShotEditor(false);
    setSelectedShot(null);
  };

  // Save old video to media library when replacing a shot (without removing the shot from scene)
  const handleSaveVideoToMediaLibrary = (shot: Shot) => {
    console.log(
      "[EditSceneView] handleSaveVideoToMediaLibrary called:",
      JSON.stringify({
        shotId: shot.id,
        hasVideo: !!shot.video,
        videoStatus: shot.video?.status,
        videoUrl: shot.video?.url?.substring(0, 100),
        currentRemovedShotsCount: scene.removedShots?.length || 0,
      }, null, 2)
    );
    
    if (shot.video?.url && shot.video.status === "completed") {
      // Create a copy with a new unique ID to avoid duplicate key conflicts
      const mediaLibraryShot: Shot = {
        ...shot,
        id: `media-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
      };
      console.log(
        "[EditSceneView] Saving video to media library:",
        JSON.stringify({ 
          originalShotId: shot.id,
          newMediaLibraryId: mediaLibraryShot.id,
          videoUrl: shot.video.url.substring(0, 100),
          thumbnailUrl: shot.video.thumbnailUrl?.substring(0, 100),
          currentRemovedShotsCount: scene.removedShots?.length || 0,
        }, null, 2)
      );
      setScene((prev) => {
        const newRemovedShots = [...(prev.removedShots || []), mediaLibraryShot];
        console.log(
          "[EditSceneView] Updated removedShots in scene state:",
          JSON.stringify({
            previousCount: prev.removedShots?.length || 0,
            newCount: newRemovedShots.length,
            addedShotId: mediaLibraryShot.id,
          }, null, 2)
        );
        return {
          ...prev,
          removedShots: newRemovedShots,
        };
      });
      toast.success("Old video saved to Media Library");
    } else {
      console.log(
        "[EditSceneView] Skipping save to media library - video not completed:",
        JSON.stringify({
          shotId: shot.id,
          hasVideo: !!shot.video,
          videoStatus: shot.video?.status,
        }, null, 2)
      );
    }
  };

  // Show confirmation dialog before deleting
  const handleRemoveFromLibraryClick = (shotId: string) => {
    const shot = removedShots.find((s) => s.id === shotId);
    if (shot) {
      setShotToDelete(shot);
    }
  };

  // Permanently remove a shot from the media library and delete video from S3
  const handleRemoveFromLibrary = async () => {
    if (!shotToDelete) return;

    const shotId = shotToDelete.id;

    // If video is playing, pause it first
    if (playingVideoId === shotId) {
      const videoElement = document.querySelector(`video[data-shot-id="${shotId}"]`) as HTMLVideoElement;
      videoElement?.pause();
      setPlayingVideoId(null);
    }

    // Delete video from S3 if it exists
    if (shotToDelete.video?.url) {
      try {
        const response = await fetch("/api/scenes/delete-video", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            videoUrl: shotToDelete.video.url,
            thumbnailUrl: shotToDelete.video.thumbnailUrl,
          }),
        });

        if (!response.ok) {
          const errorData = await response.json().catch(() => ({}));
          console.error(
            "[EditSceneView] Failed to delete video from S3:",
            JSON.stringify({ shotId, error: errorData.error || "Unknown error" }, null, 2)
          );
          toast.error("Failed to delete video. It may have already been deleted.");
          setShotToDelete(null);
          return;
        } else {
          console.log(
            "[EditSceneView] Video deleted from S3:",
            JSON.stringify({ shotId, videoUrl: shotToDelete.video.url.substring(0, 100) }, null, 2)
          );
        }
      } catch (error) {
        console.error(
          "[EditSceneView] Error deleting video:",
          JSON.stringify({ shotId, error: error instanceof Error ? error.message : String(error) }, null, 2)
        );
        toast.error("Failed to delete video. Please try again.");
        setShotToDelete(null);
        return; // Don't remove from UI if deletion failed
      }
    }

    // Remove from scene state
    setScene((prev) => {
      const newRemovedShots = (prev.removedShots || []).filter((s) => s.id !== shotId);
      console.log(
        "[EditSceneView] Removing shot from removedShots:",
        JSON.stringify({
          shotId,
          previousCount: prev.removedShots?.length || 0,
          newCount: newRemovedShots.length,
        }, null, 2)
      );
      return {
        ...prev,
        removedShots: newRemovedShots,
      };
    });
    setShotToDelete(null);
    toast.success("Video permanently deleted");
  };

  // Add a shot from media library to the scene as a new shot
  const handleAddShotFromLibrary = (shot: Shot) => {
    // Create a new shot with a new ID but keep the video and other properties
    const newShot: Shot = {
      ...shot,
      id: `shot-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
      order: scene.shots.length,
      updatedAt: new Date().toISOString(),
    };
    
    setScene((prev) => ({
      ...prev,
      shots: [...prev.shots, newShot],
    }));
    setShowMediaLibrary(false);
    toast.success("Shot added to timeline");
  };

  // Poll for composition status
  const pollCompositionStatus = useCallback(async () => {
    try {
      const response = await fetch(`/api/scenes/${scene.id}/compose?projectId=${projectId}`);
      const data = await response.json();
      
      // Update progress and stage
      if (data.progress !== null && data.progress !== undefined) {
        setRenderProgress(data.progress);
      }
      if (data.stage) {
        setRenderStage(data.stage);
      }
      
      if (data.status === "completed" && data.compositeVideo) {
        setScene((prev) => ({
          ...prev,
          compositeStatus: "completed",
          compositeVideo: data.compositeVideo,
          compositeError: undefined,
        }));
        setRenderProgress(null);
        setRenderStage(null);
        toast.success("Video rendering complete!");
        return true; // Stop polling
      } else if (data.status === "failed") {
        setScene((prev) => ({
          ...prev,
          compositeStatus: "failed",
          compositeError: data.error || "Unknown error",
        }));
        setRenderProgress(null);
        setRenderStage(null);
        toast.error("Video rendering failed");
        return true; // Stop polling
      }
      return false; // Continue polling
    } catch (error) {
      console.error(
        "[EditSceneView] Poll composition status error:",
        JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
      );
      return false;
    }
  }, [scene.id, projectId]);

  // Poll for composition status when processing
  useEffect(() => {
    if (scene.compositeStatus === "processing") {
      // Poll immediately on mount
      pollCompositionStatus();
      
      const interval = setInterval(async () => {
        const shouldStop = await pollCompositionStatus();
        if (shouldStop) {
          clearInterval(interval);
        }
      }, 1500); // Poll every 1.5 seconds for smoother progress updates

      return () => clearInterval(interval);
    } else {
      // Clear progress when not processing
      setRenderProgress(null);
      setRenderStage(null);
    }
  }, [scene.compositeStatus, pollCompositionStatus]);

  // Render scene - compose all shots and audio tracks into a single video
  const handleRenderScene = async () => {
    setIsRendering(true);
    try {
      const response = await fetch(`/api/scenes/${scene.id}/compose`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ projectId }),
      });
      const data = await response.json();
      if (data.success) {
        toast.success("Rendering started! This may take a few minutes.");
        // Update scene state to show processing status
        setScene((prev) => ({
          ...prev,
          compositeStatus: "processing",
          compositeVideo: {
            ...(prev.compositeVideo || { url: "", durationMs: 0, renderedAt: "" }),
            jobId: data.jobId,
          },
        }));
      } else {
        toast.error(data.error || "Failed to start rendering");
      }
    } catch (error) {
      console.error(
        "[EditSceneView] Render scene error:",
        JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
      );
      toast.error("Failed to start rendering");
    } finally {
      setIsRendering(false);
    }
  };

  const handleDownloadVideo = useCallback(async (videoUrl: string) => {
    try {
      toast.info("Downloading video...");
      const response = await fetch(videoUrl);
      if (!response.ok) {
        throw new Error("Failed to fetch video");
      }
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `scene-${scene.sceneNumber}-${Date.now()}.mp4`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      window.URL.revokeObjectURL(url);
      toast.success("Video downloaded!");
    } catch (error) {
      console.error(
        "[EditSceneView] Download video error:",
        JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
      );
      toast.error("Failed to download video");
    }
  }, [scene.sceneNumber]);

  const handleExportSourceVideos = useCallback(async () => {
    try {
      setIsExporting(true);
      setExportProgress({ current: 0, total: 0 });

      // Collect all source video URLs from shots
      const sourceVideos: Array<{ url: string; filename: string }> = [];
      
      scene.shots.forEach((shot, index) => {
        // Use originalVideo if it exists (original source before trimming), otherwise use video
        const videoUrl = shot.originalVideo?.url || shot.video?.url;
        if (videoUrl && shot.video?.status === "completed") {
          const extension = videoUrl.split('.').pop()?.split('?')[0] || 'mp4';
          sourceVideos.push({
            url: videoUrl,
            filename: `shot-${shot.order + 1}-${shot.id.substring(0, 8)}.${extension}`,
          });
        }
      });

      if (sourceVideos.length === 0) {
        toast.error("No source videos found to export");
        setIsExporting(false);
        setExportProgress(null);
        return;
      }

      setExportProgress({ current: 0, total: sourceVideos.length });

      // Create zip file
      const zip = new JSZip();

      // Download each video and add to zip
      for (let i = 0; i < sourceVideos.length; i++) {
        const { url, filename } = sourceVideos[i];
        try {
          toast.info(`Downloading ${filename}...`);
          const response = await fetch(url);
          if (!response.ok) {
            throw new Error(`Failed to fetch ${filename}`);
          }
          const blob = await response.blob();
          zip.file(filename, blob);
          setExportProgress({ current: i + 1, total: sourceVideos.length });
        } catch (error) {
          console.error(
            `[EditSceneView] Failed to download ${filename}:`,
            JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
          );
          toast.error(`Failed to download ${filename}`);
        }
      }

      // Generate zip file
      toast.info("Creating zip file...");
      const zipBlob = await zip.generateAsync({ type: "blob" });
      
      // Download zip
      const zipUrl = window.URL.createObjectURL(zipBlob);
      const a = document.createElement("a");
      a.href = zipUrl;
      a.download = `scene-${scene.sceneNumber}-source-videos-${Date.now()}.zip`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      window.URL.revokeObjectURL(zipUrl);

      toast.success(`Exported ${sourceVideos.length} source video(s) as zip!`);
      setShowExportDialog(false);
    } catch (error) {
      console.error(
        "[EditSceneView] Export source videos error:",
        JSON.stringify({ error: error instanceof Error ? error.message : String(error) }, null, 2)
      );
      toast.error("Failed to export source videos");
    } finally {
      setIsExporting(false);
      setExportProgress(null);
    }
  }, [scene.shots, scene.sceneNumber]);

  const handleShotReorder = (shotIds: string[]) => {
    setScene((prev) => {
      const shotMap = new Map(prev.shots.map((s) => [s.id, s]));
      const reorderedShots = shotIds
        .map((id, index) => {
          const shot = shotMap.get(id);
          if (shot) {
            return { ...shot, order: index };
          }
          return null;
        })
        .filter((s): s is Shot => s !== null);
      return { ...prev, shots: reorderedShots };
    });
  };

  const handleGenerateVideo = async (shot: Shot) => {
    // Check if video generation is enabled (localhost/development only)
    if (!isVideoGenerationEnabled()) {
      toast.error("Video generation is only available in development mode");
      return;
    }

    const loadingToast = toast.loading("Starting video generation...");

    // First, save the shot configuration (without processing status) so changes aren't lost if API fails
    const shotWithoutProcessing: Shot = {
      ...shot,
      video: shot.video?.url ? shot.video : undefined, // Preserve existing video if any
    };
    setScene((prev) => {
      const existingIndex = prev.shots.findIndex((s) => s.id === shot.id);
      if (existingIndex >= 0) {
        // Update existing shot
        const newShots = [...prev.shots];
        newShots[existingIndex] = shotWithoutProcessing;
        return { ...prev, shots: newShots };
      } else {
        // Add new shot (this happens when user clicks Generate on a new shot)
        console.log(
          "[handleGenerateVideo] Adding new shot to scene:",
          JSON.stringify({ shotId: shot.id }, null, 2)
        );
        return { ...prev, shots: [...prev.shots, shotWithoutProcessing] };
      }
    });

    try {
      const response = await fetch("/api/ai/generate-video", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt: shot.prompt,
          projectId,
          sceneId: scene.id,
          shotId: shot.id,
          aspectRatio: "16:9",
          durationSeconds: shot.durationSeconds || 8,
          generationMode: shot.generationMode,
          startFrameImage: shot.startFrameImage,
          endFrameImage: shot.endFrameImage,
          referenceImages: shot.referenceImages,
        }),
      });

      const data = await response.json();

      if (data.success && data.video) {
        // Update the shot with the pending video info
        const shotWithProcessing: Shot = {
          ...shot,
          video: {
            url: "",
            status: "processing" as const,
            operationId: data.video.operationId,
          },
        };
        setScene((prev) => {
          const existingIndex = prev.shots.findIndex((s) => s.id === shot.id);
          if (existingIndex >= 0) {
            // Update existing shot
            const newShots = [...prev.shots];
            newShots[existingIndex] = shotWithProcessing;
            return { ...prev, shots: newShots };
          } else {
            // Add new shot (shouldn't happen here but just in case)
            return { ...prev, shots: [...prev.shots, shotWithProcessing] };
          }
        });

        // Add to pending shots for polling (includes thumbnailUrl for HEAD check)
        setPendingShots((prev) => {
          const next = new Map(prev);
          next.set(shot.id, {
            operationId: data.video.operationId,
            thumbnailUrl: data.thumbnailUrl,
            thumbnailPath: data.thumbnailPath,
          });
          return next;
        });

        toast.success("Video generation started!", { id: loadingToast });
        setShowShotEditor(false);
        setSelectedShot(null);
      } else {
        toast.error(data.error || "Failed to start video generation", { id: loadingToast });
      }
    } catch (error) {
      console.error("[EditSceneView] Error generating video:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to start video generation", { id: loadingToast });
    }
  };

  // ============================================================================
  // AUDIO TRACK HANDLERS
  // ============================================================================

  const handleAddAudioTrack = () => {
    setSelectedAudioTrack(null);
    setShowAudioTrackEditor(true);
  };

  const handleAudioTrackClick = (track: AudioTrack) => {
    setSelectedAudioTrack(track);
    setShowAudioTrackEditor(true);
  };

  const handleAudioTrackSave = (track: AudioTrack) => {
    setScene((prev) => {
      const existingIndex = prev.audioTracks.findIndex((t) => t.id === track.id);
      if (existingIndex >= 0) {
        // Updating existing track - keep its position
        const newTracks = [...prev.audioTracks];
        newTracks[existingIndex] = track;
        return { ...prev, audioTracks: newTracks };
      } else {
        // Adding new track - position at end of timeline
        // Calculate timeline end by summing all shot durations
        const timelineEndMs = prev.shots.reduce((total, shot) => {
          return total + getEffectiveDuration(shot);
        }, 0);
        
        const positionedTrack: AudioTrack = {
          ...track,
          startTimeMs: timelineEndMs,
        };
        
        return { ...prev, audioTracks: [...prev.audioTracks, positionedTrack] };
      }
    });
    setShowAudioTrackEditor(false);
    setSelectedAudioTrack(null);
  };

  const handleAudioTrackDelete = (trackId: string) => {
    setScene((prev) => ({
      ...prev,
      audioTracks: prev.audioTracks.filter((t) => t.id !== trackId),
    }));
    setShowAudioTrackEditor(false);
    setSelectedAudioTrack(null);
  };

  const handleAudioTrackVolumeChange = (trackId: string, volume: number) => {
    setScene((prev) => ({
      ...prev,
      audioTracks: prev.audioTracks.map((t) => (t.id === trackId ? { ...t, volume } : t)),
    }));
  };

  const handleAudioTrackMuteToggle = (trackId: string) => {
    setScene((prev) => ({
      ...prev,
      audioTracks: prev.audioTracks.map((t) => (t.id === trackId ? { ...t, muted: !t.muted } : t)),
    }));
  };

  // Handle detach audio from shot - add extracted audio as new track
  const handleDetachAudio = (audioTrack: AudioTrack) => {
    setScene((prev) => {
      // Calculate the shot's timeline position if sourceVideoShotId is provided
      let positionedTrack = audioTrack;
      if (audioTrack.sourceVideoShotId) {
        const sourceShot = prev.shots.find(s => s.id === audioTrack.sourceVideoShotId);
        if (sourceShot) {
          // Calculate timeline position by summing durations of shots before this one
          const shotStartMs = prev.shots
            .filter(s => s.order < sourceShot.order)
            .reduce((total, shot) => total + getEffectiveDuration(shot), 0);
          
          // Calculate shot end position (start + duration)
          const shotDurationMs = getEffectiveDuration(sourceShot);
          const shotEndMs = shotStartMs + shotDurationMs;
          
          // Position audio at shot end (for overlap workflow)
          positionedTrack = {
            ...audioTrack,
            startTimeMs: shotEndMs,
          };
        }
      }
      
      return {
        ...prev,
        audioTracks: [...prev.audioTracks, positionedTrack],
      };
    });
  };

  // Handle audio track position change (dragging)
  const handleAudioTrackMove = (trackId: string, newStartTimeMs: number) => {
    setScene((prev) => ({
      ...prev,
      audioTracks: prev.audioTracks.map((t) =>
        t.id === trackId ? { ...t, startTimeMs: newStartTimeMs, updatedAt: new Date().toISOString() } : t
      ),
    }));
  };

  // Handle master volume change
  const handleMasterVolumeChange = (volume: number[]) => {
    setScene((prev) => ({
      ...prev,
      masterVolume: volume[0],
    }));
  };

  // Handle create overlap - trim video so it starts when audio starts
  const handleCreateOverlap = (audioTrack: AudioTrack) => {
    if (!audioTrack.sourceVideoShotId) return;
    
    setScene((prev) => {
      const sourceShot = prev.shots.find(s => s.id === audioTrack.sourceVideoShotId);
      if (!sourceShot) return prev;
      
      // Calculate shot's timeline start position
      const shotStartMs = prev.shots
        .filter(s => s.order < sourceShot.order)
        .reduce((total, shot) => total + getEffectiveDuration(shot), 0);
      
      // Calculate how much to trim from video start
      // Audio starts at audioTrack.startTimeMs, video should start there too
      const audioStartMs = audioTrack.startTimeMs;
      const trimAmount = audioStartMs - shotStartMs;
      
      if (trimAmount > 0) {
        // Update shot with trim from start
        const updatedShots = prev.shots.map((s) =>
          s.id === sourceShot.id
            ? {
                ...s,
                trimStartMs: (s.trimStartMs || 0) + trimAmount,
                updatedAt: new Date().toISOString(),
              }
            : s
        );
        
        return { ...prev, shots: updatedShots };
      }
      
      return prev;
    });
  };

  // ============================================================================
  // AUTO-SAVE LOGIC
  // ============================================================================

  const saveScene = useCallback(async () => {
    if (!scene.title.trim()) {
      return;
    }

    const currentSceneJson = JSON.stringify(scene);
    if (currentSceneJson === lastSavedSceneRef.current) {
      return; // No changes to save
    }

    setSaveStatus("saving");

    try {
      const updatedScene = {
        ...scene,
        updatedAt: new Date().toISOString(),
      };

      const response = await fetch(`/api/scenes/${scene.id}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          projectId,
          scene: updatedScene,
        }),
      });

      const data = await response.json();

      if (data.success) {
        lastSavedSceneRef.current = currentSceneJson;
        setSaveStatus("saved");
        // Reset to idle after showing "saved" briefly
        setTimeout(() => setSaveStatus("idle"), 2000);
      } else {
        setSaveStatus("error");
        toast.error(data.error || "Failed to save scene");
      }
    } catch (error) {
      console.error("[EditSceneView] Error saving scene:", JSON.stringify({ error }, null, 2));
      setSaveStatus("error");
      toast.error("Failed to save scene");
    }
  }, [scene, projectId]);

  // Auto-save effect with debounce
  useEffect(() => {
    const currentSceneJson = JSON.stringify(scene);
    if (currentSceneJson === lastSavedSceneRef.current) {
      return; // No changes
    }

    // Clear existing timeout
    if (saveTimeoutRef.current) {
      clearTimeout(saveTimeoutRef.current);
    }

    // Set new timeout for auto-save (1.5 second debounce)
    saveTimeoutRef.current = setTimeout(() => {
      saveScene();
    }, 1500);

    return () => {
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current);
      }
    };
  }, [scene, saveScene]);

  // Save on unmount if there are pending changes
  useEffect(() => {
    return () => {
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current);
      }
      // Trigger immediate save on unmount
      const currentSceneJson = JSON.stringify(scene);
      if (currentSceneJson !== lastSavedSceneRef.current) {
        saveScene();
      }
    };
  }, [scene, saveScene]);

  const handleDelete = async () => {
    setIsDeleting(true);
    const loadingToast = toast.loading("Deleting scene...");

    try {
      const response = await fetch(`/api/scenes/${scene.id}`, {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ projectId }),
      });

      const data = await response.json();

      if (data.success) {
        toast.success("Scene deleted", { id: loadingToast });
        router.push(`/dashboard/projects/${projectId}/edit`);
      } else {
        toast.error(data.error || "Failed to delete scene", { id: loadingToast });
      }
    } catch (error) {
      console.error("[EditSceneView] Error deleting scene:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to delete scene", { id: loadingToast });
    } finally {
      setIsDeleting(false);
      setShowDeleteDialog(false);
    }
  };

  const _toggleCharacter = (characterName: string) => {
    const currentCharacters = scene.characters || [];
    const isSelected = currentCharacters.includes(characterName);

    setScene({
      ...scene,
      characters: isSelected
        ? currentCharacters.filter((c) => c !== characterName)
        : [...currentCharacters, characterName],
    });
  };

  return (
    <div className="min-h-screen bg-background flex flex-col pt-20">
      {/* Header */}
      <div className="sticky top-0 z-10 border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="container mx-auto px-4 lg:px-8 pb-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link
                href={`/dashboard/projects/${projectId}/edit`}
                className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground transition-colors"
              >
                <ArrowLeft className="h-4 w-4" />
                <span className="text-sm font-medium">Back to Project</span>
              </Link>
              <div className="h-6 w-px bg-border" />
              <div>
                <h1 className="text-lg font-bold flex items-center gap-2">
                  <Film className="h-5 w-5 text-primary" />
                  Scene {scene.sceneNumber}: {scene.title}
                </h1>
              </div>
            </div>
            {/* Auto-save status indicator */}
            <div className="flex items-center gap-2 text-sm">
              {saveStatus === "saving" && (
                <span className="flex items-center gap-1.5 text-muted-foreground">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Saving...
                </span>
              )}
              {saveStatus === "saved" && (
                <span className="flex items-center gap-1.5 text-green-600">
                  <Check className="h-3.5 w-3.5" />
                  Saved
                </span>
              )}
              {saveStatus === "error" && (
                <span className="flex items-center gap-1.5 text-destructive">
                  Failed to save
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="flex-1 container mx-auto px-4 lg:px-8 py-6">
        <div className="grid lg:grid-cols-4 gap-6">
          {/* Left Sidebar - Scene Info */}
          <div className="space-y-6 pr-6">
            {/* Scene Title */}
            <div className="space-y-2">
              <Label htmlFor="scene-title">Scene Title *</Label>
              <Input
                id="scene-title"
                placeholder="Enter scene title"
                value={scene.title}
                onChange={(e) => {
                  setScene({ ...scene, title: e.target.value });
                }}
                className="bg-background"
              />
            </div>

            {/* Location */}
            {locations.length > 0 && (
              <div className="space-y-2">
                <Label htmlFor="scene-location">Location</Label>
                <Select
                  value={scene.locationId || "none"}
                  onValueChange={(value) => {
                    setScene({ ...scene, locationId: value === "none" ? undefined : value });
                  }}
                >
                  <SelectTrigger className="bg-background">
                    <SelectValue placeholder="Select location..." />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">No location</SelectItem>
                    {locations.map((location) => (
                      <SelectItem key={location.name} value={location.name}>
                        {location.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}

            {/* Screenplay */}
            <div className="space-y-2">
              <div className="flex items-center justify-between gap-2">
                <Label>Screenplay</Label>
                <button
                  type="button"
                  onClick={handleScreenplayEdit}
                  className="inline-flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
                >
                  <Edit className="h-3.5 w-3.5" />
                  <span>{scene.screenplay ? "Edit" : "Add"}</span>
                </button>
              </div>
              {scene.screenplay ? (
                <div className="rounded-md border border-input bg-background overflow-hidden max-h-[600px] overflow-y-auto">
                  <div className="px-4 pb-4 font-mono text-sm leading-relaxed space-y-1">
                    {(() => {
                      const elements = parseScreenplayToElements(scene.screenplay);
                      return elements.map((element, index) => {
                        // Add extra spacing when action follows dialogue
                        const prevElement = index > 0 ? elements[index - 1] : null;
                        const needsExtraSpacing =
                          element.type === "action" && prevElement?.type === "dialogue";

                        return (
                          <div
                            key={element.id || index}
                            className={cn(
                              "py-0.5",
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
                          </div>
                        );
                      });
                    })()}
                  </div>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={handleScreenplayEdit}
                  className="w-full rounded-md border border-input bg-background cursor-pointer hover:bg-muted/30 transition-colors"
                >
                  <div className="flex items-center gap-2 py-3 px-3">
                    <Plus className="h-4 w-4 text-muted-foreground" />
                    <p className="text-sm text-muted-foreground group-hover:text-foreground transition-colors">
                      Add screenplay...
                    </p>
                  </div>
                </button>
              )}
            </div>

            {/* Characters */}
            {characters.length > 0 && scene.characters.length > 0 && (
              <div className="space-y-2">
                <Label>Characters</Label>
                <div className="flex flex-wrap gap-2">
                  {characters
                    .filter((character) => scene.characters.includes(character.name))
                    .map((character) => {
                      return (
                        <div
                          key={character.name}
                          className="px-2 py-1 rounded-sm text-xs font-medium bg-foreground/20 text-foreground/90"
                        >
                          {character.name}
                        </div>
                      );
                    })}
                </div>
              </div>
            )}

            {/* Reference Images */}
            {scene.generatedImages && scene.generatedImages.length > 0 && (
              <Card>
                <CardHeader className="py-3">
                  <CardTitle className="text-sm flex items-center gap-2">
                    <ImageIcon className="h-4 w-4 text-primary" />
                    Reference Images
                  </CardTitle>
                </CardHeader>
                <CardContent className="pt-0">
                  <div className="grid grid-cols-2 gap-2">
                    {scene.generatedImages.slice(0, 4).map((image) => (
                      <div
                        key={image.id}
                        className="relative aspect-video rounded-lg overflow-hidden border border-border bg-muted/30"
                      >
                        <Image
                          src={image.imageUrl}
                          alt={image.prompt}
                          fill
                          className="object-cover"
                        />
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>
            )}
          </div>

          {/* Main Area - Player & Timeline */}
          <div className="lg:col-span-3 space-y-2">
            <div className="w-full mx-auto">
              <ScenePlayer ref={scenePlayerRef} shots={scene.shots} audioTracks={scene.audioTracks} masterVolume={scene.masterVolume ?? 1.0} />
            </div>

            {/* Video Generation Status */}
            {(pendingShots.size > 0 || scene.shots.some(s => s.video?.status === "failed")) && (
              <div className="space-y-2">
                {/* Processing indicator */}
                {pendingShots.size > 0 && (
                  <div className="flex items-center gap-3 px-4 py-3 bg-primary/10 border border-primary/20 rounded-lg">
                    <Loader2 className="h-5 w-5 text-primary animate-spin" />
                    <div className="flex-1">
                      <p className="text-sm font-medium text-primary">
                        Generating {pendingShots.size} video{pendingShots.size > 1 ? "s" : ""}...
                      </p>
                      <p className="text-xs text-muted-foreground">
                        This may take 1-2 minutes. You can continue editing while videos generate.
                      </p>
                    </div>
                  </div>
                )}

                {/* Failed shots */}
                {scene.shots.filter(s => s.video?.status === "failed").map((shot) => {
                  const errorMessage = shot.video?.error || "Unknown error occurred";
                  const isAudioError = errorMessage.toLowerCase().includes("audio");
                  
                  return (
                    <div 
                      key={shot.id}
                      className="flex items-start gap-3 px-4 py-3 bg-destructive/10 border border-destructive/20 rounded-lg"
                    >
                      <X className="h-5 w-5 text-destructive mt-0.5 shrink-0" />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-destructive">
                          Video generation failed
                        </p>
                        <p className="text-xs text-muted-foreground mt-1">
                          {errorMessage}
                        </p>
                        {isAudioError && (
                          <p className="text-xs text-muted-foreground mt-2 italic">
                            💡 Tip: Audio errors often occur when the prompt doesn&apos;t provide enough content for the video duration. Try adding more action or dialogue.
                          </p>
                        )}
                      </div>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => {
                          scenePlayerRef.current?.pause();
                          setSelectedShot(shot);
                          setShowShotEditor(true);
                        }}
                        className="shrink-0 text-xs"
                      >
                        Edit & Retry
                      </Button>
                    </div>
                  );
                })}
              </div>
            )}

            {/* Timeline Component */}
            <div className="w-full overflow-x-auto">
              <Timeline
                shots={scene.shots}
                audioTracks={scene.audioTracks}
                selectedShotId={selectedShot?.id}
                selectedAudioTrackId={selectedAudioTrack?.id}
                onShotClick={handleShotClick}
                onShotReorder={handleShotReorder}
                onAudioTrackClick={handleAudioTrackClick}
                onAudioTrackMove={handleAudioTrackMove}
              />
            </div>

            {/* Master Volume Control */}
            <div className="w-full border-t border-border pt-4 px-2">
              <div className="flex items-center gap-4">
                <div className="flex items-center gap-2 min-w-[120px]">
                  <Volume2 className="h-4 w-4 text-muted-foreground" />
                  <Label className="text-sm font-medium">Master Volume</Label>
                </div>
                <div className="flex-1 flex items-center gap-3">
                  <Slider
                    value={[scene.masterVolume ?? 1.0]}
                    onValueChange={handleMasterVolumeChange}
                    min={0}
                    max={2}
                    step={0.01}
                    className="flex-1"
                  />
                  <div className="min-w-[60px] text-right">
                    <span className="text-sm font-mono text-muted-foreground">
                      {Math.round((scene.masterVolume ?? 1.0) * 100)}%
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* Controls Row: Add Shot, Add Audio, Render Scene */}
            <div className="flex items-center justify-between gap-4 w-full border-t border-border pt-4">
              {!(isRendering || scene.compositeStatus === "processing") && (
                <div className="flex items-center gap-4">
                  <Button
                    type="button"
                    onClick={handleAddShot}
                    size="sm"
                    className="bg-primary text-primary-foreground hover:bg-primary/90"
                  >
                    <Plus className="h-4 w-4 mr-2" />
                    Video
                  </Button>
                  <Button
                    type="button"
                    onClick={handleAddAudioTrack}
                    variant="outline"
                    size="sm"
                  >
                    <Plus className="h-4 w-4 mr-2" />
                    Audio
                  </Button>
                </div>
              )}

              <div className="flex items-center gap-4">
                {!(isRendering || scene.compositeStatus === "processing") && (
                  <Button
                    onClick={handleRenderScene}
                    disabled={scene.shots.filter(s => s.video?.status === "completed").length === 0}
                    variant="outline"
                    size="sm"
                  >
                    <Film className="h-4 w-4 mr-2" />
                    Render
                  </Button>
                )}
                {scene.compositeStatus === "completed" && scene.compositeVideo?.url && (
                  <>
                    <span className="text-xs text-muted-foreground">
                      Last render: {new Date(scene.compositeVideo.renderedAt).toLocaleString()}
                    </span>
                    <Button
                      onClick={() => setShowCompositeVideoDialog(true)}
                      variant="outline"
                      size="sm"
                    >
                      <PlayCircle className="h-4 w-4 mr-2" />
                      View Composite
                    </Button>
                    {scene.compositeVideo?.url && (
                      <>
                        <Button
                          onClick={() => {
                            if (scene.compositeVideo?.url) {
                              handleDownloadVideo(scene.compositeVideo.url);
                            }
                          }}
                          variant="outline"
                          size="sm"
                          className="flex items-center gap-1 text-xs border border-primary/30"
                        >
                          <Download className="h-4 w-4" />
                          Download
                        </Button>
                        <Button
                          onClick={() => setShowExportDialog(true)}
                          variant="outline"
                          size="sm"
                          className="flex items-center gap-1 text-xs border border-primary/30"
                        >
                          <FileDown className="h-4 w-4" />
                          Export
                        </Button>
                      </>
                    )}
                  </>
                )}
                {scene.compositeStatus === "failed" && scene.compositeError && (
                  <span className="text-xs text-destructive">
                    Render failed: {scene.compositeError}
                  </span>
                )}
              </div>
            </div>

            {/* Render Progress */}
            {scene.compositeStatus === "processing" && (
              <div className="rounded-lg border border-primary/30 overflow-hidden bg-primary/5">
                <div className="p-3">
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center gap-2">
                      <Loader2 className="h-4 w-4 text-primary animate-spin" />
                      <span className="text-sm font-medium text-primary">
                        {renderStage || "Processing..."}
                      </span>
                    </div>
                    {renderProgress !== null && (
                      <span className="text-xs text-muted-foreground">
                        {renderProgress}%
                      </span>
                    )}
                  </div>
                  <div className="h-2 bg-muted rounded-full overflow-hidden">
                    <div
                      className="h-full bg-primary transition-all duration-300 ease-out"
                      style={{ width: `${renderProgress || 0}%` }}
                    />
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>

        {removedShots.length > 0 && (
          <div className="mt-20">
            <Card>
              <CardHeader className="py-4">
                <div className="flex items-center justify-between">
                  <div>
                    <CardTitle className="text-base flex items-center gap-2">
                      <Video className="h-5 w-5 text-primary" />
                      Media Library
                    </CardTitle>
                    <p className="text-sm text-muted-foreground mt-1">
                      {removedShots.length} shot{removedShots.length !== 1 ? "s" : ""} with generated videos that have been removed from the timeline
                    </p>
                  </div>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => setShowMediaLibrary(true)}
                  >
                    <Video className="h-4 w-4 mr-2" />
                    View All
                  </Button>
                </div>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                  {removedShots.slice(0, 8).map((shot) => (
                    <div
                      key={shot.id}
                      className="group relative aspect-video rounded-lg overflow-hidden border border-border bg-muted/30 cursor-pointer hover:border-primary/50 transition-colors"
                      onClick={() => setShowMediaLibrary(true)}
                    >
                      {shot.video?.thumbnailUrl ? (
                        <Image
                          src={shot.video.thumbnailUrl}
                          alt={shot.prompt}
                          fill
                          className="object-cover"
                        />
                      ) : shot.video?.url ? (
                        <video
                          src={shot.video.url}
                          className="w-full h-full object-cover"
                          muted
                          playsInline
                        />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center">
                          <Video className="h-8 w-8 text-muted-foreground opacity-50" />
                        </div>
                      )}
                      <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100">
                        <p className="text-white text-xs font-medium px-2 text-center line-clamp-2">
                          {shot.prompt}
                        </p>
                      </div>
                    </div>
                  ))}
                </div>
                {removedShots.length > 8 && (
                  <div className="mt-4 text-center">
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      onClick={() => setShowMediaLibrary(true)}
                    >
                      View {removedShots.length - 8} more shot{removedShots.length - 8 !== 1 ? "s" : ""}
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        )}

        {/* Delete Scene Button */}
        <div className="flex justify-end mt-8 pt-6 border-t border-border">
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => setShowDeleteDialog(true)}
            className="text-xs text-destructive hover:text-destructive"
          >
            <Trash2 className="h-2 w-2 mr-1" />
            Delete Scene
          </Button>
        </div>
      </div>


      {/* Shot Editor Dialog */}
      <ShotEditorDialog
        shot={selectedShot}
        open={showShotEditor}
        onOpenChange={setShowShotEditor}
        onSave={handleShotSave}
        onDelete={
          selectedShot && scene.shots.some((s) => s.id === selectedShot.id)
            ? handleShotDelete
            : undefined
        }
        onGenerateVideo={isVideoGenerationEnabled() ? handleGenerateVideo : undefined}
        onSaveVideoToMediaLibrary={handleSaveVideoToMediaLibrary}
        onDetachAudio={handleDetachAudio}
        projectId={projectId}
        sceneId={scene.id}
        characters={characters}
        locations={locations}
        username={username}
        sceneCharacters={scene.characters}
        sceneLocationId={scene.locationId}
      />

      {/* Media Library Dialog */}
      <Dialog 
        open={showMediaLibrary} 
        onOpenChange={(open) => {
          if (!open && playingVideoId) {
            // Pause any playing video when dialog closes
            const videoElement = document.querySelector(`video[data-shot-id="${playingVideoId}"]`) as HTMLVideoElement;
            videoElement?.pause();
            setPlayingVideoId(null);
          }
          setShowMediaLibrary(open);
        }}
      >
        <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Video className="h-5 w-5 text-primary" />
              Media Library
            </DialogTitle>
            <DialogDescription>
              Shots with generated videos that have been removed from the timeline. You can add them back to the scene as new shots or permanently remove them.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-4">
            {removedShots.length === 0 ? (
              <div className="text-center py-12 text-muted-foreground">
                <Video className="h-12 w-12 mx-auto mb-4 opacity-50" />
                <p className="text-sm">No removed shots in the media library</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {removedShots.map((shot) => {
                  const isPlaying = playingVideoId === shot.id;
                  
                  const handleVideoClick = () => {
                    if (!shot.video?.url) return;
                    
                    const videoElement = document.querySelector(`video[data-shot-id="${shot.id}"]`) as HTMLVideoElement;
                    
                    if (isPlaying && videoElement) {
                      // Pause this video
                      videoElement.pause();
                      setPlayingVideoId(null);
                    } else {
                      // Pause any other playing video
                      if (playingVideoId) {
                        const otherVideo = document.querySelector(`video[data-shot-id="${playingVideoId}"]`) as HTMLVideoElement;
                        otherVideo?.pause();
                      }
                      // Play this video
                      setPlayingVideoId(shot.id);
                      setTimeout(() => {
                        videoElement?.play();
                      }, 0);
                    }
                  };

                  const handleVideoEnded = () => {
                    setPlayingVideoId(null);
                  };

                  return (
                  <Card key={shot.id} className="overflow-hidden">
                      <div 
                        className="relative aspect-video bg-muted/30 cursor-pointer group"
                        onClick={handleVideoClick}
                      >
                        {shot.video?.thumbnailUrl && !isPlaying ? (
                          <>
                        <Image
                          src={shot.video.thumbnailUrl}
                          alt={shot.prompt}
                          fill
                          className="object-cover"
                        />
                            <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100">
                              <PlayCircle className="h-16 w-16 text-white/90" />
                            </div>
                          </>
                      ) : shot.video?.url ? (
                          <>
                        <video
                              data-shot-id={shot.id}
                          src={shot.video.url}
                          className="w-full h-full object-cover"
                          muted
                          playsInline
                              onEnded={handleVideoEnded}
                              onClick={(e) => {
                                e.stopPropagation();
                                handleVideoClick();
                              }}
                            />
                            {!isPlaying && (
                              <div className="absolute inset-0 bg-black/0 group-hover:bg-black/40 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100 pointer-events-none">
                                <PlayCircle className="h-16 w-16 text-white/90" />
                              </div>
                            )}
                          </>
                      ) : (
                        <div className="w-full h-full flex items-center justify-center">
                          <Video className="h-12 w-12 text-muted-foreground opacity-50" />
                        </div>
                      )}
                    </div>
                    <CardContent className="p-4 space-y-3">
                      <div className="space-y-1">
                        <p className="text-sm font-medium line-clamp-2">{shot.prompt}</p>
                        {shot.video?.durationMs && (
                          <p className="text-xs text-muted-foreground">
                            Duration: {(shot.video.durationMs / 1000).toFixed(1)}s
                          </p>
                        )}
                      </div>
                      <div className="flex gap-2">
                        <Button
                          type="button"
                          variant="default"
                          size="sm"
                          onClick={() => handleAddShotFromLibrary(shot)}
                          className="flex-1"
                        >
                          <Plus className="h-4 w-4 mr-1" />
                          Add to Scene
                        </Button>
                        <Button
                          type="button"
                          variant="destructive"
                          size="sm"
                          onClick={() => handleRemoveFromLibraryClick(shot.id)}
                          className="flex-1"
                        >
                          <Trash2 className="h-4 w-4 mr-1" />
                          Delete
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                  );
                })}
              </div>
            )}
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setShowMediaLibrary(false)}>
              Close
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete Video Confirmation Dialog */}
      <Dialog open={!!shotToDelete} onOpenChange={(open) => !open && setShotToDelete(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete Video</DialogTitle>
            <DialogDescription>
              Are you sure you want to permanently delete this video? This action cannot be undone. The video file will be removed from storage.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => setShotToDelete(null)}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="destructive"
              onClick={handleRemoveFromLibrary}
            >
              <Trash2 className="h-4 w-4 mr-2" />
              Delete Permanently
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Audio Track Modal */}
      <AudioTrackModal
        track={selectedAudioTrack}
        open={showAudioTrackEditor}
        onOpenChange={setShowAudioTrackEditor}
        onSave={handleAudioTrackSave}
        onDelete={
          selectedAudioTrack ? () => handleAudioTrackDelete(selectedAudioTrack.id) : undefined
        }
        onCreateOverlap={handleCreateOverlap}
        shots={scene.shots}
        projectId={projectId}
        sceneId={scene.id}
      />

      {/* Generate Video Dialog - Only shown in development/localhost */}
      {isVideoGenerationEnabled() && (
      <Dialog open={showGenerateVideoDialog} onOpenChange={setShowGenerateVideoDialog}>
        <DialogContent className="max-w-[95vw] xl:max-w-7xl max-h-[90vh] overflow-hidden flex flex-col">
          <DialogHeader className="shrink-0 pb-4 border-b">
            <div className="flex items-center justify-between">
              <DialogTitle className="text-xl font-semibold flex items-center gap-2">
                <Film className="h-5 w-5 text-primary" />
                Generate Video
              </DialogTitle>
              {/* Mode Selection - Inline with title on larger screens */}
              <div className="flex gap-1 p-0.5 bg-muted rounded-lg">
                <button
                  type="button"
                  onClick={() => setGenerateMode("start-end-frames")}
                  className={cn(
                    "px-4 py-2 text-sm font-medium rounded-md transition-all flex items-center gap-2",
                    generateMode === "start-end-frames"
                      ? "bg-background text-foreground shadow-sm"
                      : "text-muted-foreground hover:text-foreground"
                  )}
                >
                  <ImageIcon className="h-4 w-4" />
                  Start/End Frames
                </button>
                <button
                  type="button"
                  onClick={() => setGenerateMode("ingredients")}
                  className={cn(
                    "px-4 py-2 text-sm font-medium rounded-md transition-all flex items-center gap-2",
                    generateMode === "ingredients"
                      ? "bg-background text-foreground shadow-sm"
                      : "text-muted-foreground hover:text-foreground"
                  )}
                >
                  <Sparkles className="h-4 w-4" />
                  Ingredients
                </button>
              </div>
            </div>
          </DialogHeader>

          <div className="flex-1 overflow-y-auto py-6">
            {/* Start/End Frames Mode - Side by side on XL */}
            {generateMode === "start-end-frames" && (
              <div className="grid grid-cols-1 xl:grid-cols-2 gap-6 xl:gap-8">
                {/* Start Frame */}
                <div className="space-y-3">
                  <div className="flex items-center gap-2">
                    <span className="flex items-center justify-center w-6 h-6 rounded-full bg-primary text-primary-foreground text-xs font-bold">
                      1
                    </span>
                    <Label className="text-base font-medium">Start Frame</Label>
                  </div>
                  {startFrameImage ? (
                    <div className="relative aspect-video rounded-xl overflow-hidden border-2 border-border group shadow-sm">
                      <Image
                        src={startFrameImage}
                        alt="Start frame"
                        fill
                        className="object-cover"
                      />
                      <button
                        type="button"
                        onClick={() => setStartFrameImage(undefined)}
                        className="absolute top-3 right-3 p-1.5 rounded-full bg-destructive text-destructive-foreground opacity-0 group-hover:opacity-100 transition-opacity z-10 shadow-lg"
                      >
                        <X className="h-4 w-4" />
                      </button>
                      <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/60 to-transparent p-3">
                        <span className="text-white text-sm font-medium">Start Frame</span>
                      </div>
                    </div>
                  ) : (
                    <ImageInputZone
                      onImageUrl={(url) => setStartFrameImage(url)}
                      onUploadFile={(file) => handleImageUpload(file, "start")}
                      projectId={projectId}
                      sceneId={scene.id}
                      disabled={isUploadingImage}
                      placeholder="Describe the start frame..."
                      libraryImages={libraryImages}
                    />
                  )}
                </div>

                {/* End Frame */}
                <div className="space-y-3">
                  <div className="flex items-center gap-2">
                    <span className="flex items-center justify-center w-6 h-6 rounded-full bg-primary text-primary-foreground text-xs font-bold">
                      2
                    </span>
                    <Label className="text-base font-medium">End Frame</Label>
                  </div>
                  {endFrameImage ? (
                    <div className="relative aspect-video rounded-xl overflow-hidden border-2 border-border group shadow-sm">
                      <Image src={endFrameImage} alt="End frame" fill className="object-cover" />
                      <button
                        type="button"
                        onClick={() => setEndFrameImage(undefined)}
                        className="absolute top-3 right-3 p-1.5 rounded-full bg-destructive text-destructive-foreground opacity-0 group-hover:opacity-100 transition-opacity z-10 shadow-lg"
                      >
                        <X className="h-4 w-4" />
                      </button>
                      <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/60 to-transparent p-3">
                        <span className="text-white text-sm font-medium">End Frame</span>
                      </div>
                    </div>
                  ) : (
                    <ImageInputZone
                      onImageUrl={(url) => setEndFrameImage(url)}
                      onUploadFile={(file) => handleImageUpload(file, "end")}
                      projectId={projectId}
                      sceneId={scene.id}
                      disabled={isUploadingImage}
                      placeholder="Describe the end frame..."
                      libraryImages={libraryImages}
                    />
                  )}
                </div>
              </div>
            )}

            {/* Ingredients Mode - Grid layout on XL */}
            {generateMode === "ingredients" && (
              <div className="space-y-4">
                <div className="flex items-center gap-2">
                  <Label className="text-base font-medium">Reference Images (up to 3)</Label>
                  <span className="text-xs text-muted-foreground bg-muted px-2 py-0.5 rounded">
                    {referenceImages.length}/3 selected
                  </span>
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
                  {referenceImages.map((img, index) => (
                    <div
                      key={index}
                      className="relative aspect-video rounded-xl overflow-hidden border-2 border-border group shadow-sm"
                    >
                      <Image
                        src={img}
                        alt={`Reference ${index + 1}`}
                        fill
                        className="object-cover"
                      />
                      <button
                        type="button"
                        onClick={() =>
                          setReferenceImages(referenceImages.filter((_, i) => i !== index))
                        }
                        className="absolute top-3 right-3 p-1.5 rounded-full bg-destructive text-destructive-foreground opacity-0 group-hover:opacity-100 transition-opacity z-10 shadow-lg"
                      >
                        <X className="h-4 w-4" />
                      </button>
                      <div className="absolute top-3 left-3">
                        <span className="flex items-center justify-center w-6 h-6 rounded-full bg-primary text-primary-foreground text-xs font-bold shadow-lg">
                          {index + 1}
                        </span>
                      </div>
                    </div>
                  ))}
                  {referenceImages.length < 3 && (
                    <ImageInputZone
                      onImageUrl={(url) => {
                        if (referenceImages.length < 3) {
                          setReferenceImages([...referenceImages, url]);
                        }
                      }}
                      onUploadFile={(file) => handleImageUpload(file, "reference")}
                      projectId={projectId}
                      sceneId={scene.id}
                      disabled={isUploadingImage}
                      placeholder="Describe a reference image..."
                      libraryImages={libraryImages}
                    />
                  )}
                </div>
              </div>
            )}
          </div>

          {/* Fixed Footer with Prompt */}
          <div className="shrink-0 border-t pt-4 space-y-4 bg-background">
            <div className="space-y-2">
              <Label htmlFor="generate-prompt" className="text-base font-medium">
                Prompt
              </Label>
              <div className="flex gap-3">
                <Textarea
                  id="generate-prompt"
                  value={generatePrompt}
                  onChange={(e) => setGeneratePrompt(e.target.value)}
                  placeholder={
                    generateMode === "start-end-frames"
                      ? "Describe the motion or transition between the start and end frames..."
                      : "Describe the video you want to generate using the reference images..."
                  }
                  rows={2}
                  className="bg-background resize-none flex-1"
                />
                <div className="flex flex-col gap-2 shrink-0">
                  <Button
                    type="button"
                    size="lg"
                    onClick={handleGenerateVideoSubmit}
                    disabled={isGeneratingVideo || !generatePrompt.trim()}
                    className="h-full min-w-[140px]"
                  >
                    {isGeneratingVideo ? (
                      <>
                        <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                        Generating...
                      </>
                    ) : (
                      <>
                        <Sparkles className="h-4 w-4 mr-2" />
                        Generate
                      </>
                    )}
                  </Button>
                </div>
              </div>
              <p className="text-xs text-muted-foreground">
                {generateMode === "start-end-frames"
                  ? "Veo 3.1 will animate between your start and end frames based on this prompt."
                  : "Veo 3.1 will use your reference images to maintain style and character consistency."}
              </p>
            </div>
          </div>
        </DialogContent>
      </Dialog>
      )}

      {/* Screenplay Edit Dialog */}
      <Dialog
        open={isEditingScreenplay}
        onOpenChange={(open) => {
          if (!open) {
            handleScreenplayCancel();
          }
        }}
      >
        <DialogContent className="max-w-[calc(100%-2rem)] sm:max-w-[960px] w-full max-h-[90vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>Edit Screenplay</DialogTitle>
            <DialogDescription>
              Use structured screenplay format with scene headings, action, dialogue, and more.
            </DialogDescription>
          </DialogHeader>
          <div className="flex-1 overflow-hidden flex flex-col min-h-0">
            <div className="rounded-md border border-input bg-background overflow-hidden flex-1 flex flex-col min-h-0">
              <div className="py-2 font-mono text-sm leading-relaxed overflow-y-auto flex-1">
                {screenplayElements.map((element, index) => {
                  const prevElement = index > 0 ? screenplayElements[index - 1] : null;
                  const needsExtraSpacing =
                    element.type === "action" && prevElement?.type === "dialogue";

                  return (
                    <ScreenplayElementComponent
                      key={element.id}
                      element={element}
                      index={index}
                      isFocused={focusedElementIndex === index}
                      onFocus={setFocusedElementIndex}
                      onChange={handleElementChange}
                      onTypeChange={handleElementTypeChange}
                      onKeyDown={handleElementKeyDown}
                      onDelete={handleElementDelete}
                      onInsertAfter={handleElementInsertAfter}
                      extraTopSpacing={needsExtraSpacing}
                      ref={(ref) => registerElementRef(element.id, ref)}
                    />
                  );
                })}
              </div>

              <div className="border-t border-border p-2 flex flex-wrap gap-1.5 bg-muted/30 shrink-0">
                <span className="text-xs text-muted-foreground self-center mr-1">Add:</span>
                {(
                  [
                    "scene_heading",
                    "action",
                    "character",
                    "dialogue",
                    "parenthetical",
                    "transition",
                  ] as ScreenplayElementType[]
                ).map((type) => (
                  <Button
                    key={type}
                    variant="ghost"
                    size="sm"
                    onClick={() => handleAddElement(type)}
                    className="h-6 px-2 text-xs"
                  >
                    <Plus className="h-3 w-3 mr-1" />
                    {ELEMENT_TYPE_LABELS[type]}
                  </Button>
                ))}
              </div>
            </div>
            <p className="text-xs text-muted-foreground mt-2 shrink-0">
              Enter for new line • Tab to change type • Click type label to change
            </p>
          </div>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={handleScreenplayCancel}
              className="bg-transparent"
            >
              Cancel
            </Button>
            <Button type="button" onClick={handleScreenplaySave}>
              Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Hidden video upload input */}
      <input
        ref={videoUploadInputRef}
        type="file"
        accept="video/mp4,video/webm,video/quicktime,video/x-msvideo"
        onChange={handleVideoFileSelect}
        className="hidden"
      />

      {/* Delete Confirmation Dialog */}
      <Dialog open={showDeleteDialog} onOpenChange={setShowDeleteDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete Scene?</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete &quot;{scene.title}&quot;? This action cannot be
              undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => setShowDeleteDialog(false)}
              disabled={isDeleting}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="destructive"
              onClick={handleDelete}
              disabled={isDeleting}
            >
              {isDeleting ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Deleting...
                </>
              ) : (
                "Delete Scene"
              )}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Composite Video Dialog */}
      <Dialog open={showCompositeVideoDialog} onOpenChange={setShowCompositeVideoDialog}>
        <DialogContent className="sm:max-w-6xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Film className="h-5 w-5" />
              Rendered Composite Video
            </DialogTitle>
            <DialogDescription>
              {scene.compositeVideo?.renderedAt && (
                <>Rendered on {new Date(scene.compositeVideo.renderedAt).toLocaleString()}</>
              )}
            </DialogDescription>
          </DialogHeader>
          {scene.compositeVideo?.url && (
            <div className="space-y-4">
              <div className="aspect-video bg-black rounded-lg overflow-hidden">
                <video
                  src={scene.compositeVideo.url}
                  controls
                  className="w-full h-full"
                  poster={scene.compositeVideo.thumbnailUrl}
                >
                  Your browser does not support the video tag.
                </video>
              </div>
              <div className="flex items-center justify-between">
                {scene.compositeVideo.durationMs && (
                  <span className="text-sm text-muted-foreground">
                    Duration: {Math.round(scene.compositeVideo.durationMs / 1000)}s
                  </span>
                )}
                {scene.compositeVideo?.url && (
                  <Button
                    onClick={() => {
                      if (scene.compositeVideo?.url) {
                        handleDownloadVideo(scene.compositeVideo.url);
                      }
                    }}
                    variant="outline"
                    size="sm"
                  >
                    Download Video
                  </Button>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Export Source Videos Dialog */}
      <Dialog open={showExportDialog} onOpenChange={setShowExportDialog}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <FileDown className="h-5 w-5" />
              Export Source Videos
            </DialogTitle>
            <DialogDescription>
              Export all original source video files from this scene as a zip archive.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            {isExporting ? (
              <div className="space-y-3">
                <div className="flex items-center gap-3">
                  <Loader2 className="h-5 w-5 text-primary animate-spin" />
                  <div className="flex-1">
                    <p className="text-sm font-medium">
                      {exportProgress
                        ? `Exporting ${exportProgress.current} of ${exportProgress.total} videos...`
                        : "Preparing export..."}
                    </p>
                    {exportProgress && (
                      <div className="mt-2 w-full bg-muted rounded-full h-2 overflow-hidden">
                        <div
                          className="bg-primary h-full transition-all duration-300"
                          style={{
                            width: `${(exportProgress.current / exportProgress.total) * 100}%`,
                          }}
                        />
                      </div>
                    )}
                  </div>
                </div>
                <p className="text-xs text-muted-foreground">
                  This may take a few moments depending on the number of videos.
                </p>
              </div>
            ) : (
              <div className="space-y-2">
                <p className="text-sm text-muted-foreground">
                  This will download all original source video files from the shots in this scene
                  and package them into a zip file.
                </p>
                <p className="text-xs text-muted-foreground">
                  Total videos to export: {scene.shots.filter((s) => s.video?.status === "completed").length}
                </p>
              </div>
            )}
          </div>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => setShowExportDialog(false)}
              disabled={isExporting}
            >
              Cancel
            </Button>
            <Button
              type="button"
              onClick={handleExportSourceVideos}
              disabled={isExporting || scene.shots.filter((s) => s.video?.status === "completed").length === 0}
            >
              {isExporting ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Exporting...
                </>
              ) : (
                <>
                  <FileDown className="h-4 w-4 mr-2" />
                  Export Videos
                </>
              )}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
