import {
  DeleteObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { optimizeAvatar, optimizeImage, optimizeThumbnail } from "./image-optimization";

// Initialize S3 Client
export const s3Client = new S3Client({
  region: process.env.AWS_REGION!,
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
  },
});

export const BUCKET_NAME =
  process.env.AWS_S3_BUCKET_NAME || process.env.NEXT_PUBLIC_AWS_S3_BUCKET_NAME!;
export const CLOUDFRONT_DOMAIN =
  process.env.AWS_CLOUDFRONT_DOMAIN || process.env.NEXT_PUBLIC_AWS_CLOUDFRONT_DOMAIN;

/**
 * Get the public URL for an S3 object (using CloudFront if available, otherwise S3)
 * Server-side only - use getPublicUrl from lib/utils.ts for client-side
 */
function getPublicUrlServer(key: string): string {
  if (CLOUDFRONT_DOMAIN) {
    return `https://${CLOUDFRONT_DOMAIN}/${key}`;
  }
  return `https://${BUCKET_NAME}.s3.amazonaws.com/${key}`;
}

/**
 * Get an object from S3
 */
export async function getObjectFromS3(key: string): Promise<string | null> {
  try {
    const command = new GetObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    const response = await s3Client.send(command);
    const str = await response.Body?.transformToString();
    return str || null;
  } catch (error) {
    const awsError = error as {
      name?: string;
      message?: string;
      Code?: string;
      $metadata?: { httpStatusCode?: number };
      stack?: string;
    };

    if (awsError.name === "NoSuchKey") {
      return null;
    }
    throw error;
  }
}

/**
 * Get a file buffer from S3
 */
export async function getFileBufferFromS3(key: string): Promise<Buffer | null> {
  try {
    const command = new GetObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    const response = await s3Client.send(command);
    const arrayBuffer = await response.Body?.transformToByteArray();

    if (!arrayBuffer) {
      return null;
    }

    return Buffer.from(arrayBuffer);
  } catch (error) {
    const awsError = error as {
      name?: string;
      message?: string;
      Code?: string;
      $metadata?: { httpStatusCode?: number };
      stack?: string;
    };

    if (awsError.name === "NoSuchKey") {
      return null;
    }
    throw error;
  }
}

/**
 * Put an object to S3
 */
export async function putObjectToS3(
  key: string,
  body: string,
  contentType = "application/json"
): Promise<void> {
  const command = new PutObjectCommand({
    Bucket: BUCKET_NAME,
    Key: key,
    Body: body,
    ContentType: contentType,
  });

  await s3Client.send(command);
}

/**
 * List objects in S3 with a given prefix
 */
export async function listObjectsInS3(prefix: string): Promise<string[]> {
  const command = new ListObjectsV2Command({
    Bucket: BUCKET_NAME,
    Prefix: prefix,
  });

  const response = await s3Client.send(command);
  return response.Contents?.map((item) => item.Key!).filter(Boolean) || [];
}

/**
 * Upload image from a URL to S3 (optimized)
 */
