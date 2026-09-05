import type { Metadata } from "next";
import { ResourcesView } from "@/components/views/resources-view";

export const metadata: Metadata = {
  title: "Resources - AI Film Camp",
  description:
    "Everything you need to create stunning AI films. Tools, tutorials, inspiration, and community support.",
};

export default function ResourcesPage() {
  return <ResourcesView />;
}
