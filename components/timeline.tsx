"use client";

import { Loader2, Video } from "lucide-react";
import { useCallback, useMemo, useRef, useState } from "react";
import { AudioWaveform } from "@/components/audio-waveform";
import type { AudioTrack, Shot } from "@/lib/scenes-client";
import { getEffectiveDuration } from "@/lib/scenes-client";

// ============================================================================
// TYPES
// ============================================================================

interface TimelineProps {
  shots: Shot[];
  audioTracks: AudioTrack[];
  selectedShotId?: string;
  selectedAudioTrackId?: string;
  onShotClick: (shot: Shot) => void;
  onShotReorder: (shotIds: string[]) => void;
  onAudioTrackClick: (track: AudioTrack) => void;
  onAudioTrackMove?: (trackId: string, newStartTimeMs: number) => void;
}

// ============================================================================
// SHOT CARD COMPONENT
// ============================================================================

interface ShotCardProps {
  shot: Shot;
  isSelected: boolean;
  isDragging: boolean;
  onClick: () => void;
  onDragStart: () => void;
  onDragOver: (e: React.DragEvent) => void;
  onDrop: () => void;
  onDragEnd: () => void;
  widthPercent: number; // Width as percentage of timeline
}

function ShotCard({
  shot,
  isSelected,
  isDragging,
  onClick,
  onDragStart,
  onDragOver,
  onDrop,
  onDragEnd,
  widthPercent,
}: ShotCardProps) {
  // Get thumbnail URL - prioritize video thumbnail, then start frame image, then video URL
  const thumbnailUrl =
    shot.video?.thumbnailUrl && shot.video.thumbnailUrl.trim()
      ? shot.video.thumbnailUrl
      : shot.startFrameImage || null;
  const videoUrl = shot.video?.url || null;

  return (
    <div
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDrop={onDrop}
      onDragEnd={onDragEnd}
      onClick={onClick}
      className={`
        relative h-16 rounded-lg border-2 cursor-pointer transition-all overflow-hidden
        ${isSelected ? "border-primary shadow-lg ring-2 ring-primary/20" : "border-border hover:border-primary/50"}
        ${isDragging ? "opacity-50 scale-95" : ""}
      `}
      style={{
        flex: `${widthPercent} 1 0%`,
        minWidth: "20px",
      }}
    >
      {/* Thumbnail or placeholder */}
      {thumbnailUrl ? (
        <img
          src={thumbnailUrl}
          alt={`Shot ${shot.order + 1}`}
          className="w-full h-full object-cover"
          style={{ maxWidth: "100%", height: "100%", objectFit: "cover" }}
          onError={(e) => {
            if (videoUrl && e.currentTarget.parentElement) {
              const videoEl = document.createElement("video");
              videoEl.src = videoUrl;
              videoEl.className = "w-full h-full object-cover";
              videoEl.style.maxWidth = "100%";
              videoEl.style.height = "100%";
              videoEl.style.objectFit = "cover";
              videoEl.muted = true;
              videoEl.playsInline = true;
              e.currentTarget.parentElement.replaceChild(videoEl, e.currentTarget);
            }
          }}
        />
      ) : videoUrl ? (
        <video
          src={videoUrl}
          className="w-full h-full object-cover"
          style={{ maxWidth: "100%", height: "100%", objectFit: "cover" }}
          muted
          playsInline
        />
      ) : shot.video?.status === "processing" ? (
        <div className="w-full h-full bg-muted/50 flex flex-col items-center justify-center gap-1">
          <Loader2 className="h-5 w-5 text-primary animate-spin" />
          <span className="text-[10px] text-muted-foreground">Generating...</span>
        </div>
      ) : shot.video?.status === "failed" ? (
        <div className="w-full h-full bg-destructive/10 flex flex-col items-center justify-center gap-1">
          <Video className="h-5 w-5 text-destructive" />
          <span className="text-[10px] text-destructive">Failed</span>
        </div>
      ) : (
        <div className="w-full h-full bg-muted/50 flex items-center justify-center">
          <Video className="h-6 w-6 text-muted-foreground" />
        </div>
      )}

      {/* Audio indicator line - show at bottom for completed videos with audio */}
      {shot.video?.status === "completed" && !shot.audioMuted && (
        <div className="absolute bottom-0 left-0 right-0 h-1 bg-emerald-600" title="Has audio" />
      )}
    </div>
  );
}

