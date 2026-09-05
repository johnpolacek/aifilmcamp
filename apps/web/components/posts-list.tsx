"use client";

import { useUser } from "@clerk/nextjs";
import { Calendar, Edit, Eye, Plus, X } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { PostContent } from "@/components/post-content";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { OptimizedImage } from "@/components/ui/optimized-image";
import type { Post } from "@/lib/posts";
import { PostExport } from "./post-export";

interface PostsListProps {
  projectId: string;
  initialPosts: Post[];
  canEdit?: boolean;
  projectTitle?: string;
  authorName?: string;
  username?: string;
  projectSlug?: string;
  showAddButton?: boolean; // Control whether to show the Add New Post button
}

export function PostsList({
  projectId,
  initialPosts,
  canEdit = false,
  projectTitle,
  authorName,
  username,
  projectSlug,
  showAddButton = true, // Default to true for backward compatibility
}: PostsListProps) {
  const { user, isLoaded } = useUser();
  const [isOwner, setIsOwner] = useState(false);

  // Check if current user is the owner when username is provided
  useEffect(() => {
    if (!username || !isLoaded) {
      setIsOwner(false);
      return;
    }

    if (!user) {
      setIsOwner(false);
      return;
    }

    // Get current username using the same logic as getCurrentUsername()
    const currentUsername =
      user.username || user.emailAddresses[0]?.emailAddress.split("@")[0] || user.id;

    // Check if current user is the owner
    setIsOwner(currentUsername === username);
  }, [user, isLoaded, username]);

  // Use canEdit prop if provided, otherwise check ownership
  const canEditPosts = canEdit || isOwner;
  const [posts, setPosts] = useState<Post[]>(initialPosts);

  const handleDelete = async (postId: string, title: string) => {
    if (!confirm(`Are you sure you want to delete "${title}"?`)) {
      return;
    }

    const loadingToast = toast.loading(`Deleting "${title}"...`);

    try {
      const { deletePost } = await import("@/lib/actions/posts");
      await deletePost(postId);

      setPosts(posts.filter((p) => p.id !== postId));
      toast.success(`"${title}" deleted successfully!`, { id: loadingToast });
    } catch (error) {
      console.error("Error deleting post:", error);
      const errorMessage = error instanceof Error ? error.message : "Failed to delete post";
      toast.error(errorMessage, { id: loadingToast });
    }
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
  };

  return (
    <div className="space-y-6">
      {canEditPosts && showAddButton && (
        <div>
          <Link href={`/dashboard/projects/${projectId}/posts/new`}>
            <Button>
              <Plus className="h-4 w-4 mr-2" />
              Add New Post
            </Button>
          </Link>
        </div>
      )}

      {posts.length === 0 ? (
        <div className="p-8 text-center">
          <p className="text-muted-foreground">
            No posts yet. {canEditPosts && "Add your first post above!"}
          </p>
        </div>
      ) : (
        <div className="space-y-8">
          {posts.map((post) => (
            <Card key={post.id} className="bg-muted/30 border-border overflow-hidden">
              <CardContent className="px-6">
                <div className="flex items-start justify-between mb-4">
                  <div className="flex-1">
                    <h3 className="text-xl font-bold mb-2">{post.title}</h3>
                    <div className="flex items-center gap-2 text-sm text-muted-foreground">
                      <Calendar className="h-4 w-4" />
                      <span>{formatDate(post.createdAt)}</span>
                      {post.updatedAt && post.updatedAt !== post.createdAt && (
                        <span className="text-xs">(updated {formatDate(post.updatedAt)})</span>
                      )}
                    </div>
                  </div>
                  <div className="flex gap-2 mr-2">
                    {username && projectSlug && (
                      <Link href={`/${username}/${projectSlug}/posts/${post.id}`}>
                        <Button size="sm" variant="outline" className="gap-2">
                          <Eye className="h-4 w-4" /> View
                        </Button>
                      </Link>
                    )}
                    {canEditPosts && (
                      <Link href={`/dashboard/projects/${projectId}/posts/${post.id}/edit`}>
                        <Button size="sm" variant="outline" className="gap-2">
                          <Edit className="h-4 w-4" /> Edit
                        </Button>
                      </Link>
                    )}
                  </div>
                  <PostExport post={post} projectTitle={projectTitle} authorName={authorName} />
                  {canEditPosts && (
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => handleDelete(post.id, post.title)}
                      className="text-destructive hover:text-destructive hover:bg-destructive/10 ml-2"
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  )}
                </div>
                {post.image && post.username && (
                  <div className="mb-4 rounded-md overflow-hidden border border-border">
                    <OptimizedImage
                      type="post"
                      filename={post.image}
                      username={post.username}
                      alt={post.title}
                      width={800}
                      height={400}
                      className="w-full h-auto"
                      objectFit="contain"
                    />
                  </div>
                )}
                <PostContent
                  className={canEditPosts ? "pointer-events-none" : ""}
                  content={post.content}
                />
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
