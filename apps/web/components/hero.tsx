import { ClerkLoading, Show, SignInButton } from "@clerk/nextjs";
import { ArrowRight } from "lucide-react";
import { GetStartedButton } from "@/components/get-started-button";
import { TransitionLink } from "@/components/motion/transition";
import { Button } from "@/components/ui/button";

export function Hero() {
  return (
    <section data-hero className="relative min-h-screen grid items-center pt-16 overflow-hidden">
      {/* Background glow, transparent so the image shows through the dolly */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,var(--tw-gradient-stops))] from-primary/15 to-transparent to-55%" />

      <div className="container mx-auto px-4 lg:px-8 relative">
        <div data-outro className="max-w-4xl mx-auto text-center">
          <h1 data-headline className="text-5xl lg:text-7xl font-black mb-6 leading-tight">
            Create. Share. Collaborate.
          </h1>

          <div data-hero-actions className="flex flex-col items-center justify-center gap-4">
            <ClerkLoading>
              <GetStartedButton placeholder />
            </ClerkLoading>
            <Show when="signed-in">
              <Button
                size="lg"
                className="h-16 px-12 text-2xl font-bold bg-primary text-white hover:bg-primary/90 hover:text-white"
                asChild
              >
                <TransitionLink href="/dashboard" data-magnetic>
                  <span data-mag className="inline-flex items-center">
                    Start Creating
                    <ArrowRight className="ml-2 h-6 w-6" />
                  </span>
                </TransitionLink>
              </Button>
            </Show>
            <Show when="signed-out">
              <GetStartedButton />
              <SignInButton mode="modal">
                <Button variant="ghost" className="text-muted-foreground hover:text-foreground">
                  Sign In
                </Button>
              </SignInButton>
            </Show>
          </div>
        </div>
      </div>
    </section>
  );
}
