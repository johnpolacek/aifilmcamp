/**
 * Audio waveform generation utilities
 * Uses Web Audio API to analyze audio files and generate waveform data
 */

export interface WaveformData {
  peaks: number[]; // Normalized peak values (0-1)
  duration: number; // Duration in seconds
}

/**
 * Generate waveform peaks from an audio URL
 * @param audioUrl - URL of the audio file
 * @param numSamples - Number of peak samples to generate (default: 100)
 * @returns Promise<WaveformData>
 */
export async function generateWaveformFromUrl(
  audioUrl: string,
  numSamples: number = 100
): Promise<WaveformData> {
  // Return empty waveform for invalid URLs
  if (!audioUrl || audioUrl.trim() === "") {
    return {
      peaks: Array(numSamples).fill(0.3),
      duration: 0,
    };
  }

  try {
    // Fetch the audio file with credentials to handle CORS
    const response = await fetch(audioUrl, {
      mode: "cors",
      credentials: "omit",
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    const arrayBuffer = await response.arrayBuffer();

    // Decode audio data
    const audioContext = new (
      window.AudioContext ||
      (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
    )();
    const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

    // Get the audio data from the first channel
    const channelData = audioBuffer.getChannelData(0);
    const samplesPerPeak = Math.floor(channelData.length / numSamples);

    const peaks: number[] = [];
    for (let i = 0; i < numSamples; i++) {
      const start = i * samplesPerPeak;
      const end = start + samplesPerPeak;

      // Find the max absolute value in this segment
      let max = 0;
      for (let j = start; j < end && j < channelData.length; j++) {
        const absValue = Math.abs(channelData[j]);
        if (absValue > max) {
          max = absValue;
        }
      }
      peaks.push(max);
    }

    // Normalize peaks to 0-1 range
    const maxPeak = Math.max(...peaks, 0.01); // Avoid division by zero
    const normalizedPeaks = peaks.map((p) => p / maxPeak);

    // Close the audio context
    await audioContext.close();

    return {
      peaks: normalizedPeaks,
      duration: audioBuffer.duration,
    };
  } catch (error) {
    console.error(
      "[generateWaveformFromUrl] Error:",
      error instanceof Error ? error.message : String(error)
    );
    // Return a flat waveform as fallback
    return {
      peaks: Array(numSamples).fill(0.3),
      duration: 0,
    };
  }
}

// Cache for waveform data to avoid re-fetching
const waveformCache = new Map<string, WaveformData>();

/**
 * Get waveform data with caching
 */
export async function getWaveformData(
  audioUrl: string,
  numSamples: number = 100
): Promise<WaveformData> {
  const cacheKey = `${audioUrl}-${numSamples}`;

  if (waveformCache.has(cacheKey)) {
    return waveformCache.get(cacheKey)!;
  }

  const data = await generateWaveformFromUrl(audioUrl, numSamples);
  waveformCache.set(cacheKey, data);
  return data;
}

/**
 * Clear waveform cache for a specific URL or all
 */
export function clearWaveformCache(audioUrl?: string): void {
  if (audioUrl) {
    // Clear all entries for this URL
    for (const key of waveformCache.keys()) {
      if (key.startsWith(audioUrl)) {
        waveformCache.delete(key);
      }
    }
  } else {
    waveformCache.clear();
  }
}
