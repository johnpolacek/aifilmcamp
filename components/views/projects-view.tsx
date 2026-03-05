import { Film } from "lucide-react";
import { Header } from "@/components/header";

export function ProjectsView() {
  // Placeholder projects data
  const _placeholderProjects = [
    {
      id: "1",
      title: "The Last Algorithm",
      description:
        "A sci-fi short exploring AI consciousness through the eyes of a self-aware algorithm discovering its own mortality.",
      thumbnail: "",
      creator: "filmmaker_xyz",
      status: "Completed",
      duration: "8:45",
      genre: "Sci-Fi",
      tools: [
        { name: "Runway Gen-3", category: "video" as const },
        { name: "Midjourney", category: "image" as const },
        { name: "ElevenLabs", category: "sound" as const },
      ],
    },
    {
      id: "2",
      title: "Memories in Motion",
      description:
        "An experimental documentary blending AI-generated visuals with real family photographs to explore themes of memory and time.",
      thumbnail: "",
      creator: "creative_soul",
      status: "In Progress",
      duration: "12:00",
      genre: "Documentary",
      tools: [
        { name: "Pika Labs", category: "video" as const },
        { name: "Stable Diffusion", category: "image" as const },
      ],
    },
    {
      id: "3",
      title: "Urban Dreams",
      description:
        "A visual poem capturing the essence of city life through AI-generated imagery and soundscapes.",
      thumbnail: "",
      creator: "city_artist",
      status: "Post-Production",
      duration: "5:30",
      genre: "Experimental",
      tools: [
        { name: "Runway Gen-3", category: "video" as const },
        { name: "Suno", category: "sound" as const },
      ],
    },
  ];

  return (
    <main className="min-h-screen">
      <Header />

      {/* Hero Section */}
      <section className="pt-32 lg:pt-40 bg-linear-to-b from-background to-muted/30">
        <div className="container mx-auto px-4 lg:px-8">
          <div className="max-w-3xl mx-auto text-center">
            <h1 className="text-4xl lg:text-6xl font-bold mb-6 text-balance">Community Projects</h1>
            <p className="text-lg lg:text-xl text-muted-foreground text-balance">
              Explore concept-to-prompt AI film development packages from creators around the world.
              Get inspired, learn, and collaborate.
            </p>
          </div>
        </div>
      </section>

      {/* Projects Grid */}
      <section className="py-20">
        <div className="container mx-auto px-4 lg:px-8">
          {/* Empty State / Coming Soon Message */}
          <div className="text-center mt-16">
            <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-primary/10 mb-4">
              <Film className="h-8 w-8 text-primary" />
            </div>
            <h3 className="text-2xl font-bold mb-2">Coming Soon</h3>
            <p className="text-muted-foreground max-w-md mx-auto text-balance">
              Join the community and share your own AI film development package.
            </p>
          </div>
        </div>
      </section>
    </main>
  );
}
