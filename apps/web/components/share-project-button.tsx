"use client";

import { toast } from "sonner";
import { Button } from "@/components/ui/button";

export function ShareProjectButton({ path }: { path: string }) {
  return (
    <Button
      type="button"
      variant="outline"
      size="sm"
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(new URL(path, window.location.origin).href);
          toast.success("Project link copied");
        } catch {
          toast.error("Could not copy the link. Open the project page and copy its address.");
        }
      }}
    >
      Copy link
    </Button>
  );
}
