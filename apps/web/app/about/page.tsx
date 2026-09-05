import type { Metadata } from "next";
import { AboutView } from "@/components/views/about-view";

export const metadata: Metadata = {
  title: "About AI Film Camp",
  description:
    "Learn about AI Film Camp - a platform for AI film creators to create, collaborate, and share their work.",
};

export default function AboutPage() {
  return <AboutView />;
}
