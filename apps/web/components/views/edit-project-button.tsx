"use client";

import { useUser } from "@clerk/nextjs";
import { Edit } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";

interface EditProjectButtonProps {
  projectId: string;
  ownerUsername: string;
}

export function EditProjectButton({ projectId, ownerUsername }: EditProjectButtonProps) {
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

    // Debug logging
    console.log(
      "[EditProjectButton] Debug:",
      JSON.stringify(
        {
          currentUsername,
          ownerUsername,
          userUsername: user.username,
          userEmail: user.emailAddresses[0]?.emailAddress,
          userId: user.id,
          isMatch: currentUsername === ownerUsername,
        },
        null,
        2
      )
    );

    // Check if current user is the owner
    setIsOwner(currentUsername === ownerUsername);
  }, [user, isLoaded, ownerUsername]);

  if (!isOwner) {
    return null;
  }

  return (
    <Link href={`/dashboard/projects/${projectId}/edit`}>
      <Button variant="outline" size="sm" className="gap-2">
        <Edit className="h-4 w-4" />
        Edit Project
      </Button>
    </Link>
  );
}
