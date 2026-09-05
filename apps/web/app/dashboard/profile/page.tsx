import { auth } from "@clerk/nextjs/server";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { ProfileView } from "@/components/views/profile-view";
import { getOrCreateUserProfile } from "@/lib/actions/profiles";

export const metadata: Metadata = {
  title: "Edit Profile - AI Film Camp",
  description: "Update your personal information",
};

export default async function EditProfilePage() {
  // Check authentication
  const { userId } = await auth();

  if (!userId) {
    redirect("/signin");
  }

  // Get or create user profile from S3
  const userProfile = await getOrCreateUserProfile();

  // Check if profile completion is required (no about text yet)
  const isRequired = !userProfile.about || userProfile.about.trim() === "";

  return <ProfileView userProfile={userProfile} isRequired={isRequired} />;
}
