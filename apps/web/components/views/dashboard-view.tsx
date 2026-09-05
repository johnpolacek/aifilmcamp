"use client";

import { Edit, Eye, X } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { ImagePlaceholder } from "@/components/ui/image-placeholder";
import { OptimizedImage } from "@/components/ui/optimized-image";
import type { ProjectSummary } from "@/lib/project-basics";

interface DashboardViewProps {
  initialProjects: ProjectSummary[];
}

export function DashboardView({ initialProjects }: DashboardViewProps) {
  const [projects, setProjects] = useState<ProjectSummary[]>(initialProjects);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState<Record<string, boolean>>({});
  const [projectToDelete, setProjectToDelete] = useState<{ id: string; title: string } | null>(
    null
  );

  const handleDeleteProject = async (id: string, title: string) => {
    // Show loading toast
    const loadingToast = toast.loading(`Deleting "${title}"...`);

    try {
      // Import and call the Server Action
      const { deleteProject } = await import("@/lib/actions/projects");
      await deleteProject(id);

      // Remove from local state
      setProjects((current) => current.filter((p) => p.id !== id));

      // Close dialog
      setDeleteDialogOpen({ ...deleteDialogOpen, [id]: false });
      setProjectToDelete(null);

      // Show success toast
      toast.success(`"${title}" deleted successfully!`, {
        id: loadingToast,
      });
    } catch (error) {
      console.error("Error deleting project:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Failed to delete project. Please try again.";

      // Show error toast
      toast.error(errorMessage, {
        id: loadingToast,
      });
    }
  };

  const openDeleteDialog = (id: string, title: string) => {
    setProjectToDelete({ id, title });
    setDeleteDialogOpen({ ...deleteDialogOpen, [id]: true });
  };

  const closeDeleteDialog = (id: string) => {
    setDeleteDialogOpen({ ...deleteDialogOpen, [id]: false });
    setProjectToDelete(null);
  };

  return (
    <div className="grid gap-6">
      {projects.map((project) => {
        return (
          <Card key={project.id} className="bg-muted/30 border-border overflow-hidden">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 p-4">
              {/* Left: Image */}
              <div className="relative aspect-video">
                <OptimizedImage
                  placeholder={<ImagePlaceholder text="" className="absolute inset-0" />}
                  type="thumbnail"
                  filename={project.thumbnail}
                  username={project.username}
                  alt={project.title}
                  fill
                  className="rounded"
                  objectFit="cover"
                  sizes="(max-width: 768px) 100vw, 50vw"
                />
              </div>

              {/* Right: Project Info */}
              <div className="flex flex-col justify-between">
                <div>
                  <div className="flex items-center justify-between mb-2">
                    <h3 className="text-xl font-bold">{project.title}</h3>
                  </div>
                  {project.logline && (
                    <p className="text-sm text-muted-foreground mb-4 leading-relaxed">
                      {project.logline}
                    </p>
                  )}
                  <p className="text-sm text-muted-foreground">
                    {project.isPublished ? "Public" : "Private"}
                  </p>
                </div>
                <div className="flex flex-wrap justify-between gap-2 mt-4">
                  <div className="flex gap-2">
                    {project.username && project.slug && (
                      <Button size="sm" variant="outline" asChild>
                        <Link href={`/${project.username}/${project.slug}`}>
                          <Eye className="h-4 w-4 mr-2" />
                          {project.isPublished ? "View" : "Preview"}
                        </Link>
                      </Button>
                    )}
                    <Button size="sm" variant="outline" asChild>
                      <Link href={`/dashboard/projects/${project.id}/edit`}>
                        <Edit className="h-4 w-4 mr-2" />
                        Edit
                      </Link>
                    </Button>
                  </div>
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      variant="ghost"
                      aria-label={`Delete ${project.title}`}
                      onClick={() => openDeleteDialog(project.id, project.title)}
                      className="text-destructive hover:text-destructive hover:bg-destructive/10"
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </div>
            </div>

            {/* Delete Confirmation Dialog */}
            <Dialog
              open={deleteDialogOpen[project.id] || false}
              onOpenChange={(open) => !open && closeDeleteDialog(project.id)}
            >
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Delete Project</DialogTitle>
                  <DialogDescription>
                    Are you sure you want to delete &ldquo;{project.title}&rdquo;? This action
                    cannot be undone.
                  </DialogDescription>
                </DialogHeader>
                <DialogFooter>
                  <Button variant="outline" onClick={() => closeDeleteDialog(project.id)}>
                    Cancel
                  </Button>
                  <Button
                    variant="destructive"
                    onClick={() =>
                      projectToDelete &&
                      handleDeleteProject(projectToDelete.id, projectToDelete.title)
                    }
                  >
                    Delete
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </Card>
        );
      })}
    </div>
  );
}
