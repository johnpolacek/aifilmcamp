"use client";

import { ArrowLeft } from "lucide-react";
import Link from "next/link";
import ProjectForm from "@/components/project-form";

export function NewProjectView() {
  return (
    <div className="min-h-screen bg-background pt-24 pb-16">
      <div className="container mx-auto px-4 lg:px-8 max-w-3xl">
        <Link
          href="/dashboard"
          className="inline-flex items-center gap-2 text-primary mb-6 hover:opacity-80 transition-opacity"
        >
          <ArrowLeft className="h-4 w-4" />
          <span className="text-sm font-semibold">Back to Dashboard</span>
        </Link>

        <ProjectForm redirectPath="/dashboard" />
      </div>
    </div>
  );
}
