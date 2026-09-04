"use client";

import {
  Film,
  Image as ImageIcon,
  Loader2,
  MapPin,
  Music,
  Pause,
  Play,
  Scissors,
  Sparkles,
  Upload,
  User,
  Video,
  VolumeX,
  X,
} from "lucide-react";
import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { AudioWaveform } from "@/components/audio-waveform";
import type { Character, Location } from "@/components/project-form";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { getImageUrl } from "@/lib/image-utils";
import type {
  AudioTrack,
  GenerationMode,
  ReferenceImage,
  ReferenceImageType,
  Shot,
} from "@/lib/scenes-client";
import { createNewAudioTrack } from "@/lib/scenes-client";
import { uploadFile } from "@/lib/upload-utils";
import { isVideoGenerationEnabled } from "@/lib/utils/video-generation";
import { generateThumbnailFromFile } from "@/lib/video-thumbnail";

// ============================================================================
// TYPES
// ============================================================================

interface ShotEditorDialogProps {
  shot: Shot | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (shot: Shot) => void;
  onDelete?: (shotId: string) => void;
  onGenerateVideo?: (shot: Shot) => void;
  onSaveVideoToMediaLibrary?: (shot: Shot) => void; // Save old video to media library when replacing
  onDetachAudio?: (audioTrack: AudioTrack) => void; // Detach audio from shot as independent track
  projectId: string;
  sceneId: string;
  characters?: Character[];
  locations?: Location[];
  username?: string;
  // Scene-specific data for filtering
  sceneCharacters?: string[]; // Character names in this scene
  sceneLocationId?: string; // Location name for this scene
}

// ============================================================================
// GENERATION MODE CONFIG
// ============================================================================

const GENERATION_MODES: { value: GenerationMode; label: string; description: string }[] = [
  {
    value: "text-only",
    label: "Text Prompt",
    description: "Generate video from a text description only",
  },
  {
    value: "start-frame",
    label: "Start Frame",
    description: "Animate from a starting image with a motion prompt",
  },
  {
    value: "start-end-frame",
    label: "Start + End Frames",
    description: "Generate video transitioning between two images",
  },
  {
    value: "reference-images",
    label: "Reference Images",
    description: "Use up to 3 images to guide style and content",
  },
];

interface ImageDropZoneProps {
  label: string;
  imageUrl?: string;
  onImageSelect: (file: File) => void;
  onImageRemove: () => void;
  disabled?: boolean;
}

function ImageDropZone({
  label,
  imageUrl,
  onImageSelect,
  onImageRemove,
  disabled,
}: ImageDropZoneProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [isDragOver, setIsDragOver] = useState(false);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  }, []);

  const handleDragLeave = useCallback(() => {
    setIsDragOver(false);
  }, []);

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragOver(false);
      const file = e.dataTransfer.files[0];
      if (file?.type.startsWith("image/")) {
        onImageSelect(file);
      }
    },
    [onImageSelect]
  );

  const handleFileChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) {
        onImageSelect(file);
      }
    },
    [onImageSelect]
  );

  return (
    <div className="space-y-2">
      <Label className="text-sm">{label}</Label>
      {imageUrl ? (
        <div className="relative aspect-video rounded-lg overflow-hidden border border-border group">
          <Image src={imageUrl} alt={label} fill className="object-cover" />
          <button
            type="button"
            onClick={onImageRemove}
            className="absolute top-2 right-2 p-1 rounded-full bg-destructive text-destructive-foreground opacity-0 group-hover:opacity-100 transition-opacity z-10"
            disabled={disabled}
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      ) : (
        <div
          onClick={() => !disabled && inputRef.current?.click()}
          onDragOver={handleDragOver}
          onDragLeave={handleDragLeave}
          onDrop={handleDrop}
          className={`
            text-center aspect-video px-2 rounded-lg border-2 border-dashed flex flex-col items-center justify-center gap-1 cursor-pointer transition-colors
            ${isDragOver ? "border-primary bg-primary/5" : "border-muted-foreground/30 hover:border-primary/50"}
            ${disabled ? "opacity-50 cursor-not-allowed" : ""}
          `}
        >
          <ImageIcon className="h-6 w-6 text-muted-foreground" />
          <span className="text-xs text-muted-foreground px-4">Drop image or click to upload</span>
        </div>
      )}
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        onChange={handleFileChange}
        className="hidden"
        disabled={disabled}
      />
    </div>
  );
}

