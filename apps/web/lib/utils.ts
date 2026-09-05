import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// Re-export image utilities for backward compatibility
export {
  getCharacterImageUrl,
  getImageUrl,
  getLocationImageUrl,
  getPostImageUrl,
  getProjectFileUrl,
  getPublicUrl,
  getThumbnailUrl,
} from "./image-utils";
