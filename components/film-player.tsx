"use client";

import { Pause, Play, SkipBack, SkipForward } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import type { Scene } from "@/lib/scenes-client";

interface VideoItem {
  sceneNumber: number;
  title: string;
  videoUrl: string;
  duration?: number;
}

interface FilmPlayerProps {
  scenes: Scene[];
  title?: string;
  autoPlay?: boolean;
}

export function FilmPlayer({ scenes, title, autoPlay = false }: FilmPlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentSceneIndex, setCurrentSceneIndex] = useState(0);
  const [playlist, setPlaylist] = useState<VideoItem[]>([]);

  // Build playlist from scenes
  useEffect(() => {
    const sortedScenes = [...scenes].sort((a, b) => a.sceneNumber - b.sceneNumber);

    const videos = sortedScenes
      .map((scene) => {
        const completedVideo = scene.generatedVideos?.find(
          (v) => v.status === "completed" && v.videoUrl
        );

        if (completedVideo) {
          return {
            sceneNumber: scene.sceneNumber,
            title: scene.title,
            videoUrl: completedVideo.videoUrl,
            duration: completedVideo.duration,
          };
        }
        return null;
      })
      .filter((v): v is NonNullable<typeof v> => v !== null);

    setPlaylist(videos);
  }, [scenes]);

  const currentVideo = playlist[currentSceneIndex];
  const hasVideos = playlist.length > 0;
  const hasNext = currentSceneIndex < playlist.length - 1;
  const hasPrev = currentSceneIndex > 0;

  const playVideo = useCallback(() => {
    if (videoRef.current) {
      videoRef.current.play();
      setIsPlaying(true);
    }
  }, []);

  const pauseVideo = useCallback(() => {
    if (videoRef.current) {
      videoRef.current.pause();
      setIsPlaying(false);
    }
  }, []);

  const togglePlay = useCallback(() => {
    if (isPlaying) {
      pauseVideo();
    } else {
      playVideo();
    }
  }, [isPlaying, pauseVideo, playVideo]);

  const goToNextScene = useCallback(() => {
    if (hasNext) {
      setCurrentSceneIndex((prev) => prev + 1);
    }
  }, [hasNext]);

  const goToPrevScene = useCallback(() => {
    if (hasPrev) {
      setCurrentSceneIndex((prev) => prev - 1);
    }
  }, [hasPrev]);

  const goToScene = useCallback(
    (index: number) => {
      if (index >= 0 && index < playlist.length) {
        setCurrentSceneIndex(index);
      }
    },
    [playlist.length]
  );

  // Auto-advance to next scene when current video ends
  const handleVideoEnded = useCallback(() => {
    if (hasNext) {
      goToNextScene();
      // Auto-play next video
      setTimeout(() => {
        playVideo();
      }, 100);
    } else {
      setIsPlaying(false);
    }
  }, [hasNext, goToNextScene, playVideo]);

  // Auto-play when video changes
  useEffect(() => {
    if (autoPlay && currentVideo && videoRef.current) {
      playVideo();
    }
  }, [autoPlay, currentVideo, playVideo]);

  if (!hasVideos) {
    return (
      <Card className="bg-muted/30 border-border">
        <CardContent className="p-8 text-center">
          <p className="text-muted-foreground">
            No completed videos available. Generate videos for your scenes to watch the film.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {/* Video Player */}
      <div className="relative aspect-video bg-black rounded-lg overflow-hidden">
        {currentVideo && (
          <video
            ref={videoRef}
            src={currentVideo.videoUrl}
            className="w-full h-full object-contain"
            onEnded={handleVideoEnded}
            onPlay={() => setIsPlaying(true)}
            onPause={() => setIsPlaying(false)}
          >
            <track kind="captions" />
          </video>
        )}

        {/* Play overlay (when paused) */}
        {!isPlaying && (
          <button
            type="button"
            onClick={playVideo}
            className="absolute inset-0 flex items-center justify-center bg-black/40 hover:bg-black/50 transition-colors"
          >
            <div className="w-20 h-20 rounded-full bg-white/90 flex items-center justify-center">
              <Play className="h-10 w-10 text-black ml-1" />
            </div>
          </button>
        )}
      </div>

      {/* Controls */}
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-2">
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={goToPrevScene}
            disabled={!hasPrev}
            className="bg-transparent"
          >
            <SkipBack className="h-4 w-4" />
          </Button>
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={togglePlay}
            className="bg-transparent"
          >
            {isPlaying ? <Pause className="h-4 w-4" /> : <Play className="h-4 w-4" />}
          </Button>
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={goToNextScene}
            disabled={!hasNext}
            className="bg-transparent"
          >
            <SkipForward className="h-4 w-4" />
          </Button>
        </div>

        <div className="text-sm text-muted-foreground">
          {currentVideo && (
            <span>
              Scene {currentVideo.sceneNumber}: {currentVideo.title}
              <span className="ml-2 text-xs">
                ({currentSceneIndex + 1} of {playlist.length})
              </span>
            </span>
          )}
        </div>
      </div>

      {/* Scene Timeline */}
      {playlist.length > 1 && (
        <div className="flex gap-1 overflow-x-auto pb-2">
          {playlist.map((video, index) => (
            <button
              key={video.sceneNumber}
              type="button"
              onClick={() => goToScene(index)}
              className={`shrink-0 px-3 py-2 rounded-md text-xs font-medium transition-colors ${
                index === currentSceneIndex
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted hover:bg-muted/80 text-muted-foreground"
              }`}
            >
              Scene {video.sceneNumber}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
