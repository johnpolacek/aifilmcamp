import { Logo } from "@/components/logo";

export function AboutView() {
  return (
    <main className="min-h-screen">
      {/* Hero Section */}
      <section className="relative pt-32 pb-20 lg:pt-40 lg:pb-32 overflow-hidden">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,var(--tw-gradient-stops))] from-primary/20 via-background to-background" />

        <div className="container mx-auto px-4 lg:px-8 relative">
          <div className="max-w-4xl mx-auto text-center">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-primary/10 border border-primary/20 text-sm text-primary mb-6">
              <Logo className="h-4 w-4" />
              <span>A Pre-Production Platform for AI Film Creators</span>
            </div>

            <h1 className="text-5xl lg:text-7xl font-bold mb-6 text-balance leading-tight">
              About AI Film Camp
            </h1>

            <p className="text-xl lg:text-2xl text-muted-foreground mb-10 text-balance max-w-2xl mx-auto leading-relaxed">
              AI Film Camp helps creators move from clean-slate concept to screenplay, reference
              assets, and prompt-ready scene plans, then share that development package publicly.
            </p>
          </div>
        </div>
      </section>
    </main>
  );
}
