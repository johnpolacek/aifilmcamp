import {
  BookOpen,
  ExternalLink,
  Film,
  GraduationCap,
  MessageSquare,
  Mic,
  Music,
  Palette,
  Radio,
  Scissors,
  SquarePlay,
  Trophy,
  Users,
} from "lucide-react";
import { Header } from "@/components/header";
import { Card } from "@/components/ui/card";

export function ResourcesView() {
  const resourceCategories = [
    {
      icon: Film,
      title: "Video Generation",
      description: "AI tools for creating video content",
      resources: [
        {
          name: "Google VEO",
          description: "Google's video generation model",
          link: "https://deepmind.google/models/veo/",
        },
        {
          name: "Runway",
          description: "Advanced video generation platform",
          link: "https://runwayml.com/",
        },
        {
          name: "Kling",
          description: "AI video generation platform",
          link: "https://klingai.com/",
        },
        {
          name: "Synthesia",
          description: "AI video generation with avatars",
          link: "https://www.synthesia.io/",
        },
        { name: "Fliki", description: "Text-to-video creation", link: "https://fliki.ai/" },
        {
          name: "OpenAI Sora",
          description: "Cutting-edge video generation model",
          link: "https://openai.com/sora",
        },
        {
          name: "MovieFlow",
          description: "AI filmmaking platform",
          link: "https://www.moviefloai.com/",
        },
        { name: "Pika", description: "Video editing and effects", link: "https://pika.art/" },
        {
          name: "VEED.IO",
          description: "Video editing with AI features",
          link: "https://www.veed.io/",
        },
        {
          name: "Midjourney",
          description: "AI image generation for storyboards",
          link: "https://www.midjourney.com/",
        },
        { name: "Luma AI", description: "AI video generation", link: "https://lumalabs.ai/" },
        {
          name: "Adobe Firefly",
          description: "Adobe's AI image and video tools",
          link: "https://www.adobe.com/products/firefly.html",
        },
        {
          name: "Higgsfield",
          description: "AI video generation platform",
          link: "https://higgsfield.ai/",
        },
        {
          name: "D-ID",
          description: "AI video and avatar creation",
          link: "https://www.d-id.com/",
        },
        {
          name: "Flux Kontext",
          description: "Image and video generation",
          link: "https://fal.ai/flux-kontext",
        },
      ],
    },
    {
      icon: Mic,
      title: "Voice & Audio",
      description: "AI voice generation and dubbing tools",
      resources: [
        {
          name: "ElevenLabs",
          description: "AI voice generation and dubbing",
          link: "https://elevenlabs.io/",
        },
        {
          name: "VEED.IO",
          description: "Audio editing and voice generation",
          link: "https://www.veed.io/",
        },
        {
          name: "Respeecher",
          description: "Voice cloning and dubbing",
          link: "https://www.respeecher.com/",
        },
        {
          name: "Synthesia",
          description: "AI voices for video",
          link: "https://www.synthesia.io/",
        },
        {
          name: "PlayHT",
          description: "Text-to-speech and voice generation",
          link: "https://play.ht/",
        },
      ],
    },
    {
      icon: Music,
      title: "Music & Sound Effects",
      description: "AI-generated music and audio",
      resources: [
        { name: "ElevenLabs", description: "AI music generator", link: "https://elevenlabs.io/" },
      ],
    },
    {
      icon: Scissors,
      title: "Intelligent Editing",
      description: "AI-powered video editing tools",
      resources: [
        {
          name: "Adobe Premiere Pro",
          description: "Professional video editing with AI features",
          link: "https://www.adobe.com/products/premiere.html",
        },
        {
          name: "DaVinci Resolve Studio",
          description: "Professional editing and color grading",
          link: "https://www.blackmagicdesign.com/products/davinciresolve/",
        },
        {
          name: "Descript",
          description: "AI-powered video and audio editing",
          link: "https://www.descript.com/",
        },
      ],
    },
    {
      icon: Palette,
      title: "VFX & Color",
      description: "Visual effects and color grading tools",
      resources: [
        {
          name: "Red Giant",
          description: "VFX and motion graphics plugins",
          link: "https://www.maxon.net/en/red-giant",
        },
        {
          name: "Boris FX",
          description: "Sapphire, Continuum, Mocha Pro, and more",
          link: "https://borisfx.com/",
        },
        { name: "Runway", description: "AI VFX and editing tools", link: "https://runwayml.com/" },
        { name: "ColourLab.ai", description: "AI color grading", link: "https://colourlab.ai/" },
        { name: "Fylm.ai", description: "AI color correction", link: "https://fylm.ai/" },
        {
          name: "Blender",
          description: "Open-source 3D creation suite",
          link: "https://www.blender.org/",
        },
        {
          name: "Unreal Engine",
          description: "Real-time 3D creation for film",
          link: "https://www.unrealengine.com/",
        },
      ],
    },
    {
      icon: GraduationCap,
      title: "Courses & Tutorials",
      description: "Learn AI filmmaking from experts",
      resources: [
        {
          name: "Udemy AI Filmmaking Course",
          description: "Comprehensive AI filmmaking course",
          link: "https://www.udemy.com/course/ai-filmmaking/",
        },
        {
          name: "Alison Filmmaking Masterclass",
          description: "Filmmaking with AI assistance",
          link: "https://alison.com/course/filmmaking-masterclass-with-ai-assistance",
        },
        {
          name: "Ridderfilms Masterclass",
          description: "AI filmmaking masterclass",
          link: "https://masterclass.ridderfilms.com/courses/ai-filmmaking",
        },
        {
          name: "Skillshare AI for Film & Video",
          description: "AI techniques for filmmakers",
          link: "https://www.skillshare.com/en/browse/ai-for-film-video",
        },
      ],
    },
    {
      icon: SquarePlay,
      title: "YouTube Channels",
      description: "Learn from top AI filmmaking creators",
      resources: [
        {
          name: "Matt Wolfe",
          description: "AI tools and tutorials",
          link: "https://www.youtube.com/@mattwolfe",
        },
        {
          name: "Jeff Su",
          description: "Productivity and AI content",
          link: "https://www.youtube.com/@jeffsu",
        },
        {
          name: "Curious Refuge",
          description: "AI filmmaking tutorials and guides",
          link: "https://www.youtube.com/@CuriousRefuge",
        },
      ],
    },
    {
      icon: BookOpen,
      title: "Blogs & Guides",
      description: "Stay updated with AI filmmaking insights",
      resources: [
        {
          name: "Studiovity Blog",
          description: "Production and AI filmmaking tips",
          link: "https://blog.studiovity.com/",
        },
        {
          name: "Shai Creative Blog",
          description: "AI creative tools and techniques",
          link: "https://shaicreative.ai/",
        },
        {
          name: "Drawstory Blog",
          description: "Storytelling and AI content",
          link: "https://drawstory.ai/",
        },
      ],
    },
    {
      icon: MessageSquare,
      title: "Community Forums",
      description: "Connect with other AI filmmakers",
      resources: [
        {
          name: "AI Filmmaking Forum",
          description: "AI on the Lot community",
          link: "https://community.aionthelot.com/",
        },
        {
          name: "AI Forum X",
          description: "Beginner-friendly AI discussions",
          link: "https://xenforo.com/community/threads/ai-forum-x-beginner-friendly-ai-discussions-about-ai-tools-more.228525/",
        },
      ],
    },
    {
      icon: Radio,
      title: "Subreddits",
      description: "Reddit communities for AI filmmakers",
      resources: [
        {
          name: "r/aivideo",
          description: "AI video generation",
          link: "https://www.reddit.com/r/aivideo/",
        },
        {
          name: "r/Filmmakers",
          description: "General filmmaking community",
          link: "https://www.reddit.com/r/Filmmakers/",
        },
        {
          name: "r/Screenwriting",
          description: "Screenwriting community",
          link: "https://www.reddit.com/r/Screenwriting/",
        },
        {
          name: "r/editing",
          description: "Video editing discussions",
          link: "https://www.reddit.com/r/editing/",
        },
        {
          name: "r/StableDiffusion",
          description: "AI image generation",
          link: "https://www.reddit.com/r/StableDiffusion/",
        },
      ],
    },
    {
      icon: Users,
      title: "Discord Servers",
      description: "Join AI filmmaking communities",
      resources: [
        {
          name: "Midjourney",
          description: "AI image generation community",
          link: "http://discord.gg/midjourney",
        },
        {
          name: "Runway",
          description: "Video generation community",
          link: "https://discord.gg/runwayml",
        },
        {
          name: "OpenAI",
          description: "OpenAI community server",
          link: "https://discord.gg/openai",
        },
        {
          name: "BlueWillow AI",
          description: "AI art community",
          link: "https://discord.gg/bluewillow",
        },
        {
          name: "Civitai",
          description: "AI model sharing community",
          link: "https://discord.com/invite/civitai",
        },
        {
          name: "AI Art",
          description: "General AI art community",
          link: "https://discord.com/invite/ai-art-1016879474928795718",
        },
      ],
    },
    {
      icon: Trophy,
      title: "Case Studies & Festivals",
      description: "Inspiring examples and AI film festivals",
      resources: [
        {
          name: "Waymark",
          description: "Producers of 'The Frost' AI film",
          link: "https://waymark.com/",
        },
        {
          name: "Reply AI Film Festival",
          description: "AI-fueled short movies festival",
          link: "https://www.reply.com/en/artificial-intelligence/ai-fueled-short-movies",
        },
      ],
    },
  ];

  return (
    <main className="min-h-screen">
      <Header />

      {/* Hero Section */}
      <section className="pt-32 pb-20 lg:pt-40 lg:pb-32 bg-linear-to-b from-background to-muted/30">
        <div className="container mx-auto px-4 lg:px-8">
          <div className="max-w-3xl mx-auto text-center">
            <h1 className="text-4xl lg:text-6xl font-bold mb-6 text-balance">
              Resources for AI Filmmakers
            </h1>
            <p className="text-lg lg:text-xl text-muted-foreground text-balance">
              Everything you need to create stunning AI films. Tools, tutorials, inspiration, and
              community support.
            </p>
          </div>
        </div>
      </section>

      {/* Resource Categories */}
      <section className="pb-20 lg:pbx-32">
        <div className="container mx-auto px-4 lg:px-8">
          <div className="grid gap-16">
            {resourceCategories.map((category) => {
              const Icon = category.icon;
              return (
                <div key={category.title}>
                  <div className="flex items-center gap-3 mb-8">
                    <div className="w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center">
                      <Icon className="h-6 w-6 text-primary" />
                    </div>
                    <div>
                      <h2 className="text-2xl lg:text-3xl font-bold text-balance">
                        {category.title}
                      </h2>
                      <p className="text-muted-foreground">{category.description}</p>
                    </div>
                  </div>

                  <div className="grid md:grid-cols-2 gap-4">
                    {category.resources.map((resource) => (
                      <a
                        key={resource.name}
                        href={resource.link}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="block"
                      >
                        <Card className="p-6 bg-card border-border hover:border-primary/50 transition-all group cursor-pointer">
                          <div className="flex items-start justify-between gap-4">
                            <div className="flex-1">
                              <h3 className="text-lg font-semibold mb-2 text-balance group-hover:text-primary transition-colors">
                                {resource.name}
                              </h3>
                              <p className="text-sm text-muted-foreground leading-relaxed">
                                {resource.description}
                              </p>
                            </div>
                            <ExternalLink className="h-5 w-5 text-muted-foreground group-hover:text-primary transition-colors shrink-0" />
                          </div>
                        </Card>
                      </a>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </section>
    </main>
  );
}
