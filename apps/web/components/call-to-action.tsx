import { ArrowRight } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";

export function CallToAction() {
  return (
    <section className="py-20 lg:py-32">
      <div className="container mx-auto px-4 lg:px-8">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="text-3xl lg:text-5xl font-bold mb-6 text-balance text-shadow-[0_0_12px_rgba(0,0,0,0.5)]">Grab the Tools</h2>
          <p className="text-lg text-white mb-10 text-balance leading-relaxed text-shadow-[0_0_12px_rgba(0,0,0,0.5)]">
            Free software for AI filmmakers. Break down your screenplay, get every scene ready to
            generate, and assemble your shots into a finished film.
          </p>
          <Button
            size="lg"
            className="bg-primary text-primary-foreground hover:bg-primary/90 text-base px-8"
            asChild
          >
            <Link href="/tools">
              See the Tools
              <ArrowRight className="ml-2 h-5 w-5" />
            </Link>
          </Button>
        </div>
      </div>
    </section>
  );
}
