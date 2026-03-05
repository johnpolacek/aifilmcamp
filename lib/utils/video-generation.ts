/**
 * Utility functions for video generation feature flags
 * Video generation is only enabled in development/localhost environments
 */

/**
 * Check if video generation is enabled (localhost/development only)
 * Returns true only when explicitly enabled for legacy/internal workflows.
 */
export function isVideoGenerationEnabled(): boolean {
  const explicitFlag = process.env.NEXT_PUBLIC_ENABLE_LEGACY_VIDEO === "true";

  // Server-side check
  if (typeof window === "undefined") {
    const isDevelopment = process.env.NODE_ENV === "development";
    const appUrl = process.env.NEXT_PUBLIC_APP_URL || "";
    const isLocalhost = appUrl.includes("localhost") || appUrl.includes("127.0.0.1");

    return explicitFlag && isDevelopment && isLocalhost;
  }

  // Client-side check
  const hostname = window.location.hostname;
  const isLocalhost = hostname === "localhost" || hostname === "127.0.0.1" || hostname === "[::1]";

  return explicitFlag && isLocalhost;
}
