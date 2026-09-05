"use server";

import { auth, currentUser } from "@clerk/nextjs/server";
import { revalidatePath } from "next/cache";
import { getUserProfile, saveUserProfile, type UserProfile } from "@/lib/profiles";
import { uploadImageFromUrl } from "@/lib/s3";

/**
 * Get the current user's username from Clerk
 */
async function getCurrentUsername(): Promise<string> {
  const user = await currentUser();

  if (!user) {
    throw new Error("User not found");
  }

  return user.username || user.emailAddresses[0]?.emailAddress.split("@")[0] || user.id;
}

/**
 * Copy Clerk avatar to S3 and return the new S3 URL
 */
async function copyClerkAvatarToS3(clerkImageUrl: string, username: string): Promise<string> {
  try {
    // Generate a unique key for the avatar
    const timestamp = Date.now();
    const key = `avatars/${username}-${timestamp}.jpg`;

    // Upload the optimized image from Clerk URL to S3
    const s3Url = await uploadImageFromUrl(clerkImageUrl, key, { isAvatar: true });
    return s3Url;
  } catch (error) {
    console.error("Error copying Clerk avatar to S3:", error);
    // If copying fails, return the original Clerk URL as fallback
    return clerkImageUrl;
  }
}

/**
 * Update user profile
 */
export async function updateUserProfile(profileData: Partial<UserProfile>) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to update your profile");
  }

  try {
    const username = await getCurrentUsername();
    const user = await currentUser();

    if (!user) {
      throw new Error("User not found");
    }

    // Get existing profile or create new one
    const existingProfile = await getUserProfile(username);

    // Merge with existing data, ensuring required fields
    const updatedProfile: UserProfile = {
      username,
      name:
        profileData.name || (user.firstName && user.lastName)
          ? `${user.firstName} ${user.lastName}`
          : user.username || "User",
      email: profileData.email || user.emailAddresses[0]?.emailAddress || "",
      avatar: profileData.avatar || user.imageUrl,
      about: profileData.about !== undefined ? profileData.about : existingProfile?.about || "",
      links: profileData.links !== undefined ? profileData.links : existingProfile?.links || [],
      updatedAt: new Date().toISOString(),
    };

    // Save to S3
    await saveUserProfile(username, updatedProfile);

    // Revalidate pages that show profile data
    revalidatePath("/dashboard");
    revalidatePath("/dashboard/profile");

    return { success: true };
  } catch (error) {
    console.error("Error updating profile:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to update profile");
  }
}

/**
 * Upload a new profile image
 */
export async function uploadProfileImage(formData: FormData) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to upload a profile image");
  }

  try {
    const username = await getCurrentUsername();
    const file = formData.get("image") as File;

    if (!file) {
      throw new Error("No image file provided");
    }

    // Validate file type
    if (!file.type.startsWith("image/")) {
      throw new Error("File must be an image");
    }

    // Validate file size (max 5MB)
    const maxSize = 5 * 1024 * 1024; // 5MB
    if (file.size > maxSize) {
      throw new Error("Image must be less than 5MB");
    }

    // Convert file to buffer
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    // Generate a unique key for the avatar (always use .jpg since we optimize to JPEG)
    const timestamp = Date.now();
    const key = `avatars/${username}-${timestamp}.jpg`;

    // Upload optimized image to S3
    const { uploadImageFromBuffer } = await import("@/lib/s3");
    const s3Url = await uploadImageFromBuffer(buffer, key, file.type, { isAvatar: true });

    // Update profile with new avatar URL
    const profile = await getUserProfile(username);
    if (profile) {
      profile.avatar = s3Url;
      await saveUserProfile(username, profile);
    }

    // Revalidate pages that show profile data
    revalidatePath("/dashboard");
    revalidatePath("/dashboard/profile");

    return { success: true, avatarUrl: s3Url };
  } catch (error) {
    console.error("Error uploading profile image:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to upload image");
  }
}

/**
 * Get or create user profile for current user
 */
export async function getOrCreateUserProfile(): Promise<UserProfile> {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in");
  }

  try {
    const username = await getCurrentUsername();
    const user = await currentUser();

    if (!user) {
      throw new Error("User not found");
    }

    // Try to get existing profile
    let profile = await getUserProfile(username);

    // If no profile exists, create a default one
    if (!profile) {
      // Copy Clerk avatar to our S3 bucket
      let avatarUrl = user.imageUrl;
      if (user.imageUrl) {
        avatarUrl = await copyClerkAvatarToS3(user.imageUrl, username);
      }

      profile = {
        username,
        name:
          user.firstName && user.lastName
            ? `${user.firstName} ${user.lastName}`
            : user.username || "User",
        email: user.emailAddresses[0]?.emailAddress || "",
        avatar: avatarUrl,
        about: "",
        links: [],
        updatedAt: new Date().toISOString(),
      };

      // Save default profile
      await saveUserProfile(username, profile);
    } else {
      // Just update email from Clerk (in case it changed)
      // Don't update avatar anymore since we want users to control it independently
      profile.email = user.emailAddresses[0]?.emailAddress || profile.email;
    }

    return profile;
  } catch (error) {
    console.error("Error getting/creating profile:", error);
    throw new Error("Failed to load profile");
  }
}
