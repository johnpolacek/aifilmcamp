"use client";

import { Pause, Play, SkipBack, SkipForward, Volume2, VolumeX } from "lucide-react";
import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from "react";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";
import type { AudioTrack, Shot } from "@/lib/scenes-client";
import { cn } from "@/lib/utils";

interface ScenePlayerProps {
  shots: Shot[];
  audioTracks?: AudioTrack[];
  masterVolume?: number; // Master volume control (0.0 to 2.0, default: 1.0)
  className?: string;
}

export interface ScenePlayerHandle {
  pause: () => void;
}

export const ScenePlayer = forwardRef<ScenePlayerHandle, ScenePlayerProps>(function ScenePlayer(
  { shots, audioTracks = [], masterVolume = 1.0, className },
  ref
) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const preloadedVideoRefs = useRef<Map<string, HTMLVideoElement>>(new Map());
  const preloadedShotsRef = useRef<Set<string>>(new Set());
  const audioRefs = useRef<Map<string, HTMLAudioElement>>(new Map());
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentShotIndex, setCurrentShotIndex] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [isMuted, setIsMuted] = useState(false);
  const [volume, setVolume] = useState(1);
  const [videoError, setVideoError] = useState<string | null>(null);

  // Track actual video durations as they load
  const [actualDurations, setActualDurations] = useState<Map<string, number>>(new Map());

  // Filter to only completed shots with videos that have a URL
  const playableShots = useMemo(() => {
    const filtered = shots
      .filter((shot) => shot.video?.status === "completed" && shot.video?.url)
      .sort((a, b) => a.order - b.order);

    return filtered;
  }, [shots]);

  // Calculate timeline positions for shots (using effective durations after trimming)
  const shotTimeline = useMemo(() => {
    let currentTimeMs = 0;
    return playableShots.map((shot) => {
      const startTime = currentTimeMs;

      // Check if video has been trimmed (originalVideo exists)
      // If so, the current video.durationMs IS the effective duration (trim already baked in)
      const hasBeenTrimmed = !!shot.originalVideo;

      // Get base duration - use original video duration if trimmed, otherwise current video
      const baseDuration = hasBeenTrimmed
        ? shot.originalVideo?.durationMs || 8000
        : actualDurations.get(shot.id) || shot.video?.durationMs || 5000;

      // Get trim values - only apply if video hasn't been trimmed yet
      const trimStartMs = hasBeenTrimmed ? 0 : shot.trimStartMs || 0;
      const trimEndMs = hasBeenTrimmed ? 0 : shot.trimEndMs || 0;

      // Calculate effective duration
      // If trimmed, use current video duration directly (trim is baked in)
      // If not trimmed, subtract trim values from base duration
      const effectiveDuration = hasBeenTrimmed
        ? shot.video?.durationMs || 5000
        : Math.max(0, baseDuration - trimStartMs - trimEndMs);

      currentTimeMs += effectiveDuration;
      return {
        shot,
        startTimeMs: startTime,
        endTimeMs: currentTimeMs,
        durationMs: effectiveDuration,
        trimStartMs, // Store for playback offset (0 if already trimmed)
        trimEndMs, // Store for end detection (0 if already trimmed)
        baseDuration, // Video duration to use for playback (original if trimmed, current otherwise)
      };
    });
  }, [playableShots, actualDurations]);

  // Total duration of all shots (using actual durations if available)
  const totalDurationMs = useMemo(() => {
    return shotTimeline.reduce((acc, item) => {
      const actualDuration = actualDurations.get(item.shot.id);
      return acc + (actualDuration || item.durationMs);
    }, 0);
  }, [shotTimeline, actualDurations]);

  const currentShot = playableShots[currentShotIndex];
  const hasVideos = playableShots.length > 0;
  const hasNext = currentShotIndex < playableShots.length - 1;
  const hasPrev = currentShotIndex > 0;

  // Calculate global time from current shot and video time (accounting for trim)
  const globalTimeMs = useMemo(() => {
    if (shotTimeline.length === 0) return 0;
    const shotInfo = shotTimeline[currentShotIndex];
    if (!shotInfo) return 0;
    // currentTime is in video time, subtract trim start to get effective position
    const effectiveVideoTime = Math.max(0, currentTime * 1000 - shotInfo.trimStartMs);
    return shotInfo.startTimeMs + effectiveVideoTime;
  }, [shotTimeline, currentShotIndex, currentTime]);

  // Sync audio tracks with video playback
  const syncAudioTracks = useCallback(
    (globalTime: number, playing: boolean) => {
      audioTracks.forEach((track) => {
        const audioEl = audioRefs.current.get(track.id);
        if (!audioEl) return;

        const trackStartMs = track.startTimeMs;
        const trackEndMs = track.startTimeMs + track.durationMs;

        // If originalSourceUrl exists, the audio file is already trimmed, so don't apply trimStartMs again
        // trimStartMs/trimEndMs are just metadata about what was trimmed
        const hasBeenTrimmed = !!track.originalSourceUrl;
        const trimStartMs = hasBeenTrimmed ? 0 : track.trimStartMs || 0;

        // Check if this track should be playing at the current time
        if (globalTime >= trackStartMs && globalTime < trackEndMs) {
          const trackTime = (globalTime - trackStartMs + trimStartMs) / 1000;

          // Only update if significantly different to avoid constant seeking
          if (Math.abs(audioEl.currentTime - trackTime) > 0.1) {
            audioEl.currentTime = trackTime;
          }

          audioEl.volume = track.muted ? 0 : track.volume * volume * masterVolume;
          audioEl.muted = isMuted || track.muted;

          if (playing && audioEl.paused) {
            audioEl.play().catch(() => {});
          } else if (!playing && !audioEl.paused) {
            audioEl.pause();
          }
        } else {
          // Track not in range, pause it
          if (!audioEl.paused) {
            audioEl.pause();
          }
        }
      });
    },
    [audioTracks, isMuted, volume, masterVolume]
  );

  // Get the currently active video element
  const getActiveVideo = useCallback(() => {
    return videoRef.current;
  }, []);

  // Play video - does NOT set muted state (that's handled by goToNextShot/goToShot)
  // This avoids race conditions where playVideo's stale closure would override the correct muted state
  const playVideo = useCallback(() => {
    const video = getActiveVideo();
    if (video) {
      // Don't set muted here - it's already set correctly by goToNextShot/goToShot
      // Setting it here would use stale currentShotIndex and potentially unmute a muted shot
      video.play();
      setIsPlaying(true);
      syncAudioTracks(globalTimeMs, true);
    }
  }, [globalTimeMs, syncAudioTracks, getActiveVideo]);

  // Pause video
  const pauseVideo = useCallback(() => {
    const video = getActiveVideo();
    if (video) {
      video.pause();
      setIsPlaying(false);
      syncAudioTracks(globalTimeMs, false);
    }
  }, [globalTimeMs, syncAudioTracks, getActiveVideo]);

  // Expose pause method to parent components
  useImperativeHandle(
    ref,
    () => ({
      pause: pauseVideo,
    }),
    [pauseVideo]
  );

  // Toggle play/pause
  const togglePlay = useCallback(() => {
    if (isPlaying) {
      pauseVideo();
    } else {
      // Set muted state before playing (playVideo doesn't set it to avoid race conditions)
      const video = getActiveVideo();
      const currentShot = playableShots[currentShotIndex];
      if (video) {
        video.muted = isMuted || currentShot?.audioMuted || false;
      }
      playVideo();
    }
  }, [isPlaying, pauseVideo, playVideo, getActiveVideo, playableShots, currentShotIndex, isMuted]);

  // Go to next shot
  const goToNextShot = useCallback(() => {
    if (hasNext) {
      const nextIndex = currentShotIndex + 1;
      const nextShotInfo = shotTimeline[nextIndex];
      const nextShot = playableShots[nextIndex];
      const currentVideo = videoRef.current;
      const wasPlaying = !currentVideo?.paused;

      // If next video is preloaded and ready, copy its src to current video for instant switch
      if (nextShot?.video?.url && preloadedShotsRef.current.has(nextShot.id)) {
        const preloadedVideo = preloadedVideoRefs.current.get(nextShot.id);

        if (preloadedVideo && preloadedVideo.readyState >= 2 && currentVideo) {
          // HAVE_CURRENT_DATA or higher
          // Copy preloaded video's src to current video - this is instant since it's already loaded
          const nextVideoSrc = preloadedVideo.src;
          const nextVideoCurrentTime = nextShotInfo.trimStartMs / 1000;

          // If src is different, update it (should be instant since browser has it cached)
          if (currentVideo.src !== nextVideoSrc) {
            currentVideo.src = nextVideoSrc;
          }

          // Set position and state
          currentVideo.currentTime = nextVideoCurrentTime;
          currentVideo.volume = volume;
          currentVideo.muted = isMuted || nextShot.audioMuted || false;

          // Update state
          setCurrentShotIndex(nextIndex);
          setVideoError(null);

          // Continue playing if it was playing
          if (wasPlaying) {
            // Small delay to ensure src is applied
            setTimeout(() => {
              if (currentVideo && currentVideo.src === nextVideoSrc) {
                currentVideo.play().catch(() => {});
              }
            }, 10);
          }

          return;
        }
      }

      // Fallback: change src if preload didn't work
      setCurrentShotIndex(nextIndex);
      setVideoError(null);

      if (nextShotInfo && currentVideo) {
        // Ensure muted state is set for the next shot
        currentVideo.muted = isMuted || nextShot?.audioMuted || false;

        setTimeout(() => {
          if (videoRef.current) {
            videoRef.current.currentTime = nextShotInfo.trimStartMs / 1000;
          }
        }, 50);
      }
    }
  }, [hasNext, currentShotIndex, shotTimeline, playableShots, volume, isMuted]);

  // Go to previous shot
  const goToPrevShot = useCallback(() => {
    const currentShotInfo = shotTimeline[currentShotIndex];
    const effectiveCurrentTime = currentShotInfo
      ? (currentTime * 1000 - currentShotInfo.trimStartMs) / 1000
      : currentTime;

    // If we're more than 2 seconds into current shot, restart it at trim start
    if (effectiveCurrentTime > 2) {
      if (videoRef.current && currentShotInfo) {
        videoRef.current.currentTime = currentShotInfo.trimStartMs / 1000;
        setCurrentTime(currentShotInfo.trimStartMs / 1000);
      }
    } else if (hasPrev) {
      const prevIndex = currentShotIndex - 1;
      const prevShot = playableShots[prevIndex];
      const prevShotInfo = shotTimeline[prevIndex];
      const currentVideo = videoRef.current;
      const wasPlaying = !currentVideo?.paused;

      // If prev video is preloaded and ready, use it for instant switch
      if (prevShot?.video?.url && preloadedShotsRef.current.has(prevShot.id)) {
        const preloadedVideo = preloadedVideoRefs.current.get(prevShot.id);

        if (preloadedVideo && preloadedVideo.readyState >= 2 && currentVideo) {
          const prevVideoSrc = preloadedVideo.src;
          const prevVideoCurrentTime = prevShotInfo.trimStartMs / 1000;

          // Copy preloaded video's src to current video
          if (currentVideo.src !== prevVideoSrc) {
            currentVideo.src = prevVideoSrc;
          }

          currentVideo.currentTime = prevVideoCurrentTime;
          currentVideo.volume = volume;
          currentVideo.muted = isMuted || prevShot.audioMuted || false;

          setCurrentShotIndex(prevIndex);
          setVideoError(null);

          if (wasPlaying) {
            setTimeout(() => {
              if (currentVideo && currentVideo.src === prevVideoSrc) {
                currentVideo.play().catch(() => {});
              }
            }, 10);
          }

          return;
        }
      }

      // Fallback: change src if preload didn't work
      setCurrentShotIndex(prevIndex);
      setVideoError(null);
      if (prevShotInfo && currentVideo) {
        setTimeout(() => {
          if (videoRef.current) {
            videoRef.current.currentTime = prevShotInfo.trimStartMs / 1000;
          }
        }, 50);
      }
    }
  }, [hasPrev, currentTime, currentShotIndex, shotTimeline, playableShots, volume, isMuted]);

  // Go to specific shot
  const _goToShot = useCallback(
    (index: number) => {
      if (index >= 0 && index < playableShots.length) {
        const targetShot = playableShots[index];
        const targetShotInfo = shotTimeline[index];
        const currentVideo = videoRef.current;
        const wasPlaying = !currentVideo?.paused;

        // If target video is preloaded and ready, use it for instant switch
        if (targetShot?.video?.url && preloadedShotsRef.current.has(targetShot.id)) {
          const preloadedVideo = preloadedVideoRefs.current.get(targetShot.id);

          if (preloadedVideo && preloadedVideo.readyState >= 2 && currentVideo) {
            const targetVideoSrc = preloadedVideo.src;
            const targetVideoCurrentTime = targetShotInfo.trimStartMs / 1000;

            // Copy preloaded video's src to current video
            if (currentVideo.src !== targetVideoSrc) {
              currentVideo.src = targetVideoSrc;
            }

            currentVideo.currentTime = targetVideoCurrentTime;
            currentVideo.volume = volume;
            currentVideo.muted = isMuted || targetShot.audioMuted || false;

            setCurrentShotIndex(index);
            setVideoError(null);

            if (wasPlaying) {
              setTimeout(() => {
                if (currentVideo && currentVideo.src === targetVideoSrc) {
                  currentVideo.play().catch(() => {});
                }
              }, 10);
            }

            return;
          }
        }

        // Fallback: change src if preload didn't work
        setCurrentShotIndex(index);
        setVideoError(null);
        setTimeout(() => {
          const video = getActiveVideo();
          if (video && targetShotInfo) {
            video.currentTime = targetShotInfo.trimStartMs / 1000;
            if (isPlaying) {
              video.play();
            }
          }
        }, 50);
      }
    },
    [playableShots, isPlaying, shotTimeline, getActiveVideo, volume, isMuted]
  );

  // Handle video ended
  const handleVideoEnded = useCallback(() => {
    if (hasNext) {
      goToNextShot();
      // Auto-play next shot
      setTimeout(() => {
        playVideo();
      }, 50);
    } else {
      // End of scene
      setIsPlaying(false);
      syncAudioTracks(totalDurationMs, false);
    }
  }, [hasNext, goToNextShot, playVideo, syncAudioTracks, totalDurationMs]);

  // Handle video time update (with trim end detection)
  const handleTimeUpdate = useCallback(() => {
    const video = getActiveVideo();
    if (video) {
      setCurrentTime(video.currentTime);

      // Check if we've reached the trim end point
      const shotInfo = shotTimeline[currentShotIndex];
      if (shotInfo) {
        const trimEndPoint = (shotInfo.baseDuration - shotInfo.trimEndMs) / 1000;
        if (video.currentTime >= trimEndPoint - 0.05) {
          // Small threshold for timing accuracy
          // Manually trigger video ended behavior
          video.pause();
          if (hasNext) {
            goToNextShot();
            setTimeout(() => {
              playVideo();
            }, 50);
          } else {
            setIsPlaying(false);
            syncAudioTracks(totalDurationMs, false);
          }
        }
      }
    }
  }, [
    shotTimeline,
    currentShotIndex,
    hasNext,
    goToNextShot,
    playVideo,
    syncAudioTracks,
    totalDurationMs,
    getActiveVideo,
  ]);

  // Preload all shot videos for smooth transitions
  useEffect(() => {
    playableShots.forEach((shot) => {
      if (shot.video?.url && !preloadedShotsRef.current.has(shot.id)) {
        const preloadedVideo = preloadedVideoRefs.current.get(shot.id);
        if (preloadedVideo) {
          preloadedVideo.src = shot.video.url;
          preloadedVideo.load();
          preloadedShotsRef.current.add(shot.id);
        }
      }
    });
  }, [playableShots]);

  // Sync audio when global time changes
  useEffect(() => {
    syncAudioTracks(globalTimeMs, isPlaying);
  }, [globalTimeMs, isPlaying, syncAudioTracks]);

  // Handle seeking on the progress bar
  const handleSeek = useCallback(
    (value: number[]) => {
      const seekTimeMs = value[0];

      // Find which shot this time belongs to
      const targetShotItem = shotTimeline.find(
        (item) => seekTimeMs >= item.startTimeMs && seekTimeMs < item.endTimeMs
      );

      if (targetShotItem) {
        const shotIndex = playableShots.findIndex((s) => s.id === targetShotItem.shot.id);
        const targetShot = playableShots[shotIndex];
        // Add trim start offset to get actual video time
        const videoTime =
          (seekTimeMs - targetShotItem.startTimeMs + targetShotItem.trimStartMs) / 1000;

        if (shotIndex !== currentShotIndex) {
          const currentVideo = videoRef.current;
          const wasPlaying = !currentVideo?.paused;

          // If target video is preloaded and ready, use it for instant switch
          if (targetShot?.video?.url && preloadedShotsRef.current.has(targetShot.id)) {
            const preloadedVideo = preloadedVideoRefs.current.get(targetShot.id);

            if (preloadedVideo && preloadedVideo.readyState >= 2 && currentVideo) {
              const targetVideoSrc = preloadedVideo.src;

              // Copy preloaded video's src to current video
              if (currentVideo.src !== targetVideoSrc) {
                currentVideo.src = targetVideoSrc;
              }

              currentVideo.currentTime = videoTime;
              currentVideo.volume = volume;
              currentVideo.muted = isMuted || targetShot.audioMuted || false;

              setCurrentShotIndex(shotIndex);
              setVideoError(null);

              if (wasPlaying) {
                setTimeout(() => {
                  if (currentVideo && currentVideo.src === targetVideoSrc) {
                    currentVideo.play().catch(() => {});
                  }
                }, 10);
              }

              return;
            }
          }

          // Fallback: change src if preload didn't work
          setCurrentShotIndex(shotIndex);
          setTimeout(() => {
            const video = getActiveVideo();
            if (video) {
              video.currentTime = videoTime;
              // Ensure muted state is correct for target shot
              video.muted = isMuted || targetShot?.audioMuted || false;
              if (isPlaying) {
                video.play();
              }
            }
          }, 50);
        } else {
          const video = getActiveVideo();
          if (video) {
            video.currentTime = videoTime;
          }
        }
      }
    },
    [shotTimeline, playableShots, currentShotIndex, isPlaying, getActiveVideo, volume, isMuted]
  );

  // Toggle mute
  const toggleMute = useCallback(() => {
    setIsMuted((prev) => !prev);
    const video = getActiveVideo();
    if (video) {
      video.muted = !isMuted;
    }
  }, [isMuted, getActiveVideo]);

  // Handle volume change
  const handleVolumeChange = useCallback(
    (value: number[]) => {
      const newVolume = value[0];
      setVolume(newVolume);
      const video = getActiveVideo();
      if (video) {
        video.volume = newVolume;
      }
    },
    [getActiveVideo]
  );

  // Format time as MM:SS
  const formatTime = (ms: number) => {
    const seconds = Math.floor(ms / 1000);
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, "0")}`;
  };

  if (!hasVideos) {
    return (
      <div
        className={cn(
          "relative aspect-video bg-muted/30 rounded-lg border border-border flex items-center justify-center",
          className
        )}
      >
        <p className="text-muted-foreground text-sm text-center px-4 italic">
          Add shots and generate videos to preview the scene.
        </p>
      </div>
    );
  }

  // Shared event handlers for video elements
  const createVideoHandlers = useCallback(
    (shotIndex: number, shot: Shot) => {
      return {
        onEnded: handleVideoEnded,
        onTimeUpdate: handleTimeUpdate,
        onClick: togglePlay,
        onPlay: () => {
          setIsPlaying(true);
          setVideoError(null);
        },
        onPause: () => setIsPlaying(false),
        onError: (e: React.SyntheticEvent<HTMLVideoElement>) => {
          const video = e.currentTarget;
          const error = video.error;
          const errorMessage = error ? `${error.code}: ${error.message}` : "Unknown error";
          console.error(
            "[ScenePlayer] Video error:",
            JSON.stringify(
              {
                src: video.src,
                error: errorMessage,
                networkState: video.networkState,
                readyState: video.readyState,
              },
              null,
              2
            )
          );
          setVideoError(`Failed to load video: ${errorMessage}`);
        },
        onLoadedData: () => {
          setVideoError(null);
          // Seek to trim start position when video loads
          const shotInfo = shotTimeline[shotIndex];
          const video = getActiveVideo();
          if (shotInfo && shotInfo.trimStartMs > 0 && video) {
            video.currentTime = shotInfo.trimStartMs / 1000;
          }
        },
        onLoadedMetadata: (e: React.SyntheticEvent<HTMLVideoElement>) => {
          const video = e.currentTarget;
          if (video.duration && Number.isFinite(video.duration) && shot) {
            const durationMs = Math.round(video.duration * 1000);
            // Only update if different from stored/default duration
            const storedDuration = shot.video?.durationMs || 5000;
            if (Math.abs(durationMs - storedDuration) > 100) {
              setActualDurations((prev) => {
                const next = new Map(prev);
                next.set(shot.id, durationMs);
                return next;
              });
            }
          }
        },
      };
    },
    [handleVideoEnded, handleTimeUpdate, togglePlay, shotTimeline, getActiveVideo]
  );

  return (
    <div className={cn("space-y-3", className)}>
      {/* Video Player */}
      <div className="relative aspect-video bg-black rounded-lg overflow-hidden">
        {/* Current video */}
        {currentShot?.video?.url && (
          <>
            <video
              ref={videoRef}
              src={currentShot.video.url}
              className="w-full h-full object-contain cursor-pointer"
              {...createVideoHandlers(currentShotIndex, currentShot)}
              muted={isMuted || currentShot.audioMuted}
              playsInline
            >
              <track kind="captions" />
            </video>

            {/* Fade In Overlay */}
            {currentShot.fadeInType &&
              currentShot.fadeInType !== "none" &&
              (() => {
                const shotInfo = shotTimeline[currentShotIndex];
                if (!shotInfo) return null;

                const fadeDuration = (currentShot.fadeDurationMs || 500) / 1000; // Convert to seconds
                // Video time relative to trim start (fade starts at beginning of effective video)
                const videoTime = Math.max(0, currentTime - shotInfo.trimStartMs / 1000);
                const fadeProgress = Math.min(1, Math.max(0, videoTime / fadeDuration));
                const opacity =
                  currentShot.fadeInType === "black" || currentShot.fadeInType === "white"
                    ? 1 - fadeProgress
                    : 0;
                const bgColor = currentShot.fadeInType === "white" ? "bg-white" : "bg-black";

                if (fadeProgress < 1 && videoTime >= 0) {
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
            {currentShot.fadeOutType &&
              currentShot.fadeOutType !== "none" &&
              (() => {
                const shotInfo = shotTimeline[currentShotIndex];
                if (!shotInfo) return null;

                const fadeDuration = (currentShot.fadeDurationMs || 500) / 1000; // Convert to seconds
                const effectiveDuration = shotInfo.durationMs / 1000; // Effective duration in seconds
                const fadeOutStart = effectiveDuration - fadeDuration;
                // Video time relative to trim start (fade out is at end of effective video)
                const videoTime = Math.max(0, currentTime - shotInfo.trimStartMs / 1000);
                const fadeProgress =
                  videoTime >= fadeOutStart
                    ? Math.min(1, Math.max(0, (videoTime - fadeOutStart) / fadeDuration))
                    : 0;
                const opacity =
                  currentShot.fadeOutType === "black" || currentShot.fadeOutType === "white"
                    ? fadeProgress
                    : 0;
                const bgColor = currentShot.fadeOutType === "white" ? "bg-white" : "bg-black";

                if (fadeProgress > 0) {
                  return (
                    <div
                      className={`absolute inset-0 ${bgColor} transition-opacity duration-75 pointer-events-none z-10`}
                      style={{ opacity }}
                    />
                  );
                }
                return null;
              })()}
          </>
        )}

        {/* Preloaded videos for all shots (hidden, for preloading only) */}
        {playableShots.map((shot) => {
          // Skip the current shot since it's already rendered above
          if (shot.id === currentShot?.id) return null;

          return shot.video?.url ? (
            <video
              key={shot.id}
              ref={(el) => {
                if (el) {
                  preloadedVideoRefs.current.set(shot.id, el);
                } else {
                  preloadedVideoRefs.current.delete(shot.id);
                }
              }}
              src={shot.video.url}
              className="hidden"
              muted
              playsInline
              preload="auto"
            >
              <track kind="captions" />
            </video>
          ) : null;
        })}

        {/* Video error state */}
        {videoError && (
          <div className="absolute inset-0 flex items-center justify-center bg-black/80">
            <p className="text-red-400 text-sm text-center px-4">{videoError}</p>
          </div>
        )}

        {/* Play overlay (when paused) */}
        {!isPlaying && (
          <button
            type="button"
            onClick={togglePlay}
            className="absolute inset-0 flex items-center justify-center bg-black/30 hover:bg-black/40 transition-colors"
          >
            <div className="w-16 h-16 rounded-full bg-white/90 flex items-center justify-center shadow-lg">
              <Play className="h-8 w-8 text-black ml-1" />
            </div>
          </button>
        )}

        {/* Shot indicator */}
        <div className="absolute top-3 left-3 bg-black/60 text-white text-xs font-medium px-2 py-1 rounded">
          Shot {currentShotIndex + 1} of {playableShots.length}
        </div>
      </div>

      {/* Progress Bar */}
      <div className="space-y-1">
        <Slider
          value={[globalTimeMs]}
          min={0}
          max={totalDurationMs}
          step={100}
          onValueChange={handleSeek}
          className="cursor-pointer"
        />
        <div className="flex justify-between text-xs text-muted-foreground pt-2">
          <span>{formatTime(globalTimeMs)}</span>
          <span>{formatTime(totalDurationMs)}</span>
        </div>
      </div>

      {/* Controls */}
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-2">
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={goToPrevShot}
            className="bg-transparent h-7 w-12"
            title="Previous shot"
          >
            <SkipBack className="h-3 w-3" />
          </Button>
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={togglePlay}
            className="bg-transparent h-7 w-12"
          >
            {isPlaying ? <Pause className="h-3 w-3" /> : <Play className="h-3 w-3 ml-0.5" />}
          </Button>
          <Button
            type="button"
            variant="outline"
            size="icon"
            onClick={goToNextShot}
            disabled={!hasNext}
            className="bg-transparent h-7 w-12"
            title="Next shot"
          >
            <SkipForward className="h-3 w-3" />
          </Button>
        </div>

        {/* Volume Control */}
        <div className="flex items-center gap-2">
          <Button
            type="button"
            variant="ghost"
            size="icon"
            onClick={toggleMute}
            className="h-8 w-8"
          >
            {isMuted ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
          </Button>
          <Slider
            value={[isMuted ? 0 : volume]}
            min={0}
            max={1}
            step={0.1}
            onValueChange={handleVolumeChange}
            className="w-20"
          />
        </div>
      </div>

      {/* Hidden audio elements for audio tracks */}
      {audioTracks.map((track) => (
        <audio
          key={track.id}
          ref={(el) => {
            if (el) {
              audioRefs.current.set(track.id, el);
            } else {
              audioRefs.current.delete(track.id);
            }
          }}
          src={track.sourceUrl}
          preload="auto"
        />
      ))}
    </div>
  );
});
