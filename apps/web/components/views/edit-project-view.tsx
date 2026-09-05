import { ArrowLeft, Plus } from "lucide-react";
import Link from "next/link";
import { PostsList } from "@/components/posts-list";
import type { ProjectFormData } from "@/components/project-form";
import ProjectForm from "@/components/project-form";
import { Button } from "@/components/ui/button";
import type { Post } from "@/lib/posts";

interface EditProjectViewProps {
  projectData: ProjectFormData | null;
  projectId: string;
  posts: Post[];
  username: string;
  projectSlug: string;
}

export function EditProjectView({
  projectData,
  projectId,
  posts,
  username,
  projectSlug,
}: EditProjectViewProps) {
  if (!projectData) {
    return (
      <div className="min-h-screen bg-background pt-24 pb-16">
        <div className="container mx-auto px-4 lg:px-8">
          <Link
            href="/dashboard"
            className="inline-flex items-center gap-2 text-primary mb-6 hover:opacity-80 transition-opacity"
          >
            <ArrowLeft className="h-4 w-4" />
            <span className="text-sm font-semibold">Back to Dashboard</span>
          </Link>
          <div className="text-center py-12">
            <h2 className="text-2xl font-bold mb-2">Project Not Found</h2>
            <p className="text-muted-foreground">
              The project you&apos;re looking for doesn&apos;t exist.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background pt-24 pb-16">
      <div className="container mx-auto px-4 lg:px-8">
        <Link
          href="/dashboard"
          className="inline-flex items-center gap-2 text-primary mb-6 hover:opacity-80 transition-opacity"
        >
          <ArrowLeft className="h-4 w-4" />
          <span className="text-sm font-semibold">Back to Dashboard</span>
        </Link>

        <div className="space-y-12">
          <ProjectForm
            initialData={projectData}
            projectId={projectId}
            isEditing
            redirectPath="/dashboard"
            useGridLayout={true}
          />

          <div className="w-full border-t border-border pt-8">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-2xl font-bold">Project Posts</h2>
              <Link href={`/dashboard/projects/${projectId}/posts/new`}>
                <Button>
                  <Plus className="h-4 w-4 mr-2" />
                  Add New Post
                </Button>
              </Link>
            </div>
            <div className="space-y-4">
              {posts.map((post) => (
                <div
                  key={post.id}
                  className="h-[50vh] rounded-xl border border-border overflow-hidden"
                >
                  <PostsList
                    projectId={projectId}
                    initialPosts={[post]}
                    canEdit={true}
                    username={username}
                    projectSlug={projectSlug}
                    showAddButton={false}
                  />
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
