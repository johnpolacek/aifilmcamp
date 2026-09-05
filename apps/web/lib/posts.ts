import { getObjectFromS3, listObjectsInS3, putObjectToS3 } from "./s3";

const POSTS_PREFIX = "posts/";

export interface Post {
  id: string;
  projectId: string;
  title: string;
  content: string;
  image?: string;
  createdAt: string;
  updatedAt?: string;
  username?: string;
}

/**
 * Get a post by ID
 */
export async function getPost(postId: string): Promise<Post | null> {
  try {
    const key = `${POSTS_PREFIX}${postId}.json`;
    const data = await getObjectFromS3(key);

    if (!data) {
      return null;
    }

    return JSON.parse(data) as Post;
  } catch (error) {
    console.error("Error getting post:", error);
    return null;
  }
}

/**
 * Save a post (create or update)
 */
export async function savePost(postId: string, postData: Post): Promise<void> {
  try {
    const key = `${POSTS_PREFIX}${postId}.json`;
    const body = JSON.stringify(postData, null, 2);

    await putObjectToS3(key, body);
  } catch (error) {
    console.error("Error saving post:", error);
    throw error;
  }
}

/**
 * List all post IDs for a project
 */
export async function listPostIdsForProject(projectId: string): Promise<string[]> {
  try {
    const posts = await getPostsForProject(projectId);
    return posts.map((post) => post.id);
  } catch (error) {
    console.error("Error listing posts:", error);
    return [];
  }
}

/**
 * Get posts for multiple projects at once
 */
export async function getPostsForProjects(projectIds: string[]): Promise<Record<string, Post[]>> {
  try {
    const keys = await listObjectsInS3(POSTS_PREFIX);
    const postsByProject: Record<string, Post[]> = {};

    // Initialize empty arrays for all projects
    projectIds.forEach((id) => {
      postsByProject[id] = [];
    });

    await Promise.all(
      keys
        .filter((key) => key.endsWith(".json"))
        .map(async (key) => {
          try {
            const data = await getObjectFromS3(key);
            if (!data) return;
            const post = JSON.parse(data) as Post;
            if (projectIds.includes(post.projectId)) {
              if (!postsByProject[post.projectId]) {
                postsByProject[post.projectId] = [];
              }
              postsByProject[post.projectId].push(post);
            }
          } catch (error) {
            console.error(`Error reading post from ${key}:`, error);
          }
        })
    );

    // Sort posts by createdAt descending (newest first) for each project
    Object.keys(postsByProject).forEach((projectId) => {
      postsByProject[projectId].sort(
        (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
      );
    });

    return postsByProject;
  } catch (error) {
    console.error("Error getting posts for projects:", error);
    return {};
  }
}

/**
 * Get all posts for a project
 */
export async function getPostsForProject(projectId: string): Promise<Post[]> {
  try {
    const keys = await listObjectsInS3(POSTS_PREFIX);
    const posts: Post[] = [];

    await Promise.all(
      keys
        .filter((key) => key.endsWith(".json"))
        .map(async (key) => {
          try {
            const data = await getObjectFromS3(key);
            if (!data) return;
            const post = JSON.parse(data) as Post;
            if (post.projectId === projectId) {
              posts.push(post);
            }
          } catch (error) {
            console.error(`Error reading post from ${key}:`, error);
          }
        })
    );

    // Sort by createdAt descending (newest first)
    return posts.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
  } catch (error) {
    console.error("Error getting posts for project:", error);
    return [];
  }
}

/**
 * Delete a post
 */
export async function deletePost(postId: string): Promise<void> {
  try {
    const { DeleteObjectCommand } = await import("@aws-sdk/client-s3");
    const { s3Client, BUCKET_NAME } = await import("./s3");

    const key = `${POSTS_PREFIX}${postId}.json`;
    const command = new DeleteObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    await s3Client.send(command);
  } catch (error) {
    console.error("Error deleting post:", error);
    throw error;
  }
}
