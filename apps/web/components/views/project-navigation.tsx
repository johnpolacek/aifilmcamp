"use client";

import { useUser } from "@clerk/nextjs";
import { ArrowLeft, Edit } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";

interface ProjectNavigationProps {
  projectId: string;
  ownerUsername: string;
}

export function ProjectNavigation({ projectId, ownerUsername }: ProjectNavigationProps) {
  const { user, isLoaded } = useUser();
  const [isOwner, setIsOwner] = useState(false);

  useEffect(() => {
    if (!isLoaded || !user) {
      setIsOwner(false);
      return;
    }

    // Get current username using the same logic as getCurrentUsername()
    const currentUsername =
      user.username || user.emailAddresses[0]?.emailAddress.split("@")[0] || user.id;

    // Check if current user is the owner
    setIsOwner(currentUsername === ownerUsername);
  }, [user, isLoaded, ownerUsername]);

  if (!isOwner) {
    return null;
  }

  return (
    <div className="absolute top-20 left-4 right-4 z-10 flex items-center justify-between gap-4">
      <Link
        href="/dashboard"
        className="inline-flex items-center gap-2 bg-background/90 backdrop-blur-sm px-3 py-2 md:px-4 rounded-md text-primary hover:bg-background transition-colors border border-border/50"
      >
        <ArrowLeft className="h-4 w-4" />
        <span className="text-sm font-semibold hidden sm:inline">Back to Dashboard</span>
        <span className="text-sm font-semibold sm:hidden">Back</span>
      </Link>
      <Link href={`/dashboard/projects/${projectId}/edit`}>
        <Button size="sm" className="gap-2">
          <Edit className="h-4 w-4" />
          <span className="hidden sm:inline">Edit Project</span>
          <span className="sm:hidden">Edit</span>
        </Button>
      </Link>
    </div>
  );
}
