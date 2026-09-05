/**
 * Unified image utilities for handling image URLs and paths
 */

export type ImageType = "thumbnail" | "character" | "location" | "post" | "avatar";

export interface ImagePathConfig {
  type: ImageType;
  filename: string | undefined;
  username: string | undefined;
}

/**
 * Get the public URL for an S3 object (using CloudFront if available, otherwise S3)
 * Can be used on both server and client side - this is client-safe (no server-only imports)
 */
export function getPublicUrl(key: string): string {
  // Client-side: use NEXT_PUBLIC_ prefixed env var
  // Server-side: use regular env var (fallback to NEXT_PUBLIC_)
  const cloudfrontDomain =
    typeof window === "undefined"
      ? process.env.AWS_CLOUDFRONT_DOMAIN || process.env.NEXT_PUBLIC_AWS_CLOUDFRONT_DOMAIN
      : process.env.NEXT_PUBLIC_AWS_CLOUDFRONT_DOMAIN;

  if (cloudfrontDomain) {
    return `https://${cloudfrontDomain}/${key}`;
  }

  // Fallback to S3 URL (need bucket name from env)
  const bucketName =
    typeof window === "undefined"
      ? process.env.AWS_S3_BUCKET_NAME || process.env.NEXT_PUBLIC_AWS_S3_BUCKET_NAME
      : process.env.NEXT_PUBLIC_AWS_S3_BUCKET_NAME;

  if (bucketName) {
    return `https://${bucketName}.s3.amazonaws.com/${key}`;
  }

  // If neither is available, return the key as-is (shouldn't happen in production)
  return key;
}

/**
 * Get the S3 key path for an image based on type
 */
function getImageKey(type: ImageType, filename: string, username: string): string {
  const pathMap: Record<ImageType, string> = {
    thumbnail: `thumbnails/${username}/${filename}`,
    character: `characters/${username}/${filename}`,
    location: `locations/${username}/${filename}`,
    post: `posts/${username}/${filename}`,
    avatar: `avatars/${username}/${filename}`,
  };

  return pathMap[type];
}

/**
 * Get the full URL for an image
 * This is the main function to use for getting image URLs
 */
export function getImageUrl(config: ImagePathConfig): string {
  const { type, filename, username } = config;

  if (!filename || !username) return "";

  const key = getImageKey(type, filename, username);
  return getPublicUrl(key);
}

/**
 * Get the thumbnail URL for a project
 * @deprecated Use getImageUrl({ type: 'thumbnail', filename, username }) instead
 */
export function getThumbnailUrl(
  thumbnail: string | undefined,
  username: string | undefined
): string {
  return getImageUrl({ type: "thumbnail", filename: thumbnail, username });
}

/**
 * Get the character image URL
 * @deprecated Use getImageUrl({ type: 'character', filename: image, username }) instead
 */
export function getCharacterImageUrl(
  image: string | undefined,
  username: string | undefined
): string {
  return getImageUrl({ type: "character", filename: image, username });
}

/**
 * Get the location image URL
 * @deprecated Use getImageUrl({ type: 'location', filename: image, username }) instead
 */
export function getLocationImageUrl(
  image: string | undefined,
  username: string | undefined
): string {
  return getImageUrl({ type: "location", filename: image, username });
}

/**
 * Get the post image URL
 * @deprecated Use getImageUrl({ type: 'post', filename: image, username }) instead
 */
export function getPostImageUrl(image: string | undefined, username: string | undefined): string {
  return getImageUrl({ type: "post", filename: image, username });
}

/**
 * Get the project file URL
 * Project file should be just the filename (e.g., "1761873619145-screenplay.pdf")
 * Username is required to construct the full path
 */
export function getProjectFileUrl(
  filename: string | undefined,
  username: string | undefined
): string {
  if (!filename || !username) return "";

  const key = `projects/${username}/files/${filename}`;
  return getPublicUrl(key);
}
