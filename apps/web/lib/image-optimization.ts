import sharp from "sharp";

export interface ImageOptimizationOptions {
  maxWidth?: number;
  maxHeight?: number;
  quality?: number;
  format?: "jpeg" | "webp" | "png";
}

/**
 * Optimize an image buffer using sharp
 *
 * @param buffer - The image buffer to optimize
 * @param options - Optimization options
 * @returns Optimized image buffer and content type
 */
export async function optimizeImage(
  buffer: Buffer,
  options: ImageOptimizationOptions = {}
): Promise<{ buffer: Buffer; contentType: string }> {
  const { maxWidth = 1920, maxHeight = 1920, quality = 85, format = "jpeg" } = options;

  let sharpInstance = sharp(buffer);

  // Get image metadata
  const metadata = await sharpInstance.metadata();

  console.log(
    "[optimizeImage] Original image metadata:",
    JSON.stringify(
      {
        width: metadata.width,
        height: metadata.height,
        format: metadata.format,
        hasProfile: metadata.hasProfile,
        orientation: metadata.orientation,
        maxWidth,
        maxHeight,
      },
      null,
      2
    )
  );

  // Auto-rotate based on EXIF data
  sharpInstance = sharpInstance.rotate();

  // Resize if needed (maintain aspect ratio)
  if (metadata.width && metadata.height) {
    const needsResize = metadata.width > maxWidth || metadata.height > maxHeight;

    if (needsResize) {
      // Calculate new dimensions maintaining aspect ratio
      const aspectRatio = metadata.width / metadata.height;
      let newWidth = metadata.width;
      let newHeight = metadata.height;

      if (metadata.width > maxWidth) {
        newWidth = maxWidth;
        newHeight = Math.round(maxWidth / aspectRatio);
      }
      if (newHeight > maxHeight) {
        newHeight = maxHeight;
        newWidth = Math.round(maxHeight * aspectRatio);
      }

      console.log(
        "[optimizeImage] Resizing with fit:inside (maintains aspect ratio, no cropping):",
        JSON.stringify(
          {
            originalWidth: metadata.width,
            originalHeight: metadata.height,
            originalAspectRatio: aspectRatio.toFixed(4),
            newWidth,
            newHeight,
            newAspectRatio: (newWidth / newHeight).toFixed(4),
            maxWidth,
            maxHeight,
          },
          null,
          2
        )
      );

      sharpInstance = sharpInstance.resize(maxWidth, maxHeight, {
        fit: "inside",
        withoutEnlargement: true,
      });
    } else {
      console.log(
        "[optimizeImage] No resize needed - image is within limits, maintaining original dimensions"
      );
    }
  }

  // Get final metadata after processing
  const finalMetadata = await sharpInstance.metadata();
  console.log(
    "[optimizeImage] Final image metadata:",
    JSON.stringify(
      {
        width: finalMetadata.width,
        height: finalMetadata.height,
        format: finalMetadata.format,
      },
      null,
      2
    )
  );

  // Convert and optimize based on format
  let optimizedBuffer: Buffer;
  let contentType: string;

  switch (format) {
    case "webp":
      optimizedBuffer = await sharpInstance.webp({ quality, effort: 4 }).toBuffer();
      contentType = "image/webp";
      break;
    case "png":
      optimizedBuffer = await sharpInstance.png({ quality, compressionLevel: 9 }).toBuffer();
      contentType = "image/png";
      break;
    default:
      // Convert to JPEG (smaller file size for photos)
      optimizedBuffer = await sharpInstance.jpeg({ quality, mozjpeg: true }).toBuffer();
      contentType = "image/jpeg";
      break;
  }

  return { buffer: optimizedBuffer, contentType };
}

/**
 * Optimize an image buffer specifically for avatars (smaller, square)
 */
export async function optimizeAvatar(
  buffer: Buffer
): Promise<{ buffer: Buffer; contentType: string }> {
  return optimizeImage(buffer, {
    maxWidth: 400,
    maxHeight: 400,
    quality: 90,
    format: "jpeg",
  });
}

/**
 * Optimize an image buffer for thumbnails (16:9 aspect-video ratio)
 */
export async function optimizeThumbnail(
  buffer: Buffer
): Promise<{ buffer: Buffer; contentType: string }> {
  console.warn(
    "[optimizeThumbnail] WARNING: optimizeThumbnail called - this will crop images to 16:9!"
  );

  let sharpInstance = sharp(buffer);

  // Get image metadata
  const metadata = await sharpInstance.metadata();

  console.log(
    "[optimizeThumbnail] Original image metadata:",
    JSON.stringify(
      {
        width: metadata.width,
        height: metadata.height,
        format: metadata.format,
      },
      null,
      2
    )
  );

  // Auto-rotate based on EXIF data
  sharpInstance = sharpInstance.rotate();

  // Target dimensions for 16:9 aspect ratio
  const targetWidth = 1920;
  const targetHeight = 1080;

  if (metadata.width && metadata.height) {
    // Calculate aspect ratios
    const imageAspect = metadata.width / metadata.height;
    const targetAspect = 16 / 9;

    console.log(
      "[optimizeThumbnail] Aspect ratio comparison:",
      JSON.stringify(
        {
          imageAspect: imageAspect.toFixed(4),
          targetAspect: targetAspect.toFixed(4),
          difference: Math.abs(imageAspect - targetAspect).toFixed(4),
          willCrop: Math.abs(imageAspect - targetAspect) > 0.01,
        },
        null,
        2
      )
    );

    if (Math.abs(imageAspect - targetAspect) > 0.01) {
      // Aspect ratios don't match, need to crop
      let cropWidth = metadata.width;
      let cropHeight = metadata.height;
      let left = 0;
      let top = 0;

      if (imageAspect > targetAspect) {
        // Image is wider than 16:9, crop horizontally (center crop)
        cropHeight = metadata.height;
        cropWidth = Math.round(metadata.height * targetAspect);
        left = Math.round((metadata.width - cropWidth) / 2);
        console.log(
          "[optimizeThumbnail] Cropping horizontally (center crop):",
          JSON.stringify(
            {
              originalWidth: metadata.width,
              originalHeight: metadata.height,
              cropWidth,
              cropHeight,
              left,
              top: 0,
              cropType: "horizontal",
            },
            null,
            2
          )
        );
      } else {
        // Image is taller than 16:9, crop vertically (center crop)
        cropWidth = metadata.width;
        cropHeight = Math.round(metadata.width / targetAspect);
        top = Math.round((metadata.height - cropHeight) / 2);
        console.log(
          "[optimizeThumbnail] Cropping vertically (center crop):",
          JSON.stringify(
            {
              originalWidth: metadata.width,
              originalHeight: metadata.height,
              cropWidth,
              cropHeight,
              left: 0,
              top,
              cropType: "vertical",
            },
            null,
            2
          )
        );
      }

      // Crop to 16:9 aspect ratio
      sharpInstance = sharpInstance.extract({
        left,
        top,
        width: cropWidth,
        height: cropHeight,
      });
    }

    // Resize to target dimensions (maintains 16:9)
    sharpInstance = sharpInstance.resize(targetWidth, targetHeight, {
      fit: "cover",
      withoutEnlargement: false,
    });
  } else {
    // Fallback: resize without cropping if metadata unavailable
    sharpInstance = sharpInstance.resize(targetWidth, targetHeight, {
      fit: "cover",
    });
  }

  // Convert to JPEG
  const optimizedBuffer = await sharpInstance.jpeg({ quality: 85, mozjpeg: true }).toBuffer();

  return { buffer: optimizedBuffer, contentType: "image/jpeg" };
}