// ============================================================================
// AUDIO TRACK ROW COMPONENT
// ============================================================================

interface AudioTrackRowProps {
  track: AudioTrack;
  isSelected: boolean;
  isDragging: boolean;
  onClick: () => void;
  onDragStart: () => void;
  onDragOver: (e: React.DragEvent) => void;
  onDragEnd: () => void;
  onMouseDown: (e: React.MouseEvent) => void;
  leftPercent: number;
  widthPercent: number;
}

function AudioTrackRow({
  track,
  isSelected,
  isDragging,
  onClick,
  onDragStart,
  onDragOver,
  onDragEnd,
  onMouseDown,
  leftPercent,
  widthPercent,
}: AudioTrackRowProps) {
  return (
    <div
      draggable
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDragEnd={onDragEnd}
      onMouseDown={onMouseDown}
      className={`absolute h-6 rounded-md cursor-move transition-all overflow-hidden border ${
        isSelected
          ? "border-primary ring-2 ring-primary/30 bg-primary/5"
          : "border-border bg-muted/20 hover:border-primary/50"
      } ${track.muted ? "opacity-40" : ""} ${isDragging ? "opacity-50 scale-95" : ""}`}
      style={{
        left: `${leftPercent}%`,
        width: `${Math.max(0.5, widthPercent)}%`,
        minWidth: "8px",
      }}
      onClick={onClick}
    >
      {/* Waveform visualization */}
      <div className="absolute inset-0">
        <AudioWaveform
          audioUrl={track.sourceUrl}
          width={200} // Fixed width for waveform sampling
          height={24}
          color={isSelected ? "hsl(var(--primary))" : "hsl(var(--primary) / 0.5)"}
          className="w-full h-full"
        />
      </div>
    </div>
  );
}

// ============================================================================
// MAIN TIMELINE COMPONENT
// ============================================================================

