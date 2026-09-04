interface Clip {
  id: string;
  name: string;
  thumbnail: string;
  label: string;
  duration: number;
}

interface LeftPanelProps {
  clips: Clip[];
  selectedClip: Clip | null;
  activeTab: "media" | "properties";
  onTabChange: (tab: "media" | "properties") => void;
  onUploadClick: () => void;
  onDragStart: (clip: Clip) => (e: React.DragEvent) => void;
  onUpdateLabel: (label: string) => void;
  fileInputRef: React.RefObject<HTMLInputElement>;
  onFileSelect: (e: React.ChangeEvent<HTMLInputElement>) => void;
}

export default function LeftPanel({
  clips,
  selectedClip,
  activeTab,
  onTabChange,
  onUploadClick,
  onDragStart,
  onUpdateLabel,
}: LeftPanelProps) {
  return (
    <div className="w-64 border-r border-border bg-card rounded-lg overflow-hidden flex flex-col">
      {/* Tabs */}
      <div className="flex border-b border-border">
        <button
          onClick={() => onTabChange("media")}
          className={`flex-1 py-3 px-4 text-sm font-medium transition ${
            activeTab === "media"
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:text-foreground"
          }`}
        >
          Media Bin
        </button>
        <button
          onClick={() => onTabChange("properties")}
          className={`flex-1 py-3 px-4 text-sm font-medium transition ${
            activeTab === "properties"
              ? "bg-primary text-primary-foreground"
              : "text-muted-foreground hover:text-foreground"
          }`}
        >
          Properties
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {activeTab === "media" ? (
          <div className="space-y-4">
            <button
              onClick={onUploadClick}
              className="w-full bg-primary text-primary-foreground py-2 rounded-lg font-medium hover:opacity-90 transition"
            >
              Upload Clips
            </button>

            {/* Thumbnails Grid */}
            <div className="grid grid-cols-2 gap-3">
              {clips.map((clip) => (
                <div
                  key={clip.id}
                  draggable
                  onDragStart={onDragStart(clip)}
                  className="aspect-square rounded border border-border bg-muted cursor-move hover:border-primary transition"
                >
                  <img
                    src={clip.thumbnail || "/placeholder.svg"}
                    alt={clip.name}
                    className="w-full h-full object-cover rounded"
                  />
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            {selectedClip ? (
              <div>
                <h3 className="font-semibold mb-4">Edit Clip</h3>
                <div>
                  <label className="block text-sm font-medium mb-2">Platform Label</label>
                  <input
                    type="text"
                    value={selectedClip.label}
                    onChange={(e) => onUpdateLabel(e.target.value)}
                    placeholder="e.g., Sora, Pika, Runway"
                    className="w-full bg-muted border border-border rounded px-3 py-2 text-foreground text-sm"
                  />
                </div>
              </div>
            ) : (
              <p className="text-muted-foreground text-sm">
                Select a clip from the timeline to edit properties
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
