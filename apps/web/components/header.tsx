"use client";

import { ClerkLoading, Show, SignInButton, SignUpButton, UserButton } from "@clerk/nextjs";
import Link from "next/link";
import { Logo } from "@/components/logo";
import { Button } from "@/components/ui/button";

export function Header() {
  return (
    <header className="fixed top-0 left-0 right-0 z-50 border-b border-border/40 bg-background/80 backdrop-blur-lg">
      <div className="container mx-auto px-4 lg:px-8">
        <div className="flex h-16 items-center justify-between">
          <Link href="/" className="flex items-center gap-2 text-xl font-bold">
            <Logo />
            <span className="text-balance">AI Film Camp</span>
          </Link>

          <nav className="hidden md:flex items-center gap-6">
            <Link
              href="/learn"
              className="text-sm text-muted-foreground hover:text-foreground transition-colors"
            >
              Learn
            </Link>
            <Link
              href="/films"
              className="text-sm text-muted-foreground hover:text-foreground transition-colors"
            >
              Films
            </Link>
            <Link
              href="/community"
              className="text-sm text-muted-foreground hover:text-foreground transition-colors"
            >
              Community
            </Link>
          </nav>

          <div className="flex items-center gap-3">
            <ClerkLoading>
              <div className="flex items-center gap-3" aria-hidden="true">
                <span className="hidden sm:inline-flex items-center justify-center h-8 px-3 text-sm font-medium invisible">
                  Dashboard
                </span>
                <span className="h-7 w-7 rounded-full bg-muted/50 animate-pulse" />
              </div>
            </ClerkLoading>
            <Show when="signed-in">
              <div className="flex items-center gap-3" suppressHydrationWarning>
                <Link
                  href="/dashboard"
                  className="hidden sm:inline-flex items-center justify-center gap-1 whitespace-nowrap rounded-md text-sm font-medium transition-all h-8 px-3 hover:bg-primary/20 hover:text-white"
                >
                  Dashboard
                </Link>
                <span className="flex h-7 w-7 items-center justify-center">
                  <UserButton />
                </span>
              </div>
            </Show>
            <Show when="signed-out">
              <div className="flex items-center gap-2" suppressHydrationWarning>
                <SignInButton mode="modal">
                  <Button
                    variant="outline"
                    className="bg-transparent! border-primary/80! hover:border-primary/90! hover:text-white! hover:bg-primary/20!"
                    size="sm"
                  >
                    Sign In
                  </Button>
                </SignInButton>
                <SignUpButton mode="modal">
                  <Button size="sm" className="bg-primary text-white hover:text-white">
                    Join
                  </Button>
                </SignUpButton>
              </div>
            </Show>
          </div>
        </div>
      </div>
    </header>
  );
}