export async function uploadImageFromUrl(
  url: string,
  key: string,
  options?: { isAvatar?: boolean; isThumbnail?: boolean }
): Promise<string> {
  try {
    // Fetch the image from the URL
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Failed to fetch image: ${response.statusText}`);
    }

    const arrayBuffer = await response.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    // Optimize the image before uploading
    let optimizedBuffer: Buffer;
    let contentType: string;

    if (options?.isAvatar) {
      const result = await optimizeAvatar(buffer);
      optimizedBuffer = result.buffer;
      contentType = result.contentType;
    } else if (options?.isThumbnail) {
      const result = await optimizeThumbnail(buffer);
      optimizedBuffer = result.buffer;
      contentType = result.contentType;
    } else {
      const result = await optimizeImage(buffer);
      optimizedBuffer = result.buffer;
      contentType = result.contentType;
    }

    // Upload optimized image to S3
    // Note: Bucket should be configured with public read access via bucket policy
    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      Body: optimizedBuffer,
      ContentType: contentType,
    });

    await s3Client.send(command);

    // Return the public URL (using CloudFront if configured)
    return getPublicUrlServer(key);
  } catch (error) {
    console.error("Error uploading image from URL:", error);
    throw error;
  }
}

/**
 * Upload image from buffer to S3 (optimized)
 */
export async function uploadImageFromBuffer(
  buffer: Buffer,
  key: string,
  _contentType?: string,
  options?: { isAvatar?: boolean; isThumbnail?: boolean }
): Promise<string> {
  try {
    console.log(
      "[uploadImageFromBuffer] Starting image optimization:",
      JSON.stringify(
        {
          key,
          bufferSize: buffer.length,
          options: options
            ? {
                isAvatar: options.isAvatar,
                isThumbnail: options.isThumbnail,
              }
            : undefined,
        },
        null,
        2
      )
    );

    // Optimize the image before uploading
    let optimizedBuffer: Buffer;
    let optimizedContentType: string;

    if (options?.isAvatar) {
      console.log("[uploadImageFromBuffer] Using optimizeAvatar path");
      const result = await optimizeAvatar(buffer);
      optimizedBuffer = result.buffer;
      optimizedContentType = result.contentType;
    } else if (options?.isThumbnail) {
      // Only use thumbnail optimization when explicitly requested (e.g., project thumbnails)
      // Post images should NOT use this - it crops to 16:9 aspect ratio
      console.warn(
        "[uploadImageFromBuffer] WARNING: Using optimizeThumbnail - this will crop to 16:9!",
        JSON.stringify(
          {
            key,
            reason: "isThumbnail option was set to true",
          },
          null,
          2
        )
      );
      const result = await optimizeThumbnail(buffer);
      optimizedBuffer = result.buffer;
      optimizedContentType = result.contentType;
    } else {
      // Default: use optimizeImage which maintains original aspect ratio (no cropping)
      console.log(
        "[uploadImageFromBuffer] Using optimizeImage path (maintains aspect ratio, no cropping)"
      );

      // CRITICAL: Force optimizeImage - never use thumbnail for post images
      // Double-check that options is not set to thumbnail
      if (options?.isThumbnail) {
        console.error(
          "[uploadImageFromBuffer] ERROR: isThumbnail was set but we're in post image path! This should never happen!"
        );
      }

      const result = await optimizeImage(buffer);
      optimizedBuffer = result.buffer;
      optimizedContentType = result.contentType;
    }

    console.log(
      "[uploadImageFromBuffer] Optimization complete:",
      JSON.stringify(
        {
          key,
          originalSize: buffer.length,
          optimizedSize: optimizedBuffer.length,
          contentType: optimizedContentType,
        },
        null,
        2
      )
    );

    // Note: Bucket should be configured with public read access via bucket policy
    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      Body: optimizedBuffer,
      ContentType: optimizedContentType,
    });

    await s3Client.send(command);

    // Return the public URL (using CloudFront if configured)
    return getPublicUrlServer(key);
  } catch (error) {
    console.error("Error uploading image from buffer:", error);
    throw error;
  }
}

/**
 * Upload a file to S3 (non-image files like PDFs, documents, etc.)
 */
export async function uploadFileFromBuffer(
  buffer: Buffer,
  key: string,
  contentType: string
): Promise<string> {
  try {
    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      Body: buffer,
      ContentType: contentType,
    });

    await s3Client.send(command);

    // Return the public URL (using CloudFront if configured)
    return getPublicUrlServer(key);
  } catch (error) {
    console.error("Error uploading file:", error);
    throw error;
  }
}

/**
 * Delete an object from S3
 */
export async function deleteObjectFromS3(key: string): Promise<void> {
  try {
    const command = new DeleteObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    await s3Client.send(command);
    console.log("[s3] Deleted object:", JSON.stringify({ key }, null, 2));
  } catch (error) {
    console.error(
      "[s3] Error deleting object:",
      JSON.stringify(
        { key, error: error instanceof Error ? error.message : String(error) },
        null,
        2
      )
    );
    throw error;
  }
}
