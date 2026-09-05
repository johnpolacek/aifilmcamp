import { Image as ImageIcon } from "lucide-react";
import { cn } from "@/lib/utils";

interface ImagePlaceholderProps {
  className?: string;
  variant?: "default" | "avatar";
  text?: string;
}

export function ImagePlaceholder({
  className,
  variant = "default",
  text = "No image provided",
}: ImagePlaceholderProps) {
  if (variant === "avatar") {
    return (
      <div
        className={cn(
          "flex items-center justify-center bg-muted/50 border border-dashed border-border rounded-full",
          className
        )}
      >
        <ImageIcon className="h-4 w-4 text-muted-foreground" />
      </div>
    );
  }

  return (
    <div
      className={cn(
        "w-full h-full flex items-center justify-center bg-muted/50 border border-dashed border-border",
        className
      )}
    >
      <div className="flex flex-col items-center gap-2 text-center px-4">
        <ImageIcon className="h-8 w-8 text-muted-foreground" />
        <span className="text-sm text-muted-foreground">{text}</span>
      </div>
    </div>
  );
}
