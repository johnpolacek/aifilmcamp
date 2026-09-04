interface ProjectSetupModalProps {
  onSelectRatio: (ratio: string) => void;
}

const ASPECT_RATIOS = [
  { ratio: "16:9", label: "Widescreen / YouTube", icon: "📺" },
  { ratio: "9:16", label: "Vertical / TikTok", icon: "📱" },
  { ratio: "1:1", label: "Square / Instagram", icon: "📷" },
];

export default function ProjectSetupModal({ onSelectRatio }: ProjectSetupModalProps) {
  return (
    <div className="fixed inset-0 bg-background flex items-center justify-center dark">
      <div className="max-w-md w-full px-6">
        <h2 className="text-2xl font-bold mb-2">Start Your Project</h2>
        <p className="text-muted-foreground mb-8">Choose Your Video&apos;s Aspect Ratio</p>

        <div className="space-y-4">
          {ASPECT_RATIOS.map(({ ratio, label, icon }) => (
            <button
              key={ratio}
              onClick={() => onSelectRatio(ratio)}
              className="w-full border border-border rounded-lg p-6 hover:bg-muted transition text-left group"
            >
              <div className="text-4xl mb-3 group-hover:scale-110 transition">{icon}</div>
              <div className="font-semibold">{ratio}</div>
              <div className="text-sm text-muted-foreground">{label}</div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
