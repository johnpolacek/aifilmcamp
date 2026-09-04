import { ClerkLoading, Show, SignUpButton } from "@clerk/nextjs";
import { ArrowRight } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";

export function Hero() {
  return (
    <section className="relative py-24 overflow-hidden">
      {/* Background gradient effect */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,var(--tw-gradient-stops))] from-primary/20 via-background to-background" />

      <div className="container mx-auto px-4 lg:px-8 relative">
        <div className="max-w-4xl mx-auto text-center">
          <h1 className="text-5xl lg:text-7xl font-black mb-6 text-balance leading-tight">
            Create. Share. Collaborate.
          </h1>

          <p className="text-xl lg:text-2xl opacity-80 text-shadow-black mb-10 text-pretty max-w-4xl mx-auto leading-relaxed">
            Develop ideas, scripts, reference assets, and prompt-ready scenes in one place. Share
            your process and publish development packages as they take shape.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <ClerkLoading>
              <Button
                size="lg"
                className="bg-primary text-primary-foreground text-base px-8 invisible"
                aria-hidden="true"
                tabIndex={-1}
              >
                Start Creating
                <ArrowRight className="ml-2 h-5 w-5" />
              </Button>
            </ClerkLoading>
            <Show when="signed-in">
              <Button
                size="lg"
                className="bg-primary text-primary-foreground hover:bg-primary/90 text-base px-8"
                asChild
              >
                <Link href="/dashboard">
                  Start Creating
                  <ArrowRight className="ml-2 h-5 w-5" />
                </Link>
              </Button>
            </Show>
            <Show when="signed-out">
              <SignUpButton mode="modal">
                <Button
                  size="lg"
                  className="bg-primary text-primary-foreground hover:bg-primary/90 text-base px-8"
                >
                  Start Creating
                  <ArrowRight className="ml-2 h-5 w-5" />
                </Button>
              </SignUpButton>
            </Show>
            <Button
              size="lg"
              variant="outline"
              className="text-base px-8 bg-black/50! border-primary/80! hover:border-primary/90! hover:text-white! hover:bg-black/70!"
              asChild
            >
              <Link href="/projects">Explore Projects</Link>
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
}
