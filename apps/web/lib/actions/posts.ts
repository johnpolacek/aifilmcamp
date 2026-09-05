"use server";

import { auth, currentUser } from "@clerk/nextjs/server";
import { revalidatePath } from "next/cache";
import type { Post } from "@/lib/posts";
import { deletePost as deletePostFromS3, getPost, getPostsForProject, savePost } from "@/lib/posts";

/**
 * Get the username from the current Clerk user
 */
async function getCurrentUsername(): Promise<string> {
  const user = await currentUser();

  if (!user) {
    throw new Error("User not found");
  }

  // Use Clerk username or email prefix as username
  return user.username || user.emailAddresses[0]?.emailAddress.split("@")[0] || user.id;
}

/**
 * Create a new post
 */
export async function createPost(
  projectId: string,
  data: { title: string; content: string; image?: string }
) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to create a post");
  }

  try {
    const username = await getCurrentUsername();

    // Generate a unique post ID
    const postId = `post-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;

    const now = new Date().toISOString();

    const postData: Post = {
      id: postId,
      projectId,
      title: data.title,
      content: data.content,
      image: data.image,
      createdAt: now,
      updatedAt: now,
      username,
    };

    // Save to S3
    await savePost(postId, postData);

    // Revalidate relevant pages
    revalidatePath("/dashboard");
    revalidatePath(`/dashboard/projects/${projectId}/edit`);

    return { success: true, postId };
  } catch (error) {
    console.error("Error creating post:", error);
    throw new Error("Failed to create post");
  }
}

/**
 * Update an existing post
 */
export async function updatePost(
  postId: string,
  data: { title: string; content: string; image?: string }
) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to update a post");
  }

  try {
    // Check if post exists and user owns it
    const existingPost = await getPost(postId);
    if (!existingPost) {
      throw new Error("Post not found");
    }

    // Check if user owns the post
    const currentUsername = await getCurrentUsername();
    if (existingPost.username !== currentUsername) {
      throw new Error("You don't have permission to update this post");
    }

    // Update post data
    const updatedPost: Post = {
      ...existingPost,
      title: data.title,
      content: data.content,
      image: data.image,
      updatedAt: new Date().toISOString(),
    };

    // Save to S3
    await savePost(postId, updatedPost);

    // Revalidate relevant pages
    revalidatePath("/dashboard");
    revalidatePath(`/dashboard/projects/${existingPost.projectId}/edit`);

    return { success: true };
  } catch (error) {
    console.error("Error updating post:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to update post");
  }
}

/**
 * Delete a post
 */
export async function deletePost(postId: string) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to delete a post");
  }

  try {
    // Check if post exists and user owns it
    const existingPost = await getPost(postId);
    if (!existingPost) {
      throw new Error("Post not found");
    }

    // Check if user owns the post
    const currentUsername = await getCurrentUsername();
    if (existingPost.username !== currentUsername) {
      throw new Error("You don't have permission to delete this post");
    }

    const projectId = existingPost.projectId;

    // Delete from S3
    await deletePostFromS3(postId);

    // Revalidate relevant pages
    revalidatePath("/dashboard");
    revalidatePath(`/dashboard/projects/${projectId}/edit`);

    return { success: true };
  } catch (error) {
    console.error("Error deleting post:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to delete post");
  }
}

/**
 * Get all posts for a project
 */
export async function getProjectPosts(projectId: string): Promise<Post[]> {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to view posts");
  }

  try {
    return await getPostsForProject(projectId);
  } catch (error) {
    console.error("Error getting project posts:", error);
    return [];
  }
}

/**
 * Upload a post image
 */
export async function uploadPostImage(formData: FormData) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to upload a post image");
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

    // Validate file size (max 10MB for post images)
    const maxSize = 10 * 1024 * 1024; // 10MB
    if (file.size > maxSize) {
      throw new Error("Image must be less than 10MB");
    }

    // Convert file to buffer
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    console.log(
      "[uploadPostImage] File info:",
      JSON.stringify(
        {
          fileName: file.name,
          fileSize: file.size,
          fileType: file.type,
          bufferSize: buffer.length,
        },
        null,
        2
      )
    );

    // Generate a unique filename (timestamp + random to avoid collisions)
    const timestamp = Date.now();
    const random = Math.random().toString(36).substring(2, 9);
    const filename = `${timestamp}-${random}.jpg`;
    const key = `posts/${username}/${filename}`;

    console.log(
      "[uploadPostImage] Calling uploadImageFromBuffer with NO thumbnail option (should maintain aspect ratio):",
      JSON.stringify(
        {
          key,
          fileType: file.type,
          options: undefined,
        },
        null,
        2
      )
    );

    // Upload optimized image to S3
    // Don't use thumbnail optimization for post images - maintain original aspect ratio
    const { uploadImageFromBuffer } = await import("@/lib/s3");
    await uploadImageFromBuffer(buffer, key, file.type);

    // Revalidate pages that show post data
    revalidatePath("/dashboard");

    // Return just the filename (not the full key or URL) - URL will be constructed when displaying
    return { success: true, imageFilename: filename };
  } catch (error) {
    console.error("Error uploading post image:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to upload post image");
  }
}
