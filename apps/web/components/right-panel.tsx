interface RightPanelProps {
  aspectRatio: string;
  selectedClipLabel: string;
}

export default function RightPanel({ aspectRatio, selectedClipLabel }: RightPanelProps) {
  const getAspectClass = () => {
    switch (aspectRatio) {
      case "16:9":
        return "aspect-video";
      case "9:16":
        return "aspect-[9/16]";
      case "1:1":
        return "aspect-square";
      default:
        return "aspect-video";
    }
  };

  return (
    <div className="flex-1 bg-card rounded-lg border border-border flex flex-col items-center justify-center p-6 relative">
      {/* Preview Monitor */}
      <div
        className={`${getAspectClass()} w-full max-w-md bg-black rounded-lg shadow-lg relative overflow-hidden`}
      >
        {/* Label Overlay */}
        {selectedClipLabel && (
          <div className="absolute bottom-4 left-4 bg-black/60 px-3 py-2 rounded text-white text-sm font-medium">
            {selectedClipLabel}
          </div>
        )}
      </div>

      {/* Aspect Ratio Label */}
      <p className="text-muted-foreground text-sm mt-4">Aspect Ratio: {aspectRatio}</p>
    </div>
  );
}