export function ShotEditorDialog({
  shot,
  open,
  onOpenChange,
  onSave,
  onDelete,
  onGenerateVideo,
  onSaveVideoToMediaLibrary,
  onDetachAudio,
  projectId,
  sceneId,
  characters = [],
  locations = [],
  username = "",
  sceneCharacters = [],
  sceneLocationId,
}: ShotEditorDialogProps) {
  // Local state for editing
  const [prompt, setPrompt] = useState(shot?.prompt || "");
  const [sourceType, setSourceType] = useState<"uploaded" | "generated">(
    shot?.sourceType || (isVideoGenerationEnabled() && onGenerateVideo ? "generated" : "uploaded")
  );
  const [generationMode, setGenerationMode] = useState<GenerationMode>(
    shot?.generationMode || "text-only"
  );
  const [startFrameImage, setStartFrameImage] = useState<string | undefined>(shot?.startFrameImage);
  const [endFrameImage, setEndFrameImage] = useState<string | undefined>(shot?.endFrameImage);
  const [typedReferenceImages, setTypedReferenceImages] = useState<ReferenceImage[]>(
    shot?.typedReferenceImages || []
  );
  const [isUploading, setIsUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState<number>(0);
  const [isGenerating, setIsGenerating] = useState(false);
  const [isVideoDragOver, setIsVideoDragOver] = useState(false);
  const [durationSeconds, setDurationSeconds] = useState<4 | 6 | 8>(shot?.durationSeconds || 8);

  // Start frame generation state
  const [startFrameInputMode, setStartFrameInputMode] = useState<"upload" | "generate">("upload");
  const [startFramePrompt, setStartFramePrompt] = useState("");
  const [startFrameReferenceImages, setStartFrameReferenceImages] = useState<ReferenceImage[]>([]);
  const [isGeneratingStartFrame, setIsGeneratingStartFrame] = useState(false);

  // End frame generation state
  const [endFrameInputMode, setEndFrameInputMode] = useState<"upload" | "generate">("upload");
  const [endFramePrompt, setEndFramePrompt] = useState("");
  const [endFrameReferenceImages, setEndFrameReferenceImages] = useState<ReferenceImage[]>([]);
  const [isGeneratingEndFrame, setIsGeneratingEndFrame] = useState(false);

  // Replace mode state
  const [isReplaceMode, setIsReplaceMode] = useState(false);

  // Video trimming state
  const [isTrimMode, setIsTrimMode] = useState(false);
  const [trimStartMs, setTrimStartMs] = useState<number>(shot?.trimStartMs || 0);
  const [trimEndMs, setTrimEndMs] = useState<number>(shot?.trimEndMs || 0);
  const [isTrimmerPlaying, setIsTrimmerPlaying] = useState(false);
  const [_trimmerCurrentTime, setTrimmerCurrentTime] = useState(0);
  const [isTrimmingVideo, setIsTrimmingVideo] = useState(false);
  const trimmerVideoRef = useRef<HTMLVideoElement>(null);

  // Audio detaching state
  const [isDetachingAudio, setIsDetachingAudio] = useState(false);

  // Effects mode state
  const [isEffectsMode, setIsEffectsMode] = useState(false);
  const [fadeInType, setFadeInType] = useState<"none" | "black" | "white">(
    shot?.fadeInType || "none"
  );
  const [fadeOutType, setFadeOutType] = useState<"none" | "black" | "white">(
    shot?.fadeOutType || "none"
  );
  const [fadeDurationMs, setFadeDurationMs] = useState<number>(shot?.fadeDurationMs || 500);
  const [effectsPreviewTime, setEffectsPreviewTime] = useState(0); // Current time for fade preview in effects mode
  const [normalPreviewTime, setNormalPreviewTime] = useState(0); // Current time for fade preview in normal view

  // Auto-open file picker state
  const [shouldOpenFilePicker, setShouldOpenFilePicker] = useState(false);

  const videoInputRef = useRef<HTMLInputElement>(null);

  // Effect to open file picker after sourceType changes to "uploaded"
  useEffect(() => {
    if (shouldOpenFilePicker && sourceType === "uploaded" && videoInputRef.current) {
      videoInputRef.current.click();
      setShouldOpenFilePicker(false);
    }
  }, [shouldOpenFilePicker, sourceType]);

  // Reset state when modal opens or shot changes
  useEffect(() => {
    if (open && shot) {
      setPrompt(shot.prompt || "");
      setSourceType(
        shot.sourceType ||
          (isVideoGenerationEnabled() && onGenerateVideo ? "generated" : "uploaded")
      );
      setGenerationMode(shot.generationMode || "text-only");
      setStartFrameImage(shot.startFrameImage);
      setEndFrameImage(shot.endFrameImage);
      setTypedReferenceImages(shot.typedReferenceImages || []);
      setDurationSeconds(shot.durationSeconds || 8); // Use shot's duration or default to 8 seconds
      // Reset generating state when modal opens to prevent stuck state
      setIsGenerating(false);
      setIsUploading(false);
      setUploadProgress(0);
      // Reset frame generation state
      setStartFrameInputMode("upload");
      setStartFramePrompt("");
      setStartFrameReferenceImages([]);
      setIsGeneratingStartFrame(false);
      setEndFrameInputMode("upload");
      setEndFramePrompt("");
      setEndFrameReferenceImages([]);
      setIsGeneratingEndFrame(false);
      // Reset replace mode when modal opens
      setIsReplaceMode(false);
      // Reset file picker trigger
      setShouldOpenFilePicker(false);
      // Reset trim state
      setIsTrimMode(false);
      setTrimStartMs(shot.trimStartMs || 0);
      setTrimEndMs(shot.trimEndMs || 0);
      setIsTrimmerPlaying(false);
      setTrimmerCurrentTime(0);
      // Reset effects mode state
      setIsEffectsMode(false);
      setFadeInType(shot.fadeInType || "none");
      setFadeOutType(shot.fadeOutType || "none");
      setFadeDurationMs(shot.fadeDurationMs || 500);
      setEffectsPreviewTime(0);
      setNormalPreviewTime(0);
    }
  }, [open, shot, onGenerateVideo]);

  // Handle image upload for a specific slot
  // Uses presigned URLs for large images (>5MB), otherwise uses server-side processing for optimization
  const handleImageUpload = async (
    file: File,
    slot: "start" | "end" | "reference",
    refType?: ReferenceImageType
  ) => {
    setIsUploading(true);
    setUploadProgress(0);
    try {
      const result = await uploadFile(file, {
        projectId,
        sceneId,
        mediaType: "image",
        onProgress: setUploadProgress,
      });

      if (result.success && result.url) {
        if (slot === "start") {
          setStartFrameImage(result.url);
        } else if (slot === "end") {
          setEndFrameImage(result.url);
        } else if (slot === "reference" && refType) {
          const newRef: ReferenceImage = {
            url: result.url,
            type: refType,
          };
          setTypedReferenceImages((prev) => [...prev.slice(0, 2), newRef]);
        }
        toast.success("Image uploaded");
      } else {
        toast.error(result.error || "Failed to upload image");
      }
    } catch (error) {
      console.error("[ShotEditorDialog] Upload error:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to upload image");
    } finally {
      setIsUploading(false);
      setUploadProgress(0);
    }
  };

  // Add a reference image from existing project assets
  const addReferenceImage = (url: string, type: ReferenceImageType, name?: string) => {
    if (typedReferenceImages.length >= 3) {
      toast.error("Maximum 3 reference images allowed");
      return;
    }
    // Check if this image is already added
    if (typedReferenceImages.some((ref) => ref.url === url)) {
      toast.error("This image is already added");
      return;
    }
    const newRef: ReferenceImage = { url, type, name };
    setTypedReferenceImages((prev) => [...prev, newRef]);
  };

  // Remove a typed reference image
  const removeTypedReferenceImage = (index: number) => {
    setTypedReferenceImages((prev) => prev.filter((_, i) => i !== index));
  };

  // Generate a frame image using AI
  const handleGenerateFrameImage = async (frameType: "start" | "end") => {
    const framePrompt = frameType === "start" ? startFramePrompt : endFramePrompt;
    const frameReferenceImages =
      frameType === "start" ? startFrameReferenceImages : endFrameReferenceImages;
    const setIsGeneratingFrame =
      frameType === "start" ? setIsGeneratingStartFrame : setIsGeneratingEndFrame;
    const setFrameImage = frameType === "start" ? setStartFrameImage : setEndFrameImage;

    if (!framePrompt.trim()) {
      toast.error("Please enter a prompt for the image");
      return;
    }

    setIsGeneratingFrame(true);

    try {
      const response = await fetch("/api/ai/generate-image", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt: framePrompt,
          projectId,
          sceneId,
          aspectRatio: "16:9",
          referenceImages:
            frameReferenceImages.length > 0
              ? frameReferenceImages.map((ref) => ref.url)
              : undefined,
        }),
      });

      const data = await response.json();

      if (data.success && data.image?.imageUrl) {
        setFrameImage(data.image.imageUrl);
        toast.success(`${frameType === "start" ? "Start" : "End"} frame generated!`);
      } else {
        toast.error(data.error || "Failed to generate image");
      }
    } catch (error) {
      console.error(
        "[ShotEditorDialog] Generate frame error:",
        JSON.stringify({ error, frameType }, null, 2)
      );
      toast.error("Failed to generate image");
    } finally {
      setIsGeneratingFrame(false);
    }
  };

  // Add a reference image for frame generation
  const addFrameReferenceImage = (
    frameType: "start" | "end",
    url: string,
    type: ReferenceImageType,
    name?: string
  ) => {
    const setFrameReferenceImages =
      frameType === "start" ? setStartFrameReferenceImages : setEndFrameReferenceImages;
    const currentRefs = frameType === "start" ? startFrameReferenceImages : endFrameReferenceImages;

    if (currentRefs.length >= 3) {
      toast.error("Maximum 3 reference images allowed");
      return;
    }
    if (currentRefs.some((ref) => ref.url === url)) {
      toast.error("This image is already added");
      return;
    }
    setFrameReferenceImages((prev) => [...prev, { url, type, name }]);
  };

  // Remove a reference image for frame generation
  const removeFrameReferenceImage = (frameType: "start" | "end", index: number) => {
    const setFrameReferenceImages =
      frameType === "start" ? setStartFrameReferenceImages : setEndFrameReferenceImages;
    setFrameReferenceImages((prev) => prev.filter((_, i) => i !== index));
  };

  // Handle video file upload - uses presigned URLs for large files
  const processVideoUpload = useCallback(
    async (file: File) => {
      if (!file || !shot) return;

      setIsUploading(true);
      setUploadProgress(0);

      try {
        const result = await uploadFile(file, {
          projectId,
          sceneId,
          mediaType: "video",
          onProgress: setUploadProgress,
        });

        if (result.success && shot && result.url) {
          console.log(
            "[ShotEditorDialog] Video uploaded successfully:",
            JSON.stringify(
              {
                shotId: shot.id,
                videoUrl: result.url,
                projectId,
                sceneId,
                isReplaceMode,
              },
              null,
              2
            )
          );

          // If replacing, save old video to media library (without removing the shot)
          if (
            isReplaceMode &&
            shot.video?.url &&
            shot.video?.status === "completed" &&
            onSaveVideoToMediaLibrary
          ) {
            console.log(
              "[ShotEditorDialog] Saving old video to media library before upload replacement:",
              JSON.stringify({ shotId: shot.id, oldVideoUrl: shot.video.url }, null, 2)
            );
            onSaveVideoToMediaLibrary(shot);
          }

          // Generate thumbnail client-side from the original file
          let thumbnailUrl: string | undefined;
          let durationMs = 5000; // Default duration
          try {
            console.log("[ShotEditorDialog] Generating thumbnail client-side");
            const thumbnailResult = await generateThumbnailFromFile(file);

            if (thumbnailResult.success && thumbnailResult.thumbnailBlob) {
              durationMs = thumbnailResult.durationMs || 5000;

              // Upload thumbnail to S3
              const thumbnailFile = new File(
                [thumbnailResult.thumbnailBlob],
                `thumbnail-${shot.id}.jpg`,
                { type: "image/jpeg" }
              );

              const thumbnailUploadResult = await uploadFile(thumbnailFile, {
                projectId,
                sceneId,
                mediaType: "image",
              });

              if (thumbnailUploadResult.success && thumbnailUploadResult.url) {
                thumbnailUrl = thumbnailUploadResult.url;
                console.log(
                  "[ShotEditorDialog] Thumbnail uploaded:",
                  JSON.stringify({ thumbnailUrl, durationMs }, null, 2)
                );
              }
            } else {
              console.log(
                "[ShotEditorDialog] Thumbnail generation failed:",
                JSON.stringify({ error: thumbnailResult.error }, null, 2)
              );
            }
          } catch (thumbnailError) {
            console.error(
              "[ShotEditorDialog] Error generating thumbnail:",
              JSON.stringify({ error: thumbnailError }, null, 2)
            );
            // Continue without thumbnail - video will still work
          }

          const updatedShot: Shot = {
            ...shot,
            // Clear generation-related fields when uploading a video
            prompt: "", // Clear prompt since this is uploaded, not generated
            sourceType: "uploaded",
            generationMode: undefined,
            startFrameImage: undefined,
            endFrameImage: undefined,
            typedReferenceImages: undefined,
            referenceImages: undefined,
            durationSeconds: undefined,
            video: {
              url: result.url,
              status: "completed",
              thumbnailUrl, // Include thumbnail if generated
              durationMs, // Use actual duration from video
            },
            updatedAt: new Date().toISOString(),
          };
          onSave(updatedShot);
          toast.success(isReplaceMode ? "Shot replaced" : "Video uploaded");
          setIsReplaceMode(false);
          onOpenChange(false);
        } else {
          toast.error(result.error || "Failed to upload video");
        }
      } catch (error) {
        console.error("[ShotEditorDialog] Video upload error:", JSON.stringify({ error }, null, 2));
        toast.error("Failed to upload video");
      } finally {
        setIsUploading(false);
        setUploadProgress(0);
      }
    },
    [shot, projectId, sceneId, onSave, onOpenChange, isReplaceMode, onSaveVideoToMediaLibrary]
  );

  // Handle video upload from file input
  const handleVideoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      await processVideoUpload(file);
      if (e.target) {
        e.target.value = "";
      }
    }
  };

  // Handle video drag and drop
  const handleVideoDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsVideoDragOver(true);
  }, []);

  const handleVideoDragLeave = useCallback(() => {
    setIsVideoDragOver(false);
  }, []);

  const handleVideoDrop = useCallback(
    async (e: React.DragEvent) => {
      e.preventDefault();
      setIsVideoDragOver(false);
      const file = e.dataTransfer.files[0];
      if (file?.type.startsWith("video/")) {
        await processVideoUpload(file);
      } else {
        toast.error("Please drop a video file");
      }
    },
    [processVideoUpload]
  );

  // Handle save
  const handleSave = () => {
    if (!shot) return;

    const updatedShot: Shot = {
      ...shot,
      prompt,
      sourceType,
      generationMode,
      startFrameImage,
      endFrameImage,
      typedReferenceImages: typedReferenceImages.length > 0 ? typedReferenceImages : undefined,
      // Also keep referenceImages for backwards compatibility
      referenceImages:
        typedReferenceImages.length > 0 ? typedReferenceImages.map((ref) => ref.url) : undefined,
      fadeInType: fadeInType !== "none" ? fadeInType : undefined,
      fadeOutType: fadeOutType !== "none" ? fadeOutType : undefined,
      fadeDurationMs: fadeInType !== "none" || fadeOutType !== "none" ? fadeDurationMs : undefined,
      updatedAt: new Date().toISOString(),
    };

    onSave(updatedShot);
    onOpenChange(false);
  };

  // Handle generate
  const handleGenerate = () => {
    if (!onGenerateVideo) {
      toast.error("Video generation is not available");
      return;
    }
    if (!shot) return;

    // Validate requirements
    if (!prompt.trim()) {
      toast.error("Please enter a prompt");
      return;
    }

    if (generationMode === "start-frame" && !startFrameImage) {
      toast.error("Please upload a start frame image");
      return;
    }

    if (generationMode === "start-end-frame" && (!startFrameImage || !endFrameImage)) {
      toast.error("Please upload both start and end frame images");
      return;
    }

    if (generationMode === "reference-images" && typedReferenceImages.length === 0) {
      toast.error("Please add at least one reference image");
      return;
    }

    // If replacing, save old video to media library (without removing the shot)
    if (
      isReplaceMode &&
      shot.video?.url &&
      shot.video?.status === "completed" &&
      onSaveVideoToMediaLibrary
    ) {
      console.log(
        "[ShotEditorDialog] Saving old video to media library before replacing:",
        JSON.stringify({ shotId: shot.id, oldVideoUrl: shot.video.url }, null, 2)
      );
      onSaveVideoToMediaLibrary(shot);
    }

    const updatedShot: Shot = {
      ...shot,
      prompt,
      sourceType: "generated",
      generationMode,
      durationSeconds,
      startFrameImage,
      endFrameImage,
      typedReferenceImages: typedReferenceImages.length > 0 ? typedReferenceImages : undefined,
      // Also keep referenceImages for backwards compatibility
      referenceImages:
        typedReferenceImages.length > 0 ? typedReferenceImages.map((ref) => ref.url) : undefined,
      video: {
        url: "",
        status: "processing",
      },
      updatedAt: new Date().toISOString(),
    };

    setIsGenerating(true);
    onGenerateVideo(updatedShot);
    setIsReplaceMode(false);
    // Close modal immediately - generation status is tracked via shot.video.status
    // This prevents the UI from getting stuck in "Generating..." state if API fails
    onOpenChange(false);
  };

  // Handle delete
  const handleDelete = () => {
    if (!shot || !onDelete) return;
    onDelete(shot.id);
    onOpenChange(false);
  };

  // Handle detach audio - extract audio from video as independent track
  const handleDetachAudio = async () => {
    if (!shot || !shot.video?.url || !onDetachAudio) return;

    setIsDetachingAudio(true);
    try {
      // Use original video for audio extraction if available (full duration audio)
      const sourceVideo = shot.originalVideo || shot.video;

      const response = await fetch("/api/audio/extract", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          projectId,
          sceneId,
          shotId: shot.id,
          videoUrl: sourceVideo.url,
        }),
      });

      const data = await response.json();

      if (data.success) {
        // Calculate shot's timeline position and duration
        const shotStartMs = shot.startTimeMs || 0;
        const shotDurationMs = sourceVideo.durationMs || 5000;
        const shotEndMs = shotStartMs + shotDurationMs;

        // Create a new audio track positioned at the shot's end (for overlap workflow)
        const audioTrack = createNewAudioTrack(
          "", // No name needed
          "extracted",
          data.audioUrl,
          shotEndMs, // Position at shot end instead of start
          sourceVideo.durationMs || 5000
        );
        // Add the source shot reference
        audioTrack.sourceVideoShotId = shot.id;

        // Mute the shot's video since audio is now detached
        const updatedShot: Shot = {
          ...shot,
          audioMuted: true,
          updatedAt: new Date().toISOString(),
        };
        onSave(updatedShot);

        onDetachAudio(audioTrack);
        toast.success("Audio detached successfully");
      } else {
        toast.error(data.error || "Failed to extract audio");
      }
    } catch (error) {
      console.error("[ShotEditorDialog] Detach audio error:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to detach audio");
    } finally {
      setIsDetachingAudio(false);
    }
  };

  if (!shot) return null;

  const isNew = !shot.video?.url;
  const hasCompletedVideo = shot.video?.url && shot.video?.status === "completed";

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className={`max-h-[90vh] overflow-y-auto ${isNew ? "sm:max-w-2xl" : "sm:max-w-6xl"}`}
      >
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {isTrimMode ? (
              <>
                <Scissors className="h-5 w-5 text-primary" />
                Trim Video
              </>
            ) : isEffectsMode ? (
              <>
                <Sparkles className="h-5 w-5 text-primary" />
                Apply Effects
              </>
            ) : (
              <>
                <Film className="h-5 w-5 text-primary" />
                {isReplaceMode ? "Replace Shot" : isNew ? "Add Shot" : "Edit Shot"}
              </>
            )}
          </DialogTitle>
          <DialogDescription>
            {isTrimMode
              ? "Drag the handles to set in and out points. Click play to preview the trimmed segment."
              : isEffectsMode
                ? "Configure fade effects for this shot. Effects will be applied when the scene is rendered."
                : isReplaceMode
                  ? "Upload a new video or generate one to replace this shot. The current shot will be moved to the media library."
                  : hasCompletedVideo
                    ? "View and manage this shot."
                    : "Configure how this shot will be generated or upload a video directly."}
          </DialogDescription>
        </DialogHeader>

        {/* Simplified view for completed shots (unless in replace mode) */}
        {hasCompletedVideo && shot.video && !isReplaceMode ? (
          <div className="space-y-6 py-4">
            {isEffectsMode ? (
              /* ============ EFFECTS MODE ============ */
              <div className="space-y-6">
                {/* Video Preview */}
                <div className="space-y-2">
                  <Label>Video Preview</Label>
                  <div className="relative aspect-video rounded-lg overflow-hidden border border-border bg-muted/30">
                    <video
                      ref={trimmerVideoRef}
                      src={shot.video.url}
                      className="w-full h-full object-cover"
                      poster={shot.video.thumbnailUrl}
                      onLoadedMetadata={() => {
                        // Start at trim point if trimmed
                        if (trimmerVideoRef.current && shot.trimStartMs) {
                          trimmerVideoRef.current.currentTime = shot.trimStartMs / 1000;
                        }
                        // Initialize effects preview time
                        const trimStart = shot.trimStartMs || 0;
                        const videoTime = trimmerVideoRef.current?.currentTime || 0;
                        setEffectsPreviewTime(Math.max(0, videoTime * 1000 - trimStart));
                      }}
                      onTimeUpdate={(e) => {
                        const video = e.currentTarget;
                        // Store effective time (relative to trim start) in milliseconds
                        const trimStart = shot.trimStartMs || 0;
                        const effectiveTime = Math.max(0, video.currentTime * 1000 - trimStart);
                        setEffectsPreviewTime(effectiveTime);

                        // Stop at trim end point
                        if (shot.trimEndMs) {
                          const fullDuration = shot.video?.durationMs || 5000;
                          const endPoint = (fullDuration - shot.trimEndMs) / 1000;
                          if (video.currentTime >= endPoint) {
                            video.pause();
                            video.currentTime = (shot.trimStartMs || 0) / 1000;
                          }
                        }
                      }}
                      onEnded={() => {
                        // Reset to trim start on end
                        if (trimmerVideoRef.current && shot.trimStartMs) {
                          trimmerVideoRef.current.currentTime = shot.trimStartMs / 1000;
                        }
                      }}
                      controls
                    />

                    {/* Fade In Overlay */}
                    {fadeInType !== "none" &&
                      (() => {
                        const fadeDuration = fadeDurationMs;
                        const effectiveTime = effectsPreviewTime; // Already accounts for trim start
                        const fadeProgress = Math.min(1, Math.max(0, effectiveTime / fadeDuration));
                        const opacity =
                          fadeInType === "black" || fadeInType === "white" ? 1 - fadeProgress : 0;
                        const bgColor = fadeInType === "white" ? "bg-white" : "bg-black";

                        if (fadeProgress < 1 && effectiveTime >= 0) {
                          return (
                            <div
                              className={`absolute inset-0 ${bgColor} transition-opacity duration-75 pointer-events-none`}
                              style={{ opacity }}
                            />
                          );
                        }
                        return null;
                      })()}

                    {/* Fade Out Overlay */}
                    {fadeOutType !== "none" &&
                      (() => {
                        const videoDuration = shot.video?.durationMs || 5000;
                        const fadeDuration = fadeDurationMs;
                        const trimStart = shot.trimStartMs || 0;
                        const trimEnd = shot.trimEndMs || 0;
                        const effectiveDuration = videoDuration - trimStart - trimEnd;
                        const fadeOutStart = effectiveDuration - fadeDuration;
                        const effectiveTime = effectsPreviewTime; // Already accounts for trim start
                        const fadeProgress =
                          effectiveTime >= fadeOutStart
                            ? Math.min(
                                1,
                                Math.max(0, (effectiveTime - fadeOutStart) / fadeDuration)
                              )
                            : 0;
                        const opacity =
                          fadeOutType === "black" || fadeOutType === "white" ? fadeProgress : 0;
                        const bgColor = fadeOutType === "white" ? "bg-white" : "bg-black";

                        if (fadeProgress > 0 && fadeProgress <= 1) {
                          return (
                            <div
                              className={`absolute inset-0 ${bgColor} transition-opacity duration-75 pointer-events-none`}
                              style={{ opacity }}
                            />
                          );
                        }
                        return null;
                      })()}
                  </div>
                  {/* Duration info */}
                  <div className="flex items-center justify-between text-sm text-muted-foreground">
                    <span>
                      {shot.originalVideo ? (
                        <>
                          Duration: {((shot.video.durationMs || 5000) / 1000).toFixed(2)}s
                          <span className="text-xs ml-1">
                            (original: {((shot.originalVideo.durationMs || 5000) / 1000).toFixed(1)}
                            s)
                          </span>
                        </>
                      ) : (
                        <>Duration: {((shot.video.durationMs || 5000) / 1000).toFixed(1)}s</>
                      )}
                    </span>
                  </div>
                </div>

                {/* Fade Effects */}
                <div className="space-y-4">
                  <div
                    className={`grid gap-6 ${fadeInType !== "none" || fadeOutType !== "none" ? "grid-cols-3" : "grid-cols-2"}`}
                  >
                    {/* Fade In */}
                    <div className="w-full flex gap-4 items-center">
                      <Label className="text-sm py-2">Fade In</Label>
                      <Select
                        value={fadeInType}
                        onValueChange={(value) =>
                          setFadeInType(value as "none" | "black" | "white")
                        }
                      >
                        <SelectTrigger className="grow">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="none">None</SelectItem>
                          <SelectItem value="black">From Black</SelectItem>
                          <SelectItem value="white">From White</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>

                    {/* Fade Out */}
                    <div className="w-full flex gap-4 items-center">
                      <Label className="text-sm py-2">Fade Out</Label>
                      <Select
                        value={fadeOutType}
                        onValueChange={(value) =>
                          setFadeOutType(value as "none" | "black" | "white")
                        }
                      >
                        <SelectTrigger className="grow">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="none">None</SelectItem>
                          <SelectItem value="black">To Black</SelectItem>
                          <SelectItem value="white">To White</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>

                    {/* Duration */}
                    {(fadeInType !== "none" || fadeOutType !== "none") && (
                      <div className="w-full flex gap-4 items-center">
                        <Label className="text-sm py-2">Duration</Label>
                        <Select
                          value={fadeDurationMs.toString()}
                          onValueChange={(value) => setFadeDurationMs(parseInt(value, 10))}
                        >
                          <SelectTrigger className="grow">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="100">0.1s</SelectItem>
                            <SelectItem value="200">0.2s</SelectItem>
                            <SelectItem value="300">0.3s</SelectItem>
                            <SelectItem value="500">0.5s</SelectItem>
                            <SelectItem value="750">0.75s</SelectItem>
                            <SelectItem value="1000">1.0s</SelectItem>
                            <SelectItem value="1500">1.5s</SelectItem>
                            <SelectItem value="2000">2.0s</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ) : isTrimMode ? (
              /* ============ TRIM MODE ============ */
              (() => {
                // Use original video for trimming if available
                const sourceVideo = shot.originalVideo || shot.video;
                const sourceDuration = sourceVideo?.durationMs || 8000;

                return (
                  <div className="space-y-4">
                    {/* Large Video Player for Trimming */}
                    <div className="relative aspect-video rounded-lg overflow-hidden border border-border bg-black">
                      <video
                        ref={trimmerVideoRef}
                        src={sourceVideo?.url}
                        className="w-full h-full object-contain"
                        poster={sourceVideo?.thumbnailUrl}
                        onLoadedMetadata={() => {
                          // Seek to trim start position when video loads (so user sees the trimmed region)
                          if (trimmerVideoRef.current && trimStartMs > 0) {
                            trimmerVideoRef.current.currentTime = trimStartMs / 1000;
                          }
                        }}
                        onTimeUpdate={(e) => {
                          const video = e.currentTarget;
                          setTrimmerCurrentTime(video.currentTime * 1000);
                          // Stop at trim end point
                          const trimEndPoint = sourceDuration - trimEndMs;
                          if (video.currentTime * 1000 >= trimEndPoint) {
                            video.pause();
                            setIsTrimmerPlaying(false);
                          }
                        }}
                        onPlay={() => setIsTrimmerPlaying(true)}
                        onPause={() => setIsTrimmerPlaying(false)}
                        onEnded={() => setIsTrimmerPlaying(false)}
                      />

                      {/* Play/Pause Overlay */}
                      <button
                        type="button"
                        onClick={() => {
                          const video = trimmerVideoRef.current;
                          if (!video) return;

                          if (isTrimmerPlaying) {
                            video.pause();
                          } else {
                            // Start from trim start if before it or at end
                            const trimEndPoint = sourceDuration - trimEndMs;
                            if (
                              video.currentTime * 1000 < trimStartMs ||
                              video.currentTime * 1000 >= trimEndPoint
                            ) {
                              video.currentTime = trimStartMs / 1000;
                            }
                            video.play();
                          }
                        }}
                        className="absolute inset-0 flex items-center justify-center bg-black/20 opacity-0 hover:opacity-100 transition-opacity"
                      >
                        <div className="w-16 h-16 rounded-full bg-white/90 flex items-center justify-center">
                          {isTrimmerPlaying ? (
                            <Pause className="h-7 w-7 text-black" />
                          ) : (
                            <Play className="h-7 w-7 text-black ml-1" />
                          )}
                        </div>
                      </button>
                    </div>

                    {/* Trim Timeline Bar */}
                    <div className="space-y-3 px-1">
                      {/* Custom trim bar with draggable handles */}
                      <div className="relative h-12 bg-muted border border-border rounded overflow-visible">
                        {/* Audio Waveform Background - show waveform for any video (even if audio is muted/detached) */}
                        {sourceVideo?.url && (
                          <div className="absolute inset-0 z-0 overflow-hidden rounded">
                            <AudioWaveform
                              audioUrl={sourceVideo.url}
                              width={600}
                              height={48}
                              color="hsl(var(--primary) / 0.4)"
                              className="w-full h-full"
                            />
                          </div>
                        )}

                        {/* Active region highlight (between handles) */}
                        <div
                          className="absolute inset-y-0 bg-primary/15 z-10"
                          style={{
                            left: `${(trimStartMs / sourceDuration) * 100}%`,
                            right: `${(trimEndMs / sourceDuration) * 100}%`,
                          }}
                        />
                        {/* Trimmed out regions (dark overlay) */}
                        <div
                          className="absolute inset-y-0 left-0 bg-black/60 rounded-l z-10"
                          style={{ width: `${(trimStartMs / sourceDuration) * 100}%` }}
                        />
                        <div
                          className="absolute inset-y-0 right-0 bg-black/60 rounded-r z-10"
                          style={{ width: `${(trimEndMs / sourceDuration) * 100}%` }}
                        />

                        {/* Left trim handle (In point) - vertical line */}
                        {/* NOTE: During dragging, we only update local state. The trimmed video is NOT saved until "Apply Trim" is clicked. */}
                        <div
                          className="absolute top-0 bottom-0 w-1 bg-primary cursor-ew-resize z-30"
                          style={{
                            left: `${(trimStartMs / sourceDuration) * 100}%`,
                            transform: "translateX(-50%)",
                          }}
                          onMouseDown={(e) => {
                            e.stopPropagation();
                            const startX = e.clientX;
                            const startValue = trimStartMs;
                            const containerWidth = e.currentTarget.parentElement?.offsetWidth || 1;

                            const handleMouseMove = (moveEvent: MouseEvent) => {
                              const deltaX = moveEvent.clientX - startX;
                              const deltaMs = (deltaX / containerWidth) * sourceDuration;
                              const newValue = Math.max(
                                0,
                                Math.min(sourceDuration - trimEndMs - 100, startValue + deltaMs)
                              );
                              // Only update local state during dragging - no API calls or saves
                              setTrimStartMs(newValue);
                              if (trimmerVideoRef.current) {
                                trimmerVideoRef.current.currentTime = newValue / 1000;
                                setTrimmerCurrentTime(newValue);
                              }
                            };

                            const handleMouseUp = () => {
                              document.removeEventListener("mousemove", handleMouseMove);
                              document.removeEventListener("mouseup", handleMouseUp);
                            };

                            document.addEventListener("mousemove", handleMouseMove);
                            document.addEventListener("mouseup", handleMouseUp);
                          }}
                        />

                        {/* Right trim handle (Out point) - vertical line */}
                        {/* NOTE: During dragging, we only update local state. The trimmed video is NOT saved until "Apply Trim" is clicked. */}
                        <div
                          className="absolute top-0 bottom-0 w-1 bg-primary cursor-ew-resize z-30"
                          style={{
                            left: `${((sourceDuration - trimEndMs) / sourceDuration) * 100}%`,
                            transform: "translateX(-50%)",
                          }}
                          onMouseDown={(e) => {
                            e.stopPropagation();
                            const startX = e.clientX;
                            const startValue = trimEndMs;
                            const containerWidth = e.currentTarget.parentElement?.offsetWidth || 1;

                            const handleMouseMove = (moveEvent: MouseEvent) => {
                              const deltaX = moveEvent.clientX - startX;
                              const deltaMs = (deltaX / containerWidth) * sourceDuration;
                              const newValue = Math.max(
                                0,
                                Math.min(sourceDuration - trimStartMs - 100, startValue - deltaMs)
                              );
                              // Only update local state during dragging - no API calls or saves
                              setTrimEndMs(newValue);
                              if (trimmerVideoRef.current) {
                                const outPoint = (sourceDuration - newValue) / 1000;
                                trimmerVideoRef.current.currentTime = outPoint;
                                setTrimmerCurrentTime(sourceDuration - newValue);
                              }
                            };

                            const handleMouseUp = () => {
                              document.removeEventListener("mousemove", handleMouseMove);
                              document.removeEventListener("mouseup", handleMouseUp);
                            };

                            document.addEventListener("mousemove", handleMouseMove);
                            document.addEventListener("mouseup", handleMouseUp);
                          }}
                        />
                      </div>

                      {/* Time labels */}
                      <div className="flex justify-between items-center text-sm">
                        <div className="text-muted-foreground">
                          <span className="text-xs">In:</span>{" "}
                          <span className="font-mono">{(trimStartMs / 1000).toFixed(2)}s</span>
                        </div>
                        <div className="text-center">
                          <span className="text-xs text-muted-foreground">Duration:</span>{" "}
                          <span className="font-mono font-medium text-foreground">
                            {((sourceDuration - trimStartMs - trimEndMs) / 1000).toFixed(2)}s
                          </span>
                        </div>
                        <div className="text-muted-foreground">
                          <span className="text-xs">Out:</span>{" "}
                          <span className="font-mono">
                            {((sourceDuration - trimEndMs) / 1000).toFixed(2)}s
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })()
            ) : (
              /* ============ NORMAL VIEW ============ */
              <>
                {/* Video Preview */}
                <div className="space-y-2">
                  <Label>Video</Label>
                  <div className="relative aspect-video rounded-lg overflow-hidden border border-border bg-muted/30">
                    <video
                      ref={trimmerVideoRef}
                      src={shot.video.url}
                      className="w-full h-full object-cover"
                      poster={shot.video.thumbnailUrl}
                      onLoadedMetadata={() => {
                        // Start at trim point if trimmed
                        if (trimmerVideoRef.current && shot.trimStartMs) {
                          trimmerVideoRef.current.currentTime = shot.trimStartMs / 1000;
                        }
                        // Initialize normal preview time
                        const trimStart = shot.trimStartMs || 0;
                        const videoTime = trimmerVideoRef.current?.currentTime || 0;
                        setNormalPreviewTime(Math.max(0, videoTime * 1000 - trimStart));
                      }}
                      onTimeUpdate={(e) => {
                        const video = e.currentTarget;
                        // Store effective time (relative to trim start) in milliseconds
                        const trimStart = shot.trimStartMs || 0;
                        const effectiveTime = Math.max(0, video.currentTime * 1000 - trimStart);
                        setNormalPreviewTime(effectiveTime);

                        // Stop at trim end point
                        if (shot.trimEndMs) {
                          const fullDuration = shot.video?.durationMs || 5000;
                          const endPoint = (fullDuration - shot.trimEndMs) / 1000;
                          if (video.currentTime >= endPoint) {
                            video.pause();
                            video.currentTime = (shot.trimStartMs || 0) / 1000;
                          }
                        }
                      }}
                      onEnded={() => {
                        // Reset to trim start on end
                        if (trimmerVideoRef.current && shot.trimStartMs) {
                          trimmerVideoRef.current.currentTime = shot.trimStartMs / 1000;
                        }
                      }}
                      controls
                    />

                    {/* Fade In Overlay */}
                    {shot.fadeInType &&
                      shot.fadeInType !== "none" &&
                      (() => {
                        const fadeDuration = shot.fadeDurationMs || 500;
                        const effectiveTime = normalPreviewTime; // Already accounts for trim start
                        const fadeProgress = Math.min(1, Math.max(0, effectiveTime / fadeDuration));
                        const opacity =
                          shot.fadeInType === "black" || shot.fadeInType === "white"
                            ? 1 - fadeProgress
                            : 0;
                        const bgColor = shot.fadeInType === "white" ? "bg-white" : "bg-black";

                        if (fadeProgress < 1 && effectiveTime >= 0) {
                          return (
                            <div
                              className={`absolute inset-0 ${bgColor} transition-opacity duration-75 pointer-events-none z-10`}
                              style={{ opacity }}
                            />
                          );
                        }
                        return null;
                      })()}

                    {/* Fade Out Overlay */}
                    {shot.fadeOutType &&
                      shot.fadeOutType !== "none" &&
                      (() => {
                        const videoDuration = shot.video?.durationMs || 5000;
                        const fadeDuration = shot.fadeDurationMs || 500;
                        const trimStart = shot.trimStartMs || 0;
                        const trimEnd = shot.trimEndMs || 0;
                        const effectiveDuration = videoDuration - trimStart - trimEnd;
                        const fadeOutStart = effectiveDuration - fadeDuration;
                        const effectiveTime = normalPreviewTime; // Already accounts for trim start
                        const fadeProgress =
                          effectiveTime >= fadeOutStart
                            ? Math.min(
                                1,
                                Math.max(0, (effectiveTime - fadeOutStart) / fadeDuration)
                              )
                            : 0;
                        const opacity =
                          shot.fadeOutType === "black" || shot.fadeOutType === "white"
                            ? fadeProgress
                            : 0;
                        const bgColor = shot.fadeOutType === "white" ? "bg-white" : "bg-black";

                        if (fadeProgress > 0 && fadeProgress <= 1) {
                          return (
                            <div
                              className={`absolute inset-0 ${bgColor} transition-opacity duration-75 pointer-events-none z-10`}
                              style={{ opacity }}
                            />
                          );
                        }
                        return null;
                      })()}
                  </div>
                  {/* Duration info */}
                  <div className="flex items-center justify-between text-sm text-muted-foreground">
                    <span>
                      {shot.originalVideo ? (
                        <>
                          Duration: {((shot.video.durationMs || 5000) / 1000).toFixed(2)}s
                          <span className="text-xs ml-1">
                            (original: {((shot.originalVideo.durationMs || 5000) / 1000).toFixed(1)}
                            s)
                          </span>
                        </>
                      ) : (
                        <>Duration: {((shot.video.durationMs || 5000) / 1000).toFixed(1)}s</>
                      )}
                    </span>
                    {shot.originalVideo && (
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        className="text-xs h-6 px-2"
                        onClick={() => {
                          // Restore original video
                          const updatedShot: Shot = {
                            ...shot,
                            video: shot.originalVideo,
                            originalVideo: undefined,
                            trimStartMs: undefined,
                            trimEndMs: undefined,
                            updatedAt: new Date().toISOString(),
                          };
                          onSave(updatedShot);
                          toast.success("Original video restored");
                        }}
                      >
                        Restore Original
                      </Button>
                    )}
                  </div>
                </div>

                {shot.prompt && (
                  <div className="space-y-2">
                    <Label>Prompt</Label>
                    <p className="text-sm text-muted-foreground">{shot.prompt}</p>
                  </div>
                )}

                {/* Reference Images */}
                {(shot.typedReferenceImages && shot.typedReferenceImages.length > 0) ||
                (shot.referenceImages && shot.referenceImages.length > 0) ||
                shot.startFrameImage ||
                shot.endFrameImage ? (
                  <div className="space-y-2">
                    <Label>Reference Images</Label>
                    <div className="grid grid-cols-3 gap-1">
                      {/* Typed reference images */}
                      {shot.typedReferenceImages?.map((ref, idx) => (
                        <div
                          key={`ref-${idx}`}
                          className="relative aspect-video rounded-lg overflow-hidden border border-border group h-20"
                        >
                          <Image
                            src={ref.url}
                            alt={ref.name || `Reference ${idx + 1}`}
                            fill
                            className="object-cover"
                          />
                          <div className="absolute bottom-0 left-0 right-0 bg-black/60 px-1 py-0.5">
                            <div className="flex items-center gap-1 text-[9px] text-white">
                              {ref.type === "location" ? (
                                <MapPin className="h-2 w-2" />
                              ) : (
                                <User className="h-2 w-2" />
                              )}
                              <span className="truncate">{ref.name || ref.type}</span>
                            </div>
                          </div>
                        </div>
                      ))}

                      {/* Legacy reference images (URLs only) */}
                      {shot.referenceImages
                        ?.filter(
                          (url) => !shot.typedReferenceImages?.some((ref) => ref.url === url)
                        )
                        .map((url, idx) => (
                          <div
                            key={`legacy-ref-${idx}`}
                            className="relative aspect-video rounded-lg overflow-hidden border border-border h-20"
                          >
                            <Image
                              src={url}
                              alt={`Reference ${idx + 1}`}
                              fill
                              className="object-cover"
                            />
                          </div>
                        ))}

                      {/* Start frame */}
                      {shot.startFrameImage && (
                        <div className="relative aspect-video rounded-lg overflow-hidden border border-border h-20">
                          <Image
                            src={shot.startFrameImage}
                            alt="Start frame"
                            fill
                            className="object-cover"
                          />
                          <div className="absolute bottom-0 left-0 right-0 bg-black/60 px-1 py-0.5">
                            <span className="text-[9px] text-white">Start Frame</span>
                          </div>
                        </div>
                      )}

                      {/* End frame */}
                      {shot.endFrameImage && (
                        <div className="relative aspect-video rounded-lg overflow-hidden border border-border h-20">
                          <Image
                            src={shot.endFrameImage}
                            alt="End frame"
                            fill
                            className="object-cover"
                          />
                          <div className="absolute bottom-0 left-0 right-0 bg-black/60 px-1 py-0.5">
                            <span className="text-[9px] text-white">End Frame</span>
                          </div>
                        </div>
                      )}
                    </div>
                  </div>
                ) : null}
              </>
            )}
          </div>
        ) : (
          <div className="space-y-6 py-4">
            {/* Source Type Toggle */}
            <div className="space-y-2">
              <Label>Source</Label>
              <div className="flex gap-2">
                {isVideoGenerationEnabled() && onGenerateVideo && (
                  <Button
                    type="button"
                    variant={sourceType === "generated" ? "default" : "outline"}
                    onClick={() => setSourceType("generated")}
                    className="flex-1"
                  >
                    <Sparkles className="h-4 w-4 mr-2" />
                    Generate with AI
                  </Button>
                )}
                <Button
                  type="button"
                  variant={sourceType === "uploaded" ? "default" : "outline"}
                  onClick={() => {
                    setSourceType("uploaded");
                    // Trigger file picker after re-render when input is available
                    setShouldOpenFilePicker(true);
                  }}
                  className={isVideoGenerationEnabled() && onGenerateVideo ? "flex-1" : "w-full"}
                >
                  <Upload className="h-4 w-4 mr-2" />
                  Upload Video
                </Button>
              </div>
              {!isVideoGenerationEnabled() && (
                <p className="text-xs text-muted-foreground mt-2">
                  Video generation is only available in development mode. Please upload a video file
                  instead.
                </p>
              )}
            </div>

            {sourceType === "generated" ? (
              <>
                {/* Generation Mode */}
                <div className="space-y-2 w-full">
                  <Label>Generation Mode</Label>
                  <Select
                    value={generationMode}
                    onValueChange={(v) => {
                      setGenerationMode(v as GenerationMode);
                      // Reference images mode requires 8 seconds duration
                      if (v === "reference-images") {
                        setDurationSeconds(8);
                      }
                    }}
                  >
                    <SelectTrigger className="w-full h-auto! py-3 [&>span]:flex-1 [&>span]:text-center">
                      <SelectValue>
                        <div className="flex flex-col items-center w-full">
                          <div className="font-medium">
                            {GENERATION_MODES.find((m) => m.value === generationMode)?.label}
                          </div>
                          <div className="text-xs text-muted-foreground">
                            {GENERATION_MODES.find((m) => m.value === generationMode)?.description}
                          </div>
                        </div>
                      </SelectValue>
                    </SelectTrigger>
                    <SelectContent>
                      {GENERATION_MODES.map((mode) => (
                        <SelectItem
                          key={mode.value}
                          value={mode.value}
                          className="h-auto! py-3 justify-center pl-8"
                        >
                          <div className="flex flex-col items-center text-center">
                            <div className="font-medium">{mode.label}</div>
                            <div className="text-xs">{mode.description}</div>
                          </div>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                {/* Image inputs based on mode */}
                {/* Start Frame Mode */}
                {generationMode === "start-frame" && (
                  <div className="space-y-4">
                    <div className="flex items-center justify-between">
                      <Label>Start Frame Image</Label>
                      <div className="flex gap-1">
                        <Button
                          type="button"
                          variant={startFrameInputMode === "upload" ? "default" : "outline"}
                          size="sm"
                          onClick={() => setStartFrameInputMode("upload")}
                          className="text-xs"
                        >
                          <Upload className="h-3 w-3 mr-1" />
                          Upload
                        </Button>
                        <Button
                          type="button"
                          variant={startFrameInputMode === "generate" ? "default" : "outline"}
                          size="sm"
                          onClick={() => setStartFrameInputMode("generate")}
                          className="text-xs"
                        >
                          <Sparkles className="h-3 w-3 mr-1" />
                          Generate AI
                        </Button>
                      </div>
                    </div>

                    {startFrameInputMode === "upload" ? (
                      <ImageDropZone
                        label=""
                        imageUrl={startFrameImage}
                        onImageSelect={(file) => handleImageUpload(file, "start")}
                        onImageRemove={() => setStartFrameImage(undefined)}
                        disabled={isUploading}
                      />
                    ) : (
                      <div className="grid grid-cols-2 gap-4">
                        {/* Left: Generation Controls */}
                        <div className="space-y-3">
                          <div className="space-y-2">
                            <Label className="text-xs">Describe the image</Label>
                            <Textarea
                              value={startFramePrompt}
                              onChange={(e) => setStartFramePrompt(e.target.value)}
                              placeholder="A futuristic office with holographic displays, a man in a suit standing at his desk..."
                              rows={3}
                              className="text-sm"
                            />
                          </div>

                          {/* Reference Images for Generation */}
                          <div className="space-y-2">
                            <Label className="text-xs">
                              Reference Images (optional, {startFrameReferenceImages.length}/3)
                            </Label>
                            {startFrameReferenceImages.length > 0 && (
                              <div className="flex gap-1 flex-wrap">
                                {startFrameReferenceImages.map((ref, idx) => (
                                  <div
                                    key={idx}
                                    className="relative w-12 h-12 rounded overflow-hidden group"
                                  >
                                    <Image
                                      src={ref.url}
                                      alt={ref.name || ""}
                                      fill
                                      className="object-cover"
                                    />
                                    <button
                                      type="button"
                                      onClick={() => removeFrameReferenceImage("start", idx)}
                                      className="absolute inset-0 bg-black/50 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                                    >
                                      <X className="h-3 w-3 text-white" />
                                    </button>
                                  </div>
                                ))}
                              </div>
                            )}

                            {/* Quick add from project assets */}
                            {startFrameReferenceImages.length < 3 && (
                              <div className="flex flex-wrap gap-1">
                                {/* Scene Location */}
                                {sceneLocationId &&
                                  locations.find((l) => l.name === sceneLocationId)?.image && (
                                    <button
                                      type="button"
                                      onClick={() => {
                                        const loc = locations.find(
                                          (l) => l.name === sceneLocationId
                                        );
                                        if (loc?.image) {
                                          addFrameReferenceImage(
                                            "start",
                                            getImageUrl({
                                              type: "location",
                                              filename: loc.image,
                                              username,
                                            }),
                                            "location",
                                            loc.name
                                          );
                                        }
                                      }}
                                      disabled={startFrameReferenceImages.some(
                                        (r) => r.name === sceneLocationId
                                      )}
                                      className="text-[10px] px-2 py-1 rounded bg-blue-500/10 text-blue-600 hover:bg-blue-500/20 disabled:opacity-50 flex items-center gap-1"
                                    >
                                      <MapPin className="h-2.5 w-2.5" />
                                      {sceneLocationId}
                                    </button>
                                  )}
                                {/* Scene Characters */}
                                {sceneCharacters.map((charName) => {
                                  const char = characters.find((c) => c.name === charName);
                                  if (!char?.mainImage) return null;
                                  return (
                                    <button
                                      key={charName}
                                      type="button"
                                      onClick={() => {
                                        addFrameReferenceImage(
                                          "start",
                                          getImageUrl({
                                            type: "character",
                                            filename: char.mainImage!,
                                            username,
                                          }),
                                          "character",
                                          charName
                                        );
                                      }}
                                      disabled={startFrameReferenceImages.some(
                                        (r) => r.name === charName
                                      )}
                                      className="text-[10px] px-2 py-1 rounded bg-purple-500/10 text-purple-600 hover:bg-purple-500/20 disabled:opacity-50 flex items-center gap-1"
                                    >
                                      <User className="h-2.5 w-2.5" />
                                      {charName}
                                    </button>
                                  );
                                })}
                              </div>
                            )}
                          </div>

                          <Button
                            type="button"
                            onClick={() => handleGenerateFrameImage("start")}
                            disabled={isGeneratingStartFrame || !startFramePrompt.trim()}
                            className="w-full"
                            size="sm"
                          >
                            {isGeneratingStartFrame ? (
                              <>
                                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                                Generating...
                              </>
                            ) : (
                              <>
                                <Sparkles className="h-4 w-4 mr-2" />
                                Generate Start Frame
                              </>
                            )}
                          </Button>
                        </div>

                        {/* Right: Preview */}
                        <div className="space-y-2">
                          <Label className="text-xs">Preview</Label>
                          {startFrameImage ? (
                            <div className="relative aspect-video rounded-lg overflow-hidden border border-border group">
                              <Image
                                src={startFrameImage}
                                alt="Start frame"
                                fill
                                className="object-cover"
                              />
                              <button
                                type="button"
                                onClick={() => setStartFrameImage(undefined)}
                                className="absolute top-2 right-2 p-1 rounded-full bg-destructive text-destructive-foreground opacity-0 group-hover:opacity-100 transition-opacity"
                              >
                                <X className="h-4 w-4" />
                              </button>
                            </div>
                          ) : (
                            <div className="aspect-video rounded-lg border-2 border-dashed border-muted-foreground/30 flex items-center justify-center">
                              <div className="text-center text-muted-foreground">
                                <ImageIcon className="h-8 w-8 mx-auto mb-2 opacity-50" />
                                <p className="text-xs">Generated image will appear here</p>
                              </div>
                            </div>
                          )}
                        </div>
                      </div>
                    )}
                  </div>
                )}

                {/* Start + End Frame Mode */}
                {generationMode === "start-end-frame" && (
                  <div className="grid grid-cols-2 gap-6">
                    {/* Start Frame */}
                    <div className="space-y-3">
                      <div className="flex items-center justify-between">
                        <Label className="text-sm font-medium">Start Frame</Label>
                        <div className="flex gap-1">
                          <Button
                            type="button"
                            variant={startFrameInputMode === "upload" ? "default" : "outline"}
                            size="sm"
                            onClick={() => setStartFrameInputMode("upload")}
                            className="text-[10px] h-6 px-2"
                          >
                            <Upload className="h-2.5 w-2.5 mr-1" />
                            Upload
                          </Button>
                          <Button
                            type="button"
                            variant={startFrameInputMode === "generate" ? "default" : "outline"}
                            size="sm"
                            onClick={() => setStartFrameInputMode("generate")}
                            className="text-[10px] h-6 px-2"
                          >
                            <Sparkles className="h-2.5 w-2.5 mr-1" />
                            AI
                          </Button>
                        </div>
                      </div>

                      {startFrameInputMode === "upload" ? (
                        <ImageDropZone
                          label=""
                          imageUrl={startFrameImage}
                          onImageSelect={(file) => handleImageUpload(file, "start")}
                          onImageRemove={() => setStartFrameImage(undefined)}
                          disabled={isUploading}
                        />
                      ) : (
                        <div className="space-y-2">
                          <Textarea
                            value={startFramePrompt}
                            onChange={(e) => setStartFramePrompt(e.target.value)}
                            placeholder="Describe the starting image..."
                            rows={2}
                            className="text-xs"
                          />
                          {startFrameImage ? (
                            <div className="relative aspect-video rounded-lg overflow-hidden border border-border group">
                              <Image
                                src={startFrameImage}
                                alt="Start frame"
                                fill
                                className="object-cover"
                              />
                              <button
                                type="button"
                                onClick={() => setStartFrameImage(undefined)}
                                className="absolute top-1 right-1 p-0.5 rounded-full bg-destructive text-destructive-foreground opacity-0 group-hover:opacity-100 transition-opacity"
                              >
                                <X className="h-3 w-3" />
                              </button>
                            </div>
                          ) : (
                            <Button
                              type="button"
                              onClick={() => handleGenerateFrameImage("start")}
                              disabled={isGeneratingStartFrame || !startFramePrompt.trim()}
                              className="w-full"
                              size="sm"
                            >
                              {isGeneratingStartFrame ? (
                                <Loader2 className="h-3 w-3 animate-spin" />
                              ) : (
                                <>
                                  <Sparkles className="h-3 w-3 mr-1" />
                                  Generate
                                </>
                              )}
                            </Button>
                          )}
                        </div>
                      )}
                    </div>

                    {/* End Frame */}
                    <div className="space-y-3">
                      <div className="flex items-center justify-between">
                        <Label className="text-sm font-medium">End Frame</Label>
                        <div className="flex gap-1">
                          <Button
                            type="button"
                            variant={endFrameInputMode === "upload" ? "default" : "outline"}
                            size="sm"
                            onClick={() => setEndFrameInputMode("upload")}
                            className="text-[10px] h-6 px-2"
                          >
                            <Upload className="h-2.5 w-2.5 mr-1" />
                            Upload
                          </Button>
                          <Button
                            type="button"
                            variant={endFrameInputMode === "generate" ? "default" : "outline"}
                            size="sm"
                            onClick={() => setEndFrameInputMode("generate")}
                            className="text-[10px] h-6 px-2"
                          >
                            <Sparkles className="h-2.5 w-2.5 mr-1" />
                            AI
                          </Button>
                        </div>
                      </div>

                      {endFrameInputMode === "upload" ? (
                        <ImageDropZone
                          label=""
                          imageUrl={endFrameImage}
                          onImageSelect={(file) => handleImageUpload(file, "end")}
                          onImageRemove={() => setEndFrameImage(undefined)}
                          disabled={isUploading}
                        />
                      ) : (
                        <div className="space-y-2">
                          <Textarea
                            value={endFramePrompt}
                            onChange={(e) => setEndFramePrompt(e.target.value)}
                            placeholder="Describe the ending image..."
                            rows={2}
                            className="text-xs"
                          />
                          {endFrameImage ? (
                            <div className="relative aspect-video rounded-lg overflow-hidden border border-border group">
                              <Image
                                src={endFrameImage}
                                alt="End frame"
                                fill
                                className="object-cover"
                              />
                              <button
                                type="button"
                                onClick={() => setEndFrameImage(undefined)}
                                className="absolute top-1 right-1 p-0.5 rounded-full bg-destructive text-destructive-foreground opacity-0 group-hover:opacity-100 transition-opacity"
                              >
                                <X className="h-3 w-3" />
                              </button>
                            </div>
                          ) : (
                            <Button
                              type="button"
                              onClick={() => handleGenerateFrameImage("end")}
                              disabled={isGeneratingEndFrame || !endFramePrompt.trim()}
                              className="w-full"
                              size="sm"
                            >
                              {isGeneratingEndFrame ? (
                                <Loader2 className="h-3 w-3 animate-spin" />
                              ) : (
                                <>
                                  <Sparkles className="h-3 w-3 mr-1" />
                                  Generate
                                </>
                              )}
                            </Button>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                )}

                {generationMode === "reference-images" && (
                  <div className="space-y-4">
                    {/* Selected Reference Images */}
                    <div className="space-y-2">
                      <Label>Selected Reference Images ({typedReferenceImages.length}/3)</Label>
                      {typedReferenceImages.length > 0 ? (
                        <div className="grid grid-cols-3 gap-2">
                          {typedReferenceImages.map((ref, index) => (
                            <div
                              key={index}
                              className="relative aspect-video rounded-lg overflow-hidden border border-border group"
                            >
                              <Image
                                src={ref.url}
                                alt={ref.name || `Reference ${index + 1}`}
                                fill
                                className="object-cover"
                              />
                              {/* Type badge */}
                              <div
                                className={`absolute bottom-1 left-1 px-1.5 py-0.5 rounded text-[10px] font-medium flex items-center gap-1 ${
                                  ref.type === "location"
                                    ? "bg-blue-500/90 text-white"
                                    : "bg-purple-500/90 text-white"
                                }`}
                              >
                                {ref.type === "location" ? (
                                  <MapPin className="h-2.5 w-2.5" />
                                ) : (
                                  <User className="h-2.5 w-2.5" />
                                )}
                                {ref.name || ref.type}
                              </div>
                              <button
                                type="button"
                                onClick={() => removeTypedReferenceImage(index)}
                                className="absolute top-1 right-1 p-0.5 rounded-full bg-destructive text-destructive-foreground opacity-0 group-hover:opacity-100 transition-opacity z-10"
                              >
                                <X className="h-3 w-3" />
                              </button>
                            </div>
                          ))}
                        </div>
                      ) : (
                        <p className="text-sm text-muted-foreground">
                          Select location or character images below to add as references
                        </p>
                      )}
                    </div>

                    {/* Scene Location and Character Images */}
                    {typedReferenceImages.length < 3 && (
                      <div className="space-y-4">
                        {/* Scene Location Images */}
                        {(() => {
                          const sceneLocation = sceneLocationId
                            ? locations.find(
                                (loc) =>
                                  loc.name === sceneLocationId &&
                                  (loc.image || (loc.images && loc.images.length > 0))
                              )
                            : null;

                          if (!sceneLocation) return null;

                          // Collect all location images (main + additional)
                          const allLocationImages: string[] = [];
                          if (sceneLocation.image) {
                            allLocationImages.push(sceneLocation.image);
                          }
                          if (sceneLocation.images) {
                            allLocationImages.push(...sceneLocation.images.filter(Boolean));
                          }

                          if (allLocationImages.length === 0) return null;

                          return (
                            <div className="space-y-2">
                              <Label className="text-xs font-medium text-muted-foreground flex items-center gap-1.5">
                                <MapPin className="h-3 w-3 text-blue-500" />
                                Location: {sceneLocation.name}
                              </Label>
                              <div className="flex flex-wrap gap-2">
                                {allLocationImages.map((filename, index) => {
                                  const imageUrl = getImageUrl({
                                    type: "location",
                                    filename,
                                    username,
                                  });
                                  const isSelected = typedReferenceImages.some(
                                    (ref) => ref.url === imageUrl
                                  );
                                  return (
                                    <button
                                      key={`${sceneLocation.name}-${index}`}
                                      type="button"
                                      onClick={() =>
                                        addReferenceImage(imageUrl, "location", sceneLocation.name)
                                      }
                                      disabled={isSelected || isUploading}
                                      className={`relative w-28 aspect-video rounded-lg overflow-hidden border-2 transition-all ${
                                        isSelected
                                          ? "border-blue-500 opacity-50 cursor-not-allowed"
                                          : "border-blue-500/50 hover:border-blue-500 cursor-pointer"
                                      }`}
                                    >
                                      <Image
                                        src={imageUrl}
                                        alt={`${sceneLocation.name} ${index + 1}`}
                                        fill
                                        className="object-cover"
                                      />
                                      {isSelected && (
                                        <div className="absolute inset-0 flex items-center justify-center bg-black/30">
                                          <span className="text-white text-xs font-medium">
                                            Added
                                          </span>
                                        </div>
                                      )}
                                    </button>
                                  );
                                })}
                              </div>
                            </div>
                          );
                        })()}

                        {/* Scene Characters Images */}
                        {(() => {
                          const sceneChars = characters.filter(
                            (char) =>
                              sceneCharacters.includes(char.name) &&
                              (char.mainImage || (char.images && char.images.length > 0))
                          );

                          if (sceneChars.length === 0) return null;

                          return (
                            <div className="space-y-2">
                              <Label className="text-xs font-medium text-muted-foreground flex items-center gap-1.5">
                                <User className="h-3 w-3 text-purple-500" />
                                Characters
                              </Label>
                              <div className="flex flex-wrap gap-2">
                                {sceneChars.flatMap((character) => {
                                  // Collect all character images (main + additional)
                                  const allCharImages: string[] = [];
                                  if (character.mainImage) {
                                    allCharImages.push(character.mainImage);
                                  }
                                  if (character.images) {
                                    allCharImages.push(...character.images.filter(Boolean));
                                  }

                                  return allCharImages.map((filename, index) => {
                                    const imageUrl = getImageUrl({
                                      type: "character",
                                      filename,
                                      username,
                                    });
                                    const isSelected = typedReferenceImages.some(
                                      (ref) => ref.url === imageUrl
                                    );
                                    return (
                                      <button
                                        key={`${character.name}-${index}`}
                                        type="button"
                                        onClick={() =>
                                          addReferenceImage(imageUrl, "character", character.name)
                                        }
                                        disabled={isSelected || isUploading}
                                        className={`relative w-28 aspect-video rounded-lg overflow-hidden border-2 transition-all ${
                                          isSelected
                                            ? "border-purple-500 opacity-50 cursor-not-allowed"
                                            : "border-purple-500/50 hover:border-purple-500 cursor-pointer"
                                        }`}
                                      >
                                        <Image
                                          src={imageUrl}
                                          alt={`${character.name} ${index + 1}`}
                                          fill
                                          className="object-cover"
                                        />
                                        <div className="absolute inset-x-0 bottom-0 bg-linear-to-t from-black/80 to-transparent p-1">
                                          <span className="text-[10px] text-white truncate block">
                                            {character.name}
                                          </span>
                                        </div>
                                        {isSelected && (
                                          <div className="absolute inset-0 flex items-center justify-center bg-black/30">
                                            <span className="text-white text-xs font-medium">
                                              Added
                                            </span>
                                          </div>
                                        )}
                                      </button>
                                    );
                                  });
                                })}
                              </div>
                            </div>
                          );
                        })()}
                      </div>
                    )}
                  </div>
                )}

                {/* Prompt */}
                <div className="space-y-2">
                  <Label htmlFor="shot-prompt">
                    {generationMode === "text-only" ? "Video Description" : "Prompt"}
                  </Label>
                  <Textarea
                    id="shot-prompt"
                    value={prompt}
                    onChange={(e) => setPrompt(e.target.value)}
                    placeholder={
                      generationMode === "text-only"
                        ? "Describe the video you want to generate..."
                        : "Describe how the scene should play out..."
                    }
                    rows={3}
                  />
                </div>

                {/* Duration - Note: Reference images mode requires 8 seconds */}
                <div className="space-y-2">
                  <Label>Duration</Label>
                  {generationMode === "reference-images" ? (
                    <div className="text-sm text-muted-foreground p-2 bg-muted rounded-md">
                      Duration is fixed to <strong>8 seconds</strong> when using reference images.
                    </div>
                  ) : (
                    <div className="flex gap-2">
                      <Button
                        type="button"
                        variant={durationSeconds === 4 ? "default" : "outline"}
                        onClick={() => setDurationSeconds(4)}
                        className="flex-1"
                      >
                        4 seconds
                      </Button>
                      <Button
                        type="button"
                        variant={durationSeconds === 6 ? "default" : "outline"}
                        onClick={() => setDurationSeconds(6)}
                        className="flex-1"
                      >
                        6 seconds
                      </Button>
                      <Button
                        type="button"
                        variant={durationSeconds === 8 ? "default" : "outline"}
                        onClick={() => setDurationSeconds(8)}
                        className="flex-1"
                      >
                        8 seconds
                      </Button>
                    </div>
                  )}
                </div>
              </>
            ) : (
              /* Upload Video */
              <div className="space-y-2">
                <Label>Upload Video</Label>
                <input
                  ref={videoInputRef}
                  type="file"
                  accept="video/mp4,video/webm,video/quicktime"
                  onChange={handleVideoUpload}
                  className="hidden"
                />
                {/* Show existing video only if not in replace mode */}
                {shot.video?.url && !isReplaceMode ? (
                  <div className="relative aspect-video rounded-lg overflow-hidden border border-border">
                    <video src={shot.video.url} controls className="w-full h-full object-cover" />
                  </div>
                ) : (
                  <button
                    type="button"
                    onClick={() => videoInputRef.current?.click()}
                    onDragOver={handleVideoDragOver}
                    onDragLeave={handleVideoDragLeave}
                    onDrop={handleVideoDrop}
                    disabled={isUploading}
                    className={`
                    w-full aspect-video rounded-lg border-2 border-dashed flex flex-col items-center justify-center gap-2 transition-colors relative overflow-hidden cursor-pointer
                    ${isVideoDragOver ? "border-primary bg-primary/5" : "border-muted-foreground/30 hover:border-primary/50"}
                    ${isUploading ? "opacity-50 cursor-not-allowed" : ""}
                  `}
                  >
                    {isUploading ? (
                      <>
                        {/* Progress bar background */}
                        <div
                          className="absolute inset-0 bg-primary/10 transition-all duration-300"
                          style={{ width: `${uploadProgress}%` }}
                        />
                        <div className="relative z-10 flex flex-col items-center gap-2">
                          <Loader2 className="h-8 w-8 animate-spin text-primary" />
                          <span className="text-sm font-medium text-primary">
                            Uploading... {uploadProgress}%
                          </span>
                        </div>
                      </>
                    ) : (
                      <>
                        <Video className="h-8 w-8 text-muted-foreground" />
                        <span className="text-sm text-muted-foreground">
                          Drop video or click to upload
                        </span>
                        <span className="text-xs text-muted-foreground">
                          Supports files up to 500MB
                        </span>
                      </>
                    )}
                  </button>
                )}
              </div>
            )}
          </div>
        )}

        <DialogFooter className="flex-col sm:flex-row gap-2">
          {hasCompletedVideo && !isReplaceMode ? (
            isTrimMode ? (
              /* ============ TRIM MODE FOOTER ============ */
              <>
                {(trimStartMs > 0 || trimEndMs > 0) && (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => {
                      setTrimStartMs(0);
                      setTrimEndMs(0);
                      if (trimmerVideoRef.current) {
                        trimmerVideoRef.current.currentTime = 0;
                        setTrimmerCurrentTime(0);
                      }
                    }}
                  >
                    Reset
                  </Button>
                )}
                <div className="flex-1" />
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => {
                    // Cancel - reset trim values and exit trim mode
                    setTrimStartMs(shot?.trimStartMs || 0);
                    setTrimEndMs(shot?.trimEndMs || 0);
                    setIsTrimMode(false);
                    setIsTrimmerPlaying(false);
                  }}
                >
                  Cancel
                </Button>
                {/* Apply Trim button - This is the ONLY place where the trimmed video is created and saved */}
                <Button
                  type="button"
                  disabled={isTrimmingVideo || (trimStartMs === 0 && trimEndMs === 0)}
                  onClick={async () => {
                    if (!shot || !shot.video) return;

                    // If no trim values, just close
                    if (trimStartMs === 0 && trimEndMs === 0) {
                      setIsTrimMode(false);
                      return;
                    }

                    setIsTrimmingVideo(true);

                    try {
                      // Use original video if available, otherwise use current video
                      const sourceVideo = shot.originalVideo || shot.video;
                      const sourceVideoUrl = sourceVideo.url;
                      const sourceDuration = sourceVideo.durationMs || 8000;

                      // Create trimmed video file via API (this is the ONLY place this happens)
                      const response = await fetch("/api/video/trim", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({
                          projectId,
                          sceneId,
                          shotId: shot.id,
                          videoUrl: sourceVideoUrl,
                          trimStartMs,
                          trimEndMs,
                          durationMs: sourceDuration,
                        }),
                      });

                      const result = await response.json();

                      if (!result.success) {
                        throw new Error(result.error || "Failed to trim video");
                      }

                      // Calculate effective duration
                      const effectiveDuration = sourceDuration - trimStartMs - trimEndMs;

                      // Create updated shot with trimmed video and save it
                      const updatedShot: Shot = {
                        ...shot,
                        // Store original video if not already stored
                        originalVideo: shot.originalVideo || shot.video,
                        // Replace video with trimmed version
                        video: {
                          url: result.trimmedVideoUrl,
                          status: "completed" as const,
                          durationMs: effectiveDuration,
                          thumbnailUrl: result.thumbnailUrl || shot.video.thumbnailUrl,
                        },
                        // Store trim values for reference
                        trimStartMs,
                        trimEndMs,
                        updatedAt: new Date().toISOString(),
                      };

                      // Save the updated shot (this triggers the scene save in the parent component)
                      onSave(updatedShot);
                      setIsTrimMode(false);
                      toast.success("Video trimmed successfully");
                    } catch (error) {
                      console.error("[ShotEditorDialog] Trim error:", error);
                      toast.error(error instanceof Error ? error.message : "Failed to trim video");
                    } finally {
                      setIsTrimmingVideo(false);
                    }
                  }}
                >
                  {isTrimmingVideo ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Trimming...
                    </>
                  ) : (
                    "Apply Trim"
                  )}
                </Button>
              </>
            ) : isEffectsMode ? (
              /* ============ EFFECTS MODE FOOTER ============ */
              <>
                <div className="flex-1" />
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => {
                    // Cancel - reset fade values and exit effects mode
                    setFadeInType(shot?.fadeInType || "none");
                    setFadeOutType(shot?.fadeOutType || "none");
                    setFadeDurationMs(shot?.fadeDurationMs || 500);
                    setIsEffectsMode(false);
                  }}
                >
                  Cancel
                </Button>
                <Button
                  type="button"
                  onClick={() => {
                    if (!shot) return;
                    // Apply fade effects
                    const updatedShot: Shot = {
                      ...shot,
                      fadeInType: fadeInType !== "none" ? fadeInType : undefined,
                      fadeOutType: fadeOutType !== "none" ? fadeOutType : undefined,
                      fadeDurationMs:
                        fadeInType !== "none" || fadeOutType !== "none"
                          ? fadeDurationMs
                          : undefined,
                      updatedAt: new Date().toISOString(),
                    };
                    onSave(updatedShot);
                    setIsEffectsMode(false);
                    toast.success("Effects applied");
                  }}
                >
                  Apply Effects
                </Button>
              </>
            ) : (
              /* ============ NORMAL VIEW FOOTER ============ */
              <>
                {onDelete && (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={handleDelete}
                    className="text-sm text-destructive hover:text-destructive"
                  >
                    <X className="h-3.5 w-3.5 mr-1.5" />
                    Remove Shot
                  </Button>
                )}
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => setIsReplaceMode(true)}
                >
                  <Upload className="h-3.5 w-3.5 mr-1.5" />
                  Replace Shot
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    setIsTrimMode(true);
                    // Initialize with existing trim values if video was already trimmed
                    setTrimStartMs(shot?.trimStartMs || 0);
                    setTrimEndMs(shot?.trimEndMs || 0);
                    setTrimmerCurrentTime(shot?.trimStartMs || 0);
                  }}
                >
                  <Scissors className="h-3.5 w-3.5 mr-1.5" />
                  Trim Video
                </Button>
                {shot.audioMuted ? (
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => {
                      const updatedShot: Shot = {
                        ...shot,
                        audioMuted: false,
                        updatedAt: new Date().toISOString(),
                      };
                      onSave(updatedShot);
                      toast.success("Video audio restored");
                    }}
                  >
                    <VolumeX className="h-3.5 w-3.5 mr-1.5" />
                    Unmute Video
                  </Button>
                ) : (
                  onDetachAudio && (
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={handleDetachAudio}
                      disabled={isDetachingAudio}
                    >
                      {isDetachingAudio ? (
                        <Loader2 className="h-3.5 w-3.5 mr-1.5 animate-spin" />
                      ) : (
                        <Music className="h-3.5 w-3.5 mr-1.5" />
                      )}
                      {isDetachingAudio ? "Detaching..." : "Detach Audio"}
                    </Button>
                  )
                )}
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    setIsEffectsMode(true);
                    // Initialize with existing fade values
                    setFadeInType(shot?.fadeInType || "none");
                    setFadeOutType(shot?.fadeOutType || "none");
                    setFadeDurationMs(shot?.fadeDurationMs || 500);
                  }}
                >
                  <Sparkles className="h-3.5 w-3.5 mr-1.5" />
                  Effects
                </Button>
                <div className="flex-1" />
                <Button type="button" onClick={() => onOpenChange(false)}>
                  Close
                </Button>
              </>
            )
          ) : (
            <>
              {onDelete && (
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={handleDelete}
                  className="text-sm text-destructive hover:text-destructive"
                >
                  <X className="h-3.5 w-3.5 mr-1.5" />
                  Remove Shot
                </Button>
              )}
              <div className="flex-1" />
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  if (isReplaceMode) {
                    setIsReplaceMode(false);
                  } else {
                    onOpenChange(false);
                  }
                }}
              >
                Cancel
              </Button>
              {sourceType === "generated" && isVideoGenerationEnabled() && onGenerateVideo ? (
                <Button
                  type="button"
                  onClick={handleGenerate}
                  disabled={isGenerating || !prompt.trim()}
                >
                  {isGenerating ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Generating...
                    </>
                  ) : (
                    <>
                      <Sparkles className="h-4 w-4 mr-2" />
                      Generate Video
                    </>
                  )}
                </Button>
              ) : (
                <Button type="button" onClick={handleSave}>
                  Save Shot
                </Button>
              )}
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default ShotEditorDialog;
