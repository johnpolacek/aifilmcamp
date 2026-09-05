import { ClerkLoading, Show, SignInButton, SignUpButton } from "@clerk/nextjs";
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

          <div className="flex flex-col items-center justify-center gap-4">
            <ClerkLoading>
              <Button
                size="lg"
                className="h-16 px-12 text-2xl font-bold invisible"
                aria-hidden="true"
                tabIndex={-1}
              >
                Join The Community
              </Button>
            </ClerkLoading>
            <Show when="signed-in">
              <Button
                size="lg"
                className="h-16 px-12 text-2xl font-bold bg-primary text-white hover:bg-primary/90 hover:text-white"
                asChild
              >
                <Link href="/dashboard">
                  Start Creating
                  <ArrowRight className="ml-2 h-6 w-6" />
                </Link>
              </Button>
            </Show>
            <Show when="signed-out">
              <SignUpButton mode="modal">
                <Button
                  size="lg"
                  className="h-16 px-12 text-2xl font-bold bg-primary text-white hover:bg-primary/90 hover:text-white"
                >
                  Join The Community
                </Button>
              </SignUpButton>
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
