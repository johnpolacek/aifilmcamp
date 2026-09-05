import { auth } from "@clerk/nextjs/server";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { DashboardPageView } from "@/components/views/dashboard-page-view";
import { getOrCreateUserProfile } from "@/lib/actions/profiles";
import { getProjectsByUsername } from "@/lib/projects";

export const metadata: Metadata = {
  title: "Dashboard - AI Film Camp",
  description: "Your films and projects",
};

export default async function DashboardPage() {
  // Check authentication
  const { userId } = await auth();

  if (!userId) {
    redirect("/signin");
  }

  // Get or create user profile from S3
  const userProfile = await getOrCreateUserProfile();

  // Fetch user's projects
  const projects = await getProjectsByUsername(userProfile.username);

  const summaries = projects.map(
    ({ id, title, logline, thumbnail, filmLink, isPublished, username, slug }) => ({
      id,
      title,
      logline,
      thumbnail,
      filmLink,
      isPublished,
      username,
      slug,
    })
  );
  return <DashboardPageView projects={summaries} />;
}
