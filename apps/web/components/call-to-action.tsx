import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";

export function CallToAction() {
  return (
    <section className="py-20 lg:py-32">
      <div className="container mx-auto px-4 lg:px-8">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="text-3xl lg:text-5xl font-bold mb-6 text-balance">
            Ready to Share Your Vision?
          </h2>
          <p className="text-lg text-muted-foreground mb-10 text-pretty leading-relaxed">
            Join hundreds of AI film creators who are pushing the boundaries of storytelling. Start
            sharing your projects today.
          </p>
          <Button
            size="lg"
            className="bg-primary text-primary-foreground hover:bg-primary/90 text-base px-8"
          >
            Join the Community
            <ArrowRight className="ml-2 h-5 w-5" />
          </Button>
        </div>
      </div>
    </section>
  );
}
