/**
 * Client-side upload utilities with presigned URL support
 * for reliable large file uploads directly to S3
 */

// Size threshold for using presigned URLs (5MB)
// Files larger than this will upload directly to S3
export const PRESIGNED_UPLOAD_THRESHOLD = 5 * 1024 * 1024;

export type MediaType = "image" | "video" | "audio";

export interface UploadResult {
  success: boolean;
  url?: string;
  mediaId?: string;
  error?: string;
}

export interface UploadOptions {
  projectId: string;
  sceneId: string;
  mediaType: MediaType;
  onProgress?: (percent: number) => void;
  abortSignal?: AbortSignal;
}

/**
 * Get a presigned URL from our API for direct S3 upload
 */
async function getPresignedUrl(
  file: File,
  options: UploadOptions
): Promise<{
  success: boolean;
  uploadUrl?: string;
  publicUrl?: string;
  mediaId?: string;
  error?: string;
}> {
  const response = await fetch("/api/presigned-upload", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      projectId: options.projectId,
      sceneId: options.sceneId,
      mediaType: options.mediaType,
      contentType: file.type,
      fileName: file.name,
      fileSize: file.size,
    }),
  });

  const data = await response.json();

  if (!data.success) {
    return { success: false, error: data.error };
  }

  return {
    success: true,
    uploadUrl: data.uploadUrl,
    publicUrl: data.publicUrl,
    mediaId: data.mediaId,
  };
}

/**
 * Upload a file directly to S3 using a presigned URL with progress tracking
 */
async function uploadToS3WithProgress(
  file: File,
  uploadUrl: string,
  publicUrl: string,
  mediaId: string,
  options: UploadOptions
): Promise<UploadResult> {
  return new Promise((resolve) => {
    const xhr = new XMLHttpRequest();

    xhr.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable && options.onProgress) {
        const percentComplete = Math.round((event.loaded / event.total) * 100);
        options.onProgress(percentComplete);
      }
    });

    xhr.addEventListener("load", () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        console.log(
          "[uploadFile] S3 upload completed successfully:",
          JSON.stringify({ publicUrl, mediaId }, null, 2)
        );
        resolve({ success: true, url: publicUrl, mediaId });
      } else {
        console.error(
          "[uploadFile] S3 upload failed:",
          JSON.stringify(
            { status: xhr.status, statusText: xhr.statusText, response: xhr.responseText },
            null,
            2
          )
        );
        resolve({
          success: false,
          error: `Upload failed with status ${xhr.status}: ${xhr.statusText}`,
        });
      }
    });

    xhr.addEventListener("error", () => {
      resolve({ success: false, error: "Network error during upload" });
    });

    xhr.addEventListener("abort", () => {
      resolve({ success: false, error: "Upload cancelled" });
    });

    // Handle abort signal if provided
    if (options.abortSignal) {
      options.abortSignal.addEventListener("abort", () => {
        xhr.abort();
      });
    }

    xhr.open("PUT", uploadUrl);
    xhr.setRequestHeader("Content-Type", file.type);
    xhr.send(file);
  });
}

/**
 * Upload a file using the traditional server-side route
 */
async function uploadViaServer(file: File, options: UploadOptions): Promise<UploadResult> {
  const formData = new FormData();
  formData.append("file", file);
  formData.append("projectId", options.projectId);
  formData.append("sceneId", options.sceneId);
  formData.append("mediaType", options.mediaType);

  const response = await fetch("/api/scenes/upload-media", {
    method: "POST",
    body: formData,
  });

  const data = await response.json();

  return {
    success: data.success,
    url: data.url,
    mediaId: data.id,
    error: data.error,
  };
}

/**
 * Smart upload function that automatically chooses the best upload method
 * - Uses presigned URLs for large files (>5MB) to avoid server memory issues
 * - Uses server-side upload for smaller files (allows for server-side optimization)
 */
export async function uploadFile(file: File, options: UploadOptions): Promise<UploadResult> {
  const usePresigned = file.size > PRESIGNED_UPLOAD_THRESHOLD;

  console.log(
    `[uploadFile] Starting upload:`,
    JSON.stringify(
      {
        fileName: file.name,
        fileSize: file.size,
        mediaType: options.mediaType,
        usePresigned,
      },
      null,
      2
    )
  );

  if (usePresigned) {
    // Get presigned URL
    const presigned = await getPresignedUrl(file, options);

    if (!presigned.success || !presigned.uploadUrl || !presigned.publicUrl || !presigned.mediaId) {
      return { success: false, error: presigned.error || "Failed to get upload URL" };
    }

    // Upload directly to S3
    return uploadToS3WithProgress(
      file,
      presigned.uploadUrl,
      presigned.publicUrl,
      presigned.mediaId,
      options
    );
  }

  // Use traditional server upload for smaller files
  return uploadViaServer(file, options);
}

/**
 * Create an upload handler with abort capability
 */
export function createUploadController() {
  const controller = new AbortController();

  return {
    signal: controller.signal,
    abort: () => controller.abort(),
  };
}
