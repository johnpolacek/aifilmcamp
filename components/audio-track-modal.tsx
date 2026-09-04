"use client";

import { Loader2, Music, Pause, Play, RotateCcw, Scissors, Upload, Volume2, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { AudioWaveform } from "@/components/audio-waveform";
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
import { Slider } from "@/components/ui/slider";
import type { AudioTrack, Shot } from "@/lib/scenes-client";
import { createNewAudioTrack } from "@/lib/scenes-client";
import { uploadFile } from "@/lib/upload-utils";

// ============================================================================
// TYPES
// ============================================================================

interface AudioTrackModalProps {
  track: AudioTrack | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (track: AudioTrack) => void;
  onDelete?: (trackId: string) => void;
  onCreateOverlap?: (audioTrack: AudioTrack) => void;
  shots?: Shot[];
  projectId: string;
  sceneId: string;
}

// ============================================================================
// MAIN COMPONENT
// ============================================================================

export function AudioTrackModal({
  track,
  open,
  onOpenChange,
  onSave,
  onDelete,
  onCreateOverlap,
  shots = [],
  projectId,
  sceneId,
}: AudioTrackModalProps) {
  // Local state
  const [sourceUrl, setSourceUrl] = useState(track?.sourceUrl || "");
  const [volume, setVolume] = useState(track?.volume || 1);
  const [isUploading, setIsUploading] = useState(false);
  const [audioDuration, setAudioDuration] = useState(track?.durationMs || 5000);

  // Trim mode state
  const [isTrimMode, setIsTrimMode] = useState(false);
  const [trimStartMs, setTrimStartMs] = useState<number>(track?.trimStartMs || 0);
  const [trimEndMs, setTrimEndMs] = useState<number>(track?.trimEndMs || 0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [isTrimmingAudio, setIsTrimmingAudio] = useState(false);

  const audioInputRef = useRef<HTMLInputElement>(null);
  const audioRef = useRef<HTMLAudioElement>(null);
  const trimmerAudioRef = useRef<HTMLAudioElement>(null);
  const waveformContainerRef = useRef<HTMLDivElement>(null);
  const [waveformWidth, setWaveformWidth] = useState(0);

  // Sync state when track changes or modal opens
  useEffect(() => {
    if (open) {
      setSourceUrl(track?.sourceUrl || "");
      setVolume(track?.volume || 1);
      setAudioDuration(track?.durationMs || 5000);
      // Reset trim mode when opening
      setIsTrimMode(false);
      setTrimStartMs(track?.trimStartMs || 0);
      setTrimEndMs(track?.trimEndMs || 0);
      setIsPlaying(false);
      setCurrentTime(0);
    }
  }, [open, track]);

  // Measure waveform container width when entering trim mode
  useEffect(() => {
    if (isTrimMode && waveformContainerRef.current) {
      const updateWidth = () => {
        if (waveformContainerRef.current) {
          setWaveformWidth(waveformContainerRef.current.offsetWidth);
        }
      };
      // Initial measurement after render
      requestAnimationFrame(updateWidth);
      // Also update on resize
      window.addEventListener("resize", updateWidth);
      return () => window.removeEventListener("resize", updateWidth);
    }
  }, [isTrimMode]);

  // Handle audio metadata loaded to get duration
  const handleLoadedMetadata = (e: React.SyntheticEvent<HTMLAudioElement>) => {
    const audio = e.currentTarget;
    const durationMs = Math.round(audio.duration * 1000);
    setAudioDuration(durationMs);
  };

  // Handle audio file upload - uses presigned URLs for large audio files
  const handleAudioUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploading(true);
    try {
      const result = await uploadFile(file, {
        projectId,
        sceneId,
        mediaType: "audio",
        onProgress: (percent) => {
          console.log(`[AudioTrackModal] Upload progress: ${percent}%`);
        },
      });

      if (result.success && result.url) {
        setSourceUrl(result.url);
        toast.success("Audio uploaded");
      } else {
        toast.error(result.error || "Failed to upload audio");
      }
    } catch (error) {
      console.error("[AudioTrackModal] Upload error:", JSON.stringify({ error }, null, 2));
      toast.error("Failed to upload audio");
    } finally {
      setIsUploading(false);
      if (e.target) {
        e.target.value = "";
      }
    }
  };

  // Handle save
  const handleSave = () => {
    if (!sourceUrl) {
      toast.error("Please upload an audio file");
      return;
    }

    const audioTrack: AudioTrack = track
      ? {
          ...track,
          name: "",
          sourceType: track.sourceType,
          sourceUrl,
          volume,
          durationMs: audioDuration,
          updatedAt: new Date().toISOString(),
        }
      : createNewAudioTrack("", "imported", sourceUrl, 0, audioDuration);

    // Set volume for new tracks
    if (!track) {
      audioTrack.volume = volume;
    }

    onSave(audioTrack);
    onOpenChange(false);
  };

  // Handle delete
  const handleDelete = () => {
    if (!track || !onDelete) return;
    onDelete(track.id);
    onOpenChange(false);
  };

  // Handle replacing audio file
  const handleReplaceAudio = () => {
    audioInputRef.current?.click();
  };

  // Handle trim apply
  const handleApplyTrim = async () => {
    if (!track || !track.sourceUrl) return;

    // If no trim values, just close trim mode
    if (trimStartMs === 0 && trimEndMs === 0) {
      setIsTrimMode(false);
      return;
    }

    setIsTrimmingAudio(true);

    try {
      // Use original audio if available, otherwise use current audio
      const sourceAudioUrl = track.originalSourceUrl || track.sourceUrl;
      const sourceDuration = track.originalDurationMs || audioDuration;

      const response = await fetch("/api/audio/trim", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          projectId,
          sceneId,
          trackId: track.id,
          audioUrl: sourceAudioUrl,
          trimStartMs,
          trimEndMs,
          durationMs: sourceDuration,
        }),
      });

      const result = await response.json();

      if (!result.success) {
        throw new Error(result.error || "Failed to trim audio");
      }

      // Calculate effective duration
      const effectiveDuration = sourceDuration - trimStartMs - trimEndMs;

      // Create updated track with trimmed audio
      const updatedTrack: AudioTrack = {
        ...track,
        // Store original audio if not already stored
        originalSourceUrl: track.originalSourceUrl || track.sourceUrl,
        originalDurationMs: track.originalDurationMs || audioDuration,
        // Replace audio with trimmed version
        sourceUrl: result.trimmedAudioUrl,
        durationMs: effectiveDuration,
        // Store trim values for reference
        trimStartMs,
        trimEndMs,
        updatedAt: new Date().toISOString(),
      };

      onSave(updatedTrack);
      setIsTrimMode(false);
      toast.success("Audio trimmed successfully");
    } catch (error) {
      console.error("[AudioTrackModal] Trim error:", JSON.stringify({ error }, null, 2));
      toast.error(error instanceof Error ? error.message : "Failed to trim audio");
    } finally {
      setIsTrimmingAudio(false);
    }
  };

  // Handle restore original
  const handleRestoreOriginal = () => {
    if (!track || !track.originalSourceUrl) return;

    const updatedTrack: AudioTrack = {
      ...track,
      sourceUrl: track.originalSourceUrl,
      durationMs: track.originalDurationMs || audioDuration,
      originalSourceUrl: undefined,
      originalDurationMs: undefined,
      trimStartMs: undefined,
      trimEndMs: undefined,
      updatedAt: new Date().toISOString(),
    };

    onSave(updatedTrack);
    setSourceUrl(track.originalSourceUrl);
    setAudioDuration(track.originalDurationMs || audioDuration);
    toast.success("Original audio restored");
  };

  const isNew = !track;
  const hasAudio = !!sourceUrl;
  const hasOriginal = track?.originalSourceUrl;

  // Get source duration for trimmer (use original if available)
  const sourceDuration = track?.originalSourceUrl
    ? track.originalDurationMs || audioDuration
    : audioDuration;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-2xl w-full">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {isTrimMode ? (
              <>
                <Scissors className="h-5 w-5 text-primary" />
                Trim Audio
              </>
            ) : (
              <>
                <Music className="h-5 w-5 text-primary" />
                {isNew ? "Add Audio Track" : "Edit Audio Track"}
              </>
            )}
          </DialogTitle>
          <DialogDescription>
            {isTrimMode
              ? "Drag the handles to set in and out points. Click play to preview the trimmed segment."
              : isNew
                ? "Import an audio file. Drag on the timeline to position it."
                : "Adjust audio settings. Drag on the timeline to reposition."}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6 py-4">
          {/* Audio Player & Replace */}
          <input
            ref={audioInputRef}
            type="file"
            accept="audio/mpeg,audio/mp3,audio/wav,audio/ogg,audio/aac,audio/x-m4a,audio/mp4,.m4a,.mp3,.wav"
            onChange={handleAudioUpload}
            className="hidden"
          />

          {isTrimMode && track ? (
            /* ============ TRIM MODE ============ */
            <div className="space-y-4">
              {/* Hidden audio element for playback */}
              <audio
                ref={trimmerAudioRef}
                src={track.originalSourceUrl || track.sourceUrl}
                onTimeUpdate={(e) => {
                  const audio = e.currentTarget;
                  setCurrentTime(audio.currentTime * 1000);
                  // Stop at trim end point
                  const trimEndPoint = sourceDuration - trimEndMs;
                  if (audio.currentTime * 1000 >= trimEndPoint) {
                    audio.pause();
                    setIsPlaying(false);
                  }
                }}
                onPlay={() => setIsPlaying(true)}
                onPause={() => setIsPlaying(false)}
                onEnded={() => setIsPlaying(false)}
                onLoadedMetadata={(e) => {
                  const audio = e.currentTarget;
                  // If we don't have original duration stored, calculate it
                  if (!track.originalDurationMs && !track.originalSourceUrl) {
                    const durationMs = Math.round(audio.duration * 1000);
                    setAudioDuration(durationMs);
                  }
                }}
              />

              {/* Play/Pause Button */}
              <div className="flex justify-center">
                <button
                  type="button"
                  onClick={() => {
                    const audio = trimmerAudioRef.current;
                    if (!audio) return;

                    if (isPlaying) {
                      audio.pause();
                    } else {
                      // Start from trim start if before it or at end
                      const trimEndPoint = sourceDuration - trimEndMs;
                      if (
                        audio.currentTime * 1000 < trimStartMs ||
                        audio.currentTime * 1000 >= trimEndPoint
                      ) {
                        audio.currentTime = trimStartMs / 1000;
                      }
                      audio.play();
                    }
                  }}
                  className="w-16 h-16 rounded-full bg-primary hover:bg-primary/90 flex items-center justify-center transition-colors"
                >
                  {isPlaying ? (
                    <Pause className="h-7 w-7 text-primary-foreground" />
                  ) : (
                    <Play className="h-7 w-7 text-primary-foreground ml-1" />
                  )}
                </button>
              </div>

              {/* Trim Timeline Bar with Waveform */}
              <div className="space-y-3">
                {/* Custom trim bar with waveform and draggable handles */}
                <div
                  ref={waveformContainerRef}
                  className="relative h-24 bg-muted border border-border rounded overflow-hidden"
                >
                  {/* Waveform visualization */}
                  {waveformWidth > 0 && (
                    <div className="absolute inset-0 flex items-center">
                      <AudioWaveform
                        audioUrl={track.originalSourceUrl || track.sourceUrl}
                        width={waveformWidth}
                        height={96}
                        color="hsl(var(--primary) / 0.6)"
                        backgroundColor="transparent"
                      />
                    </div>
                  )}

                  {/* Active region highlight (between handles) */}
                  <div
                    className="absolute inset-y-0 bg-primary/10 pointer-events-none"
                    style={{
                      left: `${(trimStartMs / sourceDuration) * 100}%`,
                      right: `${(trimEndMs / sourceDuration) * 100}%`,
                    }}
                  />

                  {/* Trimmed out regions (dark overlay) */}
                  <div
                    className="absolute inset-y-0 left-0 bg-black/60 pointer-events-none"
                    style={{ width: `${(trimStartMs / sourceDuration) * 100}%` }}
                  />
                  <div
                    className="absolute inset-y-0 right-0 bg-black/60 pointer-events-none"
                    style={{ width: `${(trimEndMs / sourceDuration) * 100}%` }}
                  />

                  {/* Current time playhead */}
                  <div
                    className="absolute top-0 bottom-0 w-0.5 bg-white z-20 pointer-events-none"
                    style={{
                      left: `${(currentTime / sourceDuration) * 100}%`,
                      display:
                        currentTime >= trimStartMs && currentTime <= sourceDuration - trimEndMs
                          ? "block"
                          : "none",
                    }}
                  />

                  {/* Left trim handle (In point) */}
                  <div
                    className="absolute top-0 bottom-0 w-2 bg-primary cursor-ew-resize z-30 hover:bg-primary/80 transition-colors"
                    style={{
                      left: `${(trimStartMs / sourceDuration) * 100}%`,
                      transform: "translateX(-50%)",
                    }}
                    onMouseDown={(e) => {
                      e.stopPropagation();
                      const startX = e.clientX;
                      const startValue = trimStartMs;
                      const containerWidth = waveformContainerRef.current?.offsetWidth || 1;

                      const handleMouseMove = (moveEvent: MouseEvent) => {
                        const deltaX = moveEvent.clientX - startX;
                        const deltaMs = (deltaX / containerWidth) * sourceDuration;
                        const newValue = Math.max(
                          0,
                          Math.min(sourceDuration - trimEndMs - 100, startValue + deltaMs)
                        );
                        setTrimStartMs(newValue);
                        if (trimmerAudioRef.current) {
                          trimmerAudioRef.current.currentTime = newValue / 1000;
                          setCurrentTime(newValue);
                        }
                      };

                      const handleMouseUp = () => {
                        document.removeEventListener("mousemove", handleMouseMove);
                        document.removeEventListener("mouseup", handleMouseUp);
                      };

                      document.addEventListener("mousemove", handleMouseMove);
                      document.addEventListener("mouseup", handleMouseUp);
                    }}
                  >
                    {/* Handle grip indicator */}
                    <div className="absolute inset-y-0 left-1/2 -translate-x-1/2 w-0.5 bg-white/50" />
                  </div>

                  {/* Right trim handle (Out point) */}
                  <div
                    className="absolute top-0 bottom-0 w-2 bg-primary cursor-ew-resize z-30 hover:bg-primary/80 transition-colors"
                    style={{
                      left: `${((sourceDuration - trimEndMs) / sourceDuration) * 100}%`,
                      transform: "translateX(-50%)",
                    }}
                    onMouseDown={(e) => {
                      e.stopPropagation();
                      const startX = e.clientX;
                      const startValue = trimEndMs;
                      const containerWidth = waveformContainerRef.current?.offsetWidth || 1;

                      const handleMouseMove = (moveEvent: MouseEvent) => {
                        const deltaX = moveEvent.clientX - startX;
                        const deltaMs = (deltaX / containerWidth) * sourceDuration;
                        const newValue = Math.max(
                          0,
                          Math.min(sourceDuration - trimStartMs - 100, startValue - deltaMs)
                        );
                        setTrimEndMs(newValue);
                        if (trimmerAudioRef.current) {
                          const outPoint = (sourceDuration - newValue) / 1000;
                          trimmerAudioRef.current.currentTime = outPoint;
                          setCurrentTime(sourceDuration - newValue);
                        }
                      };

                      const handleMouseUp = () => {
                        document.removeEventListener("mousemove", handleMouseMove);
                        document.removeEventListener("mouseup", handleMouseUp);
                      };

                      document.addEventListener("mousemove", handleMouseMove);
                      document.addEventListener("mouseup", handleMouseUp);
                    }}
                  >
                    {/* Handle grip indicator */}
                    <div className="absolute inset-y-0 left-1/2 -translate-x-1/2 w-0.5 bg-white/50" />
                  </div>
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
          ) : (
            /* ============ NORMAL MODE ============ */
            <>
              {sourceUrl ? (
                <div className="space-y-2">
                  <div>
                    <audio
                      ref={audioRef}
                      src={sourceUrl}
                      controls
                      className="w-full"
                      style={{ colorScheme: "dark" }}
                      onLoadedMetadata={handleLoadedMetadata}
                    />
                  </div>
                  <div className="flex items-center justify-between">
                    <button
                      type="button"
                      onClick={handleReplaceAudio}
                      disabled={isUploading}
                      className="text-xs text-muted-foreground hover:text-primary flex items-center gap-1 transition-colors"
                    >
                      {isUploading ? (
                        <Loader2 className="h-3 w-3 animate-spin" />
                      ) : (
                        <Upload className="h-3 w-3" />
                      )}
                      {isUploading ? "Uploading..." : "Replace audio"}
                    </button>
                    {/* Duration info */}
                    <span className="text-xs text-muted-foreground">
                      {hasOriginal ? (
                        <>
                          {(audioDuration / 1000).toFixed(1)}s
                          <span className="ml-1">
                            (original:{" "}
                            {((track?.originalDurationMs || audioDuration) / 1000).toFixed(1)}s)
                          </span>
                        </>
                      ) : (
                        <>{(audioDuration / 1000).toFixed(1)}s</>
                      )}
                    </span>
                  </div>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => audioInputRef.current?.click()}
                  disabled={isUploading}
                  className="w-full h-24 rounded-lg border-2 border-dashed border-muted-foreground/30 hover:border-primary/50 flex flex-col items-center justify-center gap-2 transition-colors"
                >
                  {isUploading ? (
                    <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
                  ) : (
                    <>
                      <Upload className="h-6 w-6 text-muted-foreground" />
                      <span className="text-sm text-muted-foreground">
                        Click to upload audio file
                      </span>
                    </>
                  )}
                </button>
              )}

              {/* Volume */}
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <Label className="flex items-center gap-2">
                    <Volume2 className="h-4 w-4" />
                    Volume
                  </Label>
                  <span className="text-sm text-muted-foreground">{Math.round(volume * 100)}%</span>
                </div>
                <Slider
                  value={[volume * 100]}
                  onValueChange={([v]) => setVolume(v / 100)}
                  max={100}
                  step={1}
                />
              </div>

              {/* Create Overlap - for detached audio */}
              {track?.sourceVideoShotId && onCreateOverlap && (
                <div className="space-y-2 pt-2 border-t border-border">
                  <Label>Video Overlap</Label>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => {
                      if (track && onCreateOverlap) {
                        onCreateOverlap(track);
                        toast.success("Video trimmed to create overlap");
                      }
                    }}
                    className="w-full"
                  >
                    <Scissors className="h-4 w-4 mr-2" />
                    Trim Video to Create Overlap
                  </Button>
                  <p className="text-xs text-muted-foreground">
                    Trim the source video so it starts when this audio starts, creating overlap with
                    previous shot.
                  </p>
                </div>
              )}
            </>
          )}
        </div>

        <DialogFooter className="flex-col sm:flex-row gap-2 items-center">
          {isTrimMode ? (
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
                    if (trimmerAudioRef.current) {
                      trimmerAudioRef.current.currentTime = 0;
                      setCurrentTime(0);
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
                  setTrimStartMs(track?.trimStartMs || 0);
                  setTrimEndMs(track?.trimEndMs || 0);
                  setIsTrimMode(false);
                  setIsPlaying(false);
                }}
              >
                Cancel
              </Button>
              <Button
                type="button"
                disabled={isTrimmingAudio || (trimStartMs === 0 && trimEndMs === 0)}
                onClick={handleApplyTrim}
              >
                {isTrimmingAudio ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Trimming...
                  </>
                ) : (
                  "Apply Trim"
                )}
              </Button>
            </>
          ) : (
            /* ============ NORMAL MODE FOOTER ============ */
            <>
              {onDelete && track && (
                <button
                  type="button"
                  onClick={handleDelete}
                  className="mr-2 flex items-center gap-1 sm:w-auto text-xs text-destructive hover:text-destructive"
                >
                  <X className="h-3 w-3" />
                  Delete
                </button>
              )}
              {/* Trim button - only show for existing tracks with audio */}
              {track && hasAudio && (
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    setIsTrimMode(true);
                    // Preserve existing trim values if they exist, otherwise reset to 0
                    setTrimStartMs(track.trimStartMs || 0);
                    setTrimEndMs(track.trimEndMs || 0);
                    setCurrentTime(0);
                  }}
                >
                  <Scissors className="h-3.5 w-3.5 mr-1.5" />
                  Trim
                </Button>
              )}
              {/* Restore original button */}
              {hasOriginal && (
                <Button type="button" variant="outline" size="sm" onClick={handleRestoreOriginal}>
                  <RotateCcw className="h-3 w-3 mr-1.5" />
                  Restore
                </Button>
              )}
              <div className="flex-1" />
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              <Button type="button" onClick={handleSave} disabled={!sourceUrl}>
                {isNew ? "Add Track" : "Save Changes"}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default AudioTrackModal;
