import { Heart, MessageCircle, Play } from "lucide-react";
import Image from "next/image";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { ImagePlaceholder } from "@/components/ui/image-placeholder";

const projects = [
  {
    id: 1,
    title: "Neon Dreams",
    creator: "Sarah Chen",
    thumbnail: "/cyberpunk-neon-city-cinematic.jpg",
    status: "In Progress",
    likes: 234,
    comments: 45,
    tags: ["Sci-Fi", "Cyberpunk", "Experimental"],
  },
  {
    id: 2,
    title: "The Last Garden",
    creator: "Marcus Rivera",
    thumbnail: "/lush-garden-nature-cinematic-film.jpg",
    status: "Week 3",
    likes: 189,
    comments: 32,
    tags: ["Nature", "Documentary", "Drama"],
  },
  {
    id: 3,
    title: "Quantum Echoes",
    creator: "Aisha Patel",
    thumbnail: "/abstract-quantum-space-cinematic.jpg",
    status: "Pre-Production",
    likes: 312,
    comments: 67,
    tags: ["Abstract", "Sci-Fi", "Thriller"],
  },
];

export function FeaturedProjects() {
  return (
    <section id="projects" className="py-20 lg:py-32">
      <div className="container mx-auto px-4 lg:px-8">
        <div className="text-center mb-16">
          <h2 className="text-3xl lg:text-5xl font-bold mb-4 text-balance">Featured Projects</h2>
          <p className="text-lg text-muted-foreground text-pretty max-w-2xl mx-auto">
            Discover what our community is creating right now
          </p>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6 lg:gap-8">
          {projects.map((project) => (
            <Card
              key={project.id}
              className="group overflow-hidden bg-card border-border hover:border-primary/50 transition-all duration-300"
            >
              <div className="relative aspect-video overflow-hidden">
                {project.thumbnail ? (
                  <Image
                    src={project.thumbnail}
                    alt={project.title}
                    fill
                    className="object-cover group-hover:scale-105 transition-transform duration-300"
                  />
                ) : (
                  <ImagePlaceholder className="h-full" />
                )}
                <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-center justify-center">
                  <div className="w-14 h-14 rounded-full bg-primary/90 flex items-center justify-center">
                    <Play className="h-6 w-6 text-primary-foreground ml-1" />
                  </div>
                </div>
                <Badge className="absolute top-3 right-3 bg-background/90 text-foreground border-border">
                  {project.status}
                </Badge>
              </div>

              <div className="p-5">
                <h3 className="text-xl font-semibold mb-2 text-balance">{project.title}</h3>
                <p className="text-sm text-muted-foreground mb-4">by {project.creator}</p>

                <div className="flex flex-wrap gap-2 mb-4">
                  {project.tags.map((tag) => (
                    <Badge key={tag} variant="secondary" className="text-xs">
                      {tag}
                    </Badge>
                  ))}
                </div>

                <div className="flex items-center gap-4 text-sm text-muted-foreground">
                  <div className="flex items-center gap-1">
                    <Heart className="h-4 w-4" />
                    <span>{project.likes}</span>
                  </div>
                  <div className="flex items-center gap-1">
                    <MessageCircle className="h-4 w-4" />
                    <span>{project.comments}</span>
                  </div>
                </div>
              </div>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}
