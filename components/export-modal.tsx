interface ExportModalProps {
  isComplete: boolean;
  progress: number;
  onDownload: () => void;
}

export default function ExportModal({ isComplete, progress, onDownload }: ExportModalProps) {
  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-card rounded-lg p-8 w-96 shadow-2xl border border-border">
        {!isComplete ? (
          <div>
            <h2 className="text-xl font-semibold mb-4">Rendering...</h2>
            <div className="w-full bg-muted rounded-full h-2 overflow-hidden">
              <div
                className="bg-primary h-full transition-all duration-300"
                style={{ width: `${Math.min(progress, 100)}%` }}
              />
            </div>
            <p className="text-muted-foreground text-sm mt-3">
              {Math.min(Math.round(progress), 100)}%
            </p>
          </div>
        ) : (
          <div className="text-center">
            <h2 className="text-xl font-semibold mb-6">Your video is ready!</h2>
            <button
              onClick={onDownload}
              className="w-full bg-primary text-primary-foreground py-2 rounded-lg font-medium hover:opacity-90 transition"
            >
              Download .mp4
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
