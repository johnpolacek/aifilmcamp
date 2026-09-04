"use client";

import { useEffect, useRef, useState } from "react";
import { getWaveformData, type WaveformData } from "@/lib/audio-waveform";

interface AudioWaveformProps {
  audioUrl: string;
  width: number;
  height: number;
  color?: string;
  backgroundColor?: string;
  className?: string;
}

/**
 * Audio waveform visualization component
 * Generates and displays waveform from an audio URL
 */
export function AudioWaveform({
  audioUrl,
  width,
  height,
  color = "rgba(255, 255, 255, 0.7)",
  backgroundColor = "transparent",
  className = "",
}: AudioWaveformProps) {
  const [waveform, setWaveform] = useState<WaveformData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const loadedUrlRef = useRef<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    // Don't attempt to load if URL is empty or invalid
    if (!audioUrl || audioUrl.trim() === "") {
      setIsLoading(false);
      return;
    }

    // Don't reload if we already have waveform data for this URL
    if (loadedUrlRef.current === audioUrl) {
      return;
    }

    async function loadWaveform() {
      setIsLoading(true);
      try {
        // Calculate number of samples based on width (roughly 2px per bar)
        // Use a stable number of samples to avoid re-rendering on small width changes
        const numSamples = Math.max(20, Math.min(200, Math.floor(Math.max(width, 100) / 3)));
        const data = await getWaveformData(audioUrl, numSamples);
        if (!cancelled) {
          setWaveform(data);
          loadedUrlRef.current = audioUrl;
          setIsLoading(false);
        }
      } catch (error) {
        console.error(
          "[AudioWaveform] Failed to load waveform:",
          error instanceof Error ? error.message : String(error)
        );
        if (!cancelled) {
          setIsLoading(false);
          // Set a fallback waveform so the UI doesn't break
          setWaveform({
            peaks: Array(50).fill(0.3),
            duration: 0,
          });
        }
      }
    }

    if (width > 0) {
      loadWaveform();
    }

    return () => {
      cancelled = true;
    };
  }, [audioUrl, width]); // Only reload if audioUrl changes

  if (width <= 0 || height <= 0) {
    return null;
  }

  if (isLoading || !waveform) {
    // Show placeholder bars while loading
    // Use deterministic pattern based on index to avoid hydration errors
    const numBars = Math.max(1, Math.floor(width / 4));
    return (
      <div
        className={`flex items-center justify-center gap-[1px] ${className}`}
        style={{ width, height, backgroundColor }}
      >
        {Array.from({ length: numBars }).map((_, i) => {
          // Use fixed integer heights to avoid floating point precision issues between server/client
          const patternIndex = i % 8;
          const heights = [35, 45, 50, 40, 55, 42, 38, 48];
          return (
            <div
              key={i}
              className="bg-white/30 rounded-sm animate-pulse"
              style={{
                width: 2,
                height: `${heights[patternIndex]}%`,
              }}
            />
          );
        })}
      </div>
    );
  }

  const barWidth = Math.max(1, width / waveform.peaks.length - 1);
  const gap = 1;

  // Convert color to a format that works in SVG fill
  // Handle CSS variable format like "hsl(var(--primary) / 0.6)"
  let fillColor = color;
  let fillOpacity = 1;

  if (color.includes("var(--primary)")) {
    // Extract opacity if present
    const opacityMatch = color.match(/\/\s*([\d.]+)\)/);
    if (opacityMatch) {
      fillOpacity = parseFloat(opacityMatch[1]);
    }
    // Use currentColor for CSS variable support
    fillColor = "currentColor";
  }

  return (
    <svg
      width={width}
      height={height}
      className={className}
      style={{
        backgroundColor,
        color: color.includes("var(--primary)") ? "hsl(var(--primary))" : undefined,
      }}
      viewBox={`0 0 ${width} ${height}`}
      preserveAspectRatio="none"
    >
      {waveform.peaks.map((peak, i) => {
        const barHeight = Math.max(2, peak * height * 0.9);
        const x = i * (barWidth + gap);
        const y = (height - barHeight) / 2;

        return (
          <rect
            key={i}
            x={x}
            y={y}
            width={barWidth}
            height={barHeight}
            fill={fillColor}
            fillOpacity={fillOpacity}
            rx={barWidth / 2}
          />
        );
      })}
    </svg>
  );
}

export default AudioWaveform;
