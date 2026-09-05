"use client";

import { useUser } from "@clerk/nextjs";
import { Edit } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";

interface EditPostButtonProps {
  projectId: string;
  postId: string;
  ownerUsername: string;
}

export function EditPostButton({ projectId, postId, ownerUsername }: EditPostButtonProps) {
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
    <Link href={`/dashboard/projects/${projectId}/posts/${postId}/edit`}>
      <Button variant="outline" size="sm" className="gap-2">
        <Edit className="h-4 w-4" />
        Edit Post
      </Button>
    </Link>
  );
}
