import { Logo } from "@/components/logo";
import { TransitionLink } from "@/components/motion/transition";

export function Footer() {
  return (
    <footer className="border-t border-white/10 bg-muted/30">
      <div className="container mx-auto px-4 lg:px-8 py-12">
        <div className="grid md:grid-cols-4 gap-8 mb-8">
          <div className="md:col-span-2">
            <TransitionLink href="/" className="flex items-center gap-2 text-xl font-bold mb-4">
              <Logo className="h-7 w-7" />
              <span>AI Film Camp</span>
            </TransitionLink>
            <p className="text-sm text-muted-foreground max-w-md leading-relaxed">
              An online community for AI film creators to share, collaborate, and showcase their
              work-in-progress projects.
            </p>
          </div>

          <div>
            <h3 className="font-semibold mb-4">Community</h3>
            <ul className="space-y-2 text-sm text-muted-foreground">
              <li>
                <TransitionLink href="#" className="hover:text-foreground transition-colors">
                  Projects
                </TransitionLink>
              </li>
              <li>
                <TransitionLink href="#" className="hover:text-foreground transition-colors">
                  Creators
                </TransitionLink>
              </li>
              <li>
                <TransitionLink href="#" className="hover:text-foreground transition-colors">
                  Contact
                </TransitionLink>
              </li>
            </ul>
          </div>

          <div>
            <h3 className="font-semibold mb-4">Resources</h3>
            <ul className="space-y-2 text-sm text-muted-foreground">
              <li>
                <TransitionLink
                  href="/community"
                  className="hover:text-foreground transition-colors"
                >
                  Community
                </TransitionLink>
              </li>
              <li>
                <TransitionLink href="#" className="hover:text-foreground transition-colors">
                  Privacy Policy
                </TransitionLink>
              </li>
              <li>
                <TransitionLink href="#" className="hover:text-foreground transition-colors">
                  Terms of Use
                </TransitionLink>
              </li>
            </ul>
          </div>
        </div>

        <div className="pt-8 border-t border-border text-center text-sm text-muted-foreground">
          <p>&copy; 2025 AI Film Camp. All rights reserved.</p>
        </div>
      </div>
    </footer>
  );
}