export default function Timeline({
  shots,
  audioTracks,
  selectedShotId,
  selectedAudioTrackId,
  onShotClick,
  onShotReorder,
  onAudioTrackClick,
  onAudioTrackMove,
}: TimelineProps) {
  const [draggedShotId, setDraggedShotId] = useState<string | null>(null);
  const [draggedAudioTrackId, setDraggedAudioTrackId] = useState<string | null>(null);
  const [draggedAudioTrackPosition, setDraggedAudioTrackPosition] = useState<number | null>(null); // Track dragged position for visual updates
  const timelineRef = useRef<HTMLDivElement>(null);
  const audioTrackDraggedRef = useRef(false); // Track if drag actually occurred

  // Calculate total timeline duration using effective (trimmed) durations
  const totalDurationMs = useMemo(() => {
    return shots.reduce((acc, shot) => {
      return acc + getEffectiveDuration(shot);
    }, 0);
  }, [shots]);

  // Calculate shot positions with durations for proportional layout
  const shotPositions = useMemo(() => {
    const sortedShots = [...shots].sort((a, b) => a.order - b.order);
    let currentTimeMs = 0;
    return sortedShots.map((shot) => {
      const startTimeMs = currentTimeMs;
      const effectiveDurationMs = getEffectiveDuration(shot);
      const widthPercent = totalDurationMs > 0 ? (effectiveDurationMs / totalDurationMs) * 100 : 0;
      currentTimeMs += effectiveDurationMs;
      return {
        shot,
        startTimeMs,
        durationMs: effectiveDurationMs,
        widthPercent,
      };
    });
  }, [shots, totalDurationMs]);

  // Handle shot reordering
  const handleDragStart = useCallback((shotId: string) => {
    setDraggedShotId(shotId);
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  }, []);

  const handleDrop = useCallback(
    (targetShotId: string) => {
      if (!draggedShotId || draggedShotId === targetShotId) return;

      const draggedIndex = shots.findIndex((s) => s.id === draggedShotId);
      const targetIndex = shots.findIndex((s) => s.id === targetShotId);

      if (draggedIndex === -1 || targetIndex === -1) return;

      const newOrder = shots.map((s) => s.id);
      newOrder.splice(draggedIndex, 1);
      newOrder.splice(targetIndex, 0, draggedShotId);

      onShotReorder(newOrder);
      setDraggedShotId(null);
    },
    [draggedShotId, shots, onShotReorder]
  );

  const handleDragEnd = useCallback(() => {
    setDraggedShotId(null);
  }, []);

  // Handle audio track dragging
  // NOTE: During dragging, we only update local visual state. The position is NOT saved until drag ends.
  const handleAudioTrackMouseDown = useCallback(
    (trackId: string, e: React.MouseEvent) => {
      e.preventDefault();
      e.stopPropagation();
      const track = audioTracks.find((t) => t.id === trackId);
      if (!track || !onAudioTrackMove) return;

      const trackRect = e.currentTarget.getBoundingClientRect();
      const offsetX = e.clientX - trackRect.left;
      const startX = e.clientX;
      setDraggedAudioTrackId(trackId);
      audioTrackDraggedRef.current = false; // Reset drag flag

      // Store the final position to save when drag ends
      let finalStartTimeMs = track.startTimeMs;

      const handleMouseMove = (moveEvent: MouseEvent) => {
        // Only consider it a drag if moved more than 3 pixels
        if (Math.abs(moveEvent.clientX - startX) > 3) {
          audioTrackDraggedRef.current = true;
        }
        if (!timelineRef.current) return;
        const timelineRect = timelineRef.current.getBoundingClientRect();
        const timelineWidth = timelineRect.width;
        const newX = moveEvent.clientX - timelineRect.left - offsetX;
        // Convert pixel position to percentage, then to milliseconds
        const newPercent = Math.max(0, Math.min(100, (newX / timelineWidth) * 100));
        const newStartTimeMs = (newPercent / 100) * totalDurationMs;

        // Store the final position but don't save yet - only update visual state during dragging
        finalStartTimeMs = newStartTimeMs;

        // Update local state for visual feedback during dragging (no API calls)
        setDraggedAudioTrackPosition(newStartTimeMs);
      };

      const handleMouseUp = () => {
        document.removeEventListener("mousemove", handleMouseMove);
        document.removeEventListener("mouseup", handleMouseUp);

        // Only save the position when drag ends (not during dragging)
        if (audioTrackDraggedRef.current && finalStartTimeMs !== track.startTimeMs) {
          onAudioTrackMove(trackId, finalStartTimeMs);
        }

        // Clear dragged position state
        setDraggedAudioTrackPosition(null);
        setDraggedAudioTrackId(null);
      };

      document.addEventListener("mousemove", handleMouseMove);
      document.addEventListener("mouseup", handleMouseUp);
    },
    [audioTracks, totalDurationMs, onAudioTrackMove]
  );

  const handleAudioTrackDragStart = useCallback((trackId: string) => {
    setDraggedAudioTrackId(trackId);
  }, []);

  const handleAudioTrackDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  }, []);

  const handleAudioTrackDragEnd = useCallback(() => {
    setDraggedAudioTrackId(null);
  }, []);

  // Time markers for ruler
  const timeMarkers = useMemo(() => {
    const markers = [];
    const totalSeconds = Math.ceil(totalDurationMs / 1000) || 10;
    for (let i = 0; i <= totalSeconds; i += 5) {
      markers.push(i);
    }
    return markers;
  }, [totalDurationMs]);

  return (
    <div className="w-full relative">
      {/* Shot boundary guide lines */}
      {shotPositions.map(({ shot, startTimeMs, durationMs }) => {
        const startPercent = totalDurationMs > 0 ? (startTimeMs / totalDurationMs) * 100 : 0;
        const endPercent =
          totalDurationMs > 0 ? ((startTimeMs + durationMs) / totalDurationMs) * 100 : 0;
        return (
          <div key={`shot-boundaries-${shot.id}`} className="contents">
            {/* Start boundary */}
            <div
              className="absolute top-0 bottom-0 w-px bg-primary/30 pointer-events-none z-10"
              style={{ left: `${startPercent}%` }}
            />
            {/* End boundary */}
            <div
              className="absolute top-0 bottom-0 w-px bg-primary/20 pointer-events-none z-10"
              style={{ left: `${endPercent}%` }}
            />
          </div>
        );
      })}

      {/* Time marker guide lines (every 1 second) */}
      {Array.from({ length: Math.ceil(totalDurationMs / 1000) + 1 }).map((_, i) => {
        const seconds = i;
        const percent = totalDurationMs > 0 ? ((seconds * 1000) / totalDurationMs) * 100 : 0;
        return (
          <div
            key={`time-guide-${seconds}`}
            className="absolute top-0 bottom-0 w-px bg-border/50 pointer-events-none z-0"
            style={{ left: `${percent}%` }}
          />
        );
      })}

      {/* Timeline Ruler */}
      <div className="border-b border-border px-2 py-1 w-full relative z-20">
        <div className="relative w-full" style={{ height: "24px" }}>
          {timeMarkers.map((seconds) => {
            const leftPercent =
              totalDurationMs > 0 ? ((seconds * 1000) / totalDurationMs) * 100 : 0;
            return (
              <div
                key={seconds}
                className="absolute top-0 bottom-0 flex flex-col items-center"
                style={{ left: `${leftPercent}%`, transform: "translateX(-50%)" }}
              >
                <div className="w-px h-2 bg-border" />
                <span className="text-[10px] text-muted-foreground mt-0.5">{seconds}s</span>
              </div>
            );
          })}
        </div>
      </div>

      {/* Shots Row */}
      <div className="border-b border-border px-2 py-2 w-full relative z-20">
        <div ref={timelineRef} className="flex w-full" style={{ height: "64px" }}>
          {shotPositions.map(({ shot, widthPercent }) => (
            <ShotCard
              key={shot.id}
              shot={shot}
              isSelected={selectedShotId === shot.id}
              isDragging={draggedShotId === shot.id}
              onClick={() => onShotClick(shot)}
              onDragStart={() => handleDragStart(shot.id)}
              onDragOver={handleDragOver}
              onDrop={() => handleDrop(shot.id)}
              onDragEnd={handleDragEnd}
              widthPercent={widthPercent}
            />
          ))}
        </div>
      </div>

      {/* Audio Tracks */}
      <div className="px-1 py-1 space-y-1 w-full relative z-20">
        {audioTracks.map((track) => {
          // Use dragged position for visual feedback during dragging, otherwise use actual position
          const displayStartTimeMs =
            draggedAudioTrackId === track.id && draggedAudioTrackPosition !== null
              ? draggedAudioTrackPosition
              : track.startTimeMs;
          const leftPercent =
            totalDurationMs > 0 ? (displayStartTimeMs / totalDurationMs) * 100 : 0;
          const widthPercent =
            totalDurationMs > 0 ? (track.durationMs / totalDurationMs) * 100 : 10;
          return (
            <div key={track.id} className="relative w-full h-6">
              <AudioTrackRow
                track={track}
                isSelected={selectedAudioTrackId === track.id}
                isDragging={draggedAudioTrackId === track.id}
                onClick={() => {
                  // Only open modal if this wasn't a drag
                  if (!audioTrackDraggedRef.current) {
                    onAudioTrackClick(track);
                  }
                  audioTrackDraggedRef.current = false; // Reset for next interaction
                }}
                onDragStart={() => handleAudioTrackDragStart(track.id)}
                onDragOver={handleAudioTrackDragOver}
                onDragEnd={handleAudioTrackDragEnd}
                onMouseDown={(e) => handleAudioTrackMouseDown(track.id, e)}
                leftPercent={leftPercent}
                widthPercent={widthPercent}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
}

export type { TimelineProps };
export { AudioTrackRow, ShotCard };
