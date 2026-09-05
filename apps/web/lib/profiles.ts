import { getObjectFromS3, putObjectToS3 } from "./s3";

const PROFILES_PREFIX = "profiles/";

export interface UserProfileLink {
  text: string;
  url: string;
}

export interface UserProfile {
  username: string;
  name: string;
  email: string;
  avatar?: string;
  about?: string;
  links: UserProfileLink[];
  updatedAt: string;
}

/**
 * Get a user profile by username
 */
export async function getUserProfile(username: string): Promise<UserProfile | null> {
  try {
    const key = `${PROFILES_PREFIX}${username}.json`;
    const data = await getObjectFromS3(key);

    if (!data) {
      return null;
    }

    return JSON.parse(data) as UserProfile;
  } catch (error) {
    console.error("Error getting user profile:", error);
    return null;
  }
}

/**
 * Save a user profile (create or update)
 */
export async function saveUserProfile(username: string, profileData: UserProfile): Promise<void> {
  try {
    const key = `${PROFILES_PREFIX}${username}.json`;

    // Add/update timestamp
    profileData.updatedAt = new Date().toISOString();

    const body = JSON.stringify(profileData, null, 2);
    await putObjectToS3(key, body);
  } catch (error) {
    console.error("Error saving user profile:", error);
    throw error;
  }
}

/**
 * Create a default profile from Clerk user data
 */
export function createDefaultProfile(
  username: string,
  name: string,
  email: string,
  avatar?: string
): UserProfile {
  return {
    username,
    name,
    email,
    avatar,
    about: "",
    links: [],
    updatedAt: new Date().toISOString(),
  };
}
