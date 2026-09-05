"use client";

import { Loader2 } from "lucide-react";
import Image from "next/image";
import { useState } from "react";
import { ImagePlaceholder } from "@/components/ui/image-placeholder";
import { getImageUrl, type ImageType } from "@/lib/image-utils";
import { cn } from "@/lib/utils";

export interface OptimizedImageProps {
  /** Image type (thumbnail, character, location, post, avatar) */
  type: ImageType;
  /** Image filename */
  filename: string | undefined;
  /** Username for constructing the path */
  username: string | undefined;
  /** Alt text for the image */
  alt: string;
  /** Use fill layout (image will fill parent container) */
  fill?: boolean;
  /** Fixed width (required if fill is false) */
  width?: number;
  /** Fixed height (required if fill is false) */
  height?: number;
  /** Additional CSS classes */
  className?: string;
  /** Object fit style */
  objectFit?: "contain" | "cover" | "fill" | "none" | "scale-down";
  /** Sizes attribute for responsive images */
  sizes?: string;
  /** Show placeholder when image is missing */
  showPlaceholder?: boolean;
  /** Custom placeholder component */
  placeholder?: React.ReactNode;
  /** Priority loading */
  priority?: boolean;
  /** Image source override (for preview images) */
  src?: string;
}

/**
 * Unified optimized image component with loading states, error handling, and type support
 */
export function OptimizedImage({
  type,
  filename,
  username,
  alt,
  fill = false,
  width,
  height,
  className,
  objectFit = "cover",
  sizes,
  showPlaceholder = true,
  placeholder,
  priority = false,
  src: srcOverride,
}: OptimizedImageProps) {
  const [isLoading, setIsLoading] = useState(true);
  const [hasError, setHasError] = useState(false);

  // Use provided src or generate from type/filename/username
  const imageSrc = srcOverride || getImageUrl({ type, filename, username });

  // If no image source and showPlaceholder is true, show placeholder
  if (!imageSrc && showPlaceholder) {
    return (
      <>
        {placeholder || (
          <ImagePlaceholder
            className={cn(fill ? "absolute inset-0" : "", className)}
            variant={type === "avatar" ? "avatar" : "default"}
          />
        )}
      </>
    );
  }

  // If error occurred, show placeholder
  if (hasError && showPlaceholder) {
    return (
      <>
        {placeholder || (
          <ImagePlaceholder
            className={cn(fill ? "absolute inset-0" : "", className)}
            variant={type === "avatar" ? "avatar" : "default"}
            text="Failed to load image"
          />
        )}
      </>
    );
  }

  const imageClassName = cn(
    {
      "object-contain": objectFit === "contain",
      "object-cover": objectFit === "cover",
      "object-fill": objectFit === "fill",
      "object-none": objectFit === "none",
      "object-scale-down": objectFit === "scale-down",
    },
    className
  );

  // Default sizes if not provided
  const defaultSizes =
    sizes ||
    (fill
      ? "(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
      : width
        ? `(max-width: ${width}px) 100vw, ${width}px`
        : undefined);

  return (
    <div className={cn(fill ? "relative w-full h-full" : "relative", className)}>
      {isLoading && (
        <div className="absolute inset-0 flex items-center justify-center bg-muted/30">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      )}
      {fill ? (
        <Image
          src={imageSrc}
          alt={alt}
          fill
          className={imageClassName}
          sizes={defaultSizes}
          priority={priority}
          onLoad={() => setIsLoading(false)}
          onError={() => {
            setIsLoading(false);
            setHasError(true);
          }}
        />
      ) : (
        <Image
          src={imageSrc}
          alt={alt}
          width={width}
          height={height}
          className={imageClassName}
          sizes={defaultSizes}
          priority={priority}
          onLoad={() => setIsLoading(false)}
          onError={() => {
            setIsLoading(false);
            setHasError(true);
          }}
        />
      )}
    </div>
  );
}
