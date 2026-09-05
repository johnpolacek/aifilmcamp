"use client";

import { Loader2 } from "lucide-react";
import Image from "next/image";
import { ImagePlaceholder } from "@/components/ui/image-placeholder";
import { cn } from "@/lib/utils";

export interface ImagePreviewProps {
  /** Preview image source (data URL or URL) */
  src?: string | null;
  /** Whether image is currently uploading */
  isUploading?: boolean;
  /** Whether image is successfully uploaded */
  isUploaded?: boolean;
  /** Alt text for the image */
  alt?: string;
  /** Additional CSS classes */
  className?: string;
  /** Aspect ratio container class */
  aspectRatio?: "video" | "square" | "auto";
  /** Object fit style */
  objectFit?: "contain" | "cover";
  /** Custom placeholder component */
  placeholder?: React.ReactNode;
  /** Error message to display */
  errorMessage?: string;
  /** Called when image fails to load */
  onError?: () => void;
}

/**
 * Image preview component for forms with upload states
 */
export function ImagePreview({
  src,
  isUploading = false,
  isUploaded = false,
  alt = "Preview",
  className,
  aspectRatio = "video",
  objectFit = "cover",
  placeholder,
  errorMessage,
  onError,
}: ImagePreviewProps) {
  const aspectRatioClass =
    aspectRatio === "video" ? "aspect-video" : aspectRatio === "square" ? "aspect-square" : "";

  return (
    <div
      className={cn(
        "relative w-full rounded-md overflow-hidden border border-border bg-muted",
        aspectRatioClass,
        className
      )}
    >
      {isUploading ? (
        <div className="w-full h-full flex items-center justify-center">
          <Loader2 className="h-8 w-8 animate-spin text-primary" />
        </div>
      ) : src ? (
        <Image
          src={src}
          alt={alt}
          fill
          className={cn(objectFit === "contain" ? "object-contain" : "object-cover")}
          onError={() => {
            if (onError) {
              onError();
            }
          }}
        />
      ) : isUploaded ? (
        <div className="w-full h-full flex items-center justify-center text-muted-foreground text-sm">
          Image uploaded successfully
        </div>
      ) : errorMessage ? (
        <div className="w-full h-full flex items-center justify-center text-muted-foreground text-sm">
          {errorMessage}
        </div>
      ) : (
        placeholder || (
          <ImagePlaceholder
            className="absolute inset-0"
            variant="default"
            text="No image provided"
          />
        )
      )}
    </div>
  );
}
