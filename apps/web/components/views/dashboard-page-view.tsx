import Link from "next/link";
import { Button } from "@/components/ui/button";
import { DashboardView } from "@/components/views/dashboard-view";
import type { ProjectSummary } from "@/lib/project-basics";

export function DashboardPageView({ projects }: { projects: ProjectSummary[] }) {
  return (
    <main className="min-h-screen bg-background px-4 pt-28 pb-16 lg:px-8">
      <div className="mx-auto max-w-5xl">
        <div className="mb-10 flex flex-wrap items-end justify-between gap-6">
          <div>
            <h1 className="text-4xl font-bold">My projects</h1>
            <p className="mt-3 text-muted-foreground">
              A home for your films. Start a project and share it when you’re ready.
            </p>
          </div>
          <div className="flex items-center gap-4">
            <Link
              className="text-sm text-muted-foreground hover:text-foreground"
              href="/dashboard/profile"
            >
              Edit profile
            </Link>
            <Button asChild>
              <Link href="/dashboard/projects/new">New project</Link>
            </Button>
          </div>
        </div>
        {projects.length ? (
          <DashboardView initialProjects={projects} />
        ) : (
          <div className="rounded-xl border border-dashed px-6 py-20 text-center">
            <h2 className="text-2xl font-semibold">Your next film starts here</h2>
            <p className="mt-3 mb-6 text-muted-foreground">
              All you need is a title. Everything else can come later.
            </p>
            <Button asChild>
              <Link href="/dashboard/projects/new">Create your first project</Link>
            </Button>
          </div>
        )}
      </div>
    </main>
  );
}
