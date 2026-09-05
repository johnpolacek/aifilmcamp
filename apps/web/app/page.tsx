import type { Metadata } from "next";
import { HomeView } from "@/components/views/home-view";

export const metadata: Metadata = {
  title: "AI Film Camp - Community for AI Filmmakers",
  description:
    "Join a community of AI filmmakers sharing work, tips, and techniques. Collaborate, learn, and showcase your AI film projects.",
};

export default function Home() {
  return <HomeView />;
}
