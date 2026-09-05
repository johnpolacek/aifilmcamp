import { currentUser } from "@clerk/nextjs/server";
import { notFound } from "next/navigation";
import { getProject, getProjectByUsernameAndSlug } from "@/lib/projects";

export async function isProjectOwner(username?: string) {
  const user = await currentUser();
  return (
    !!user &&
    username === (user.username || user.emailAddresses[0]?.emailAddress.split("@")[0] || user.id)
  );
}

export async function getOwnedProject(id: string) {
  const project = await getProject(id);
  if (!project || !(await isProjectOwner(project.username))) notFound();
  return project;
}

export async function getVisibleProject(username: string, slug: string) {
  const result = await getProjectByUsernameAndSlug(username, slug);
  if (!result || (!result.project.isPublished && !(await isProjectOwner(result.project.username))))
    return null;
  return result;
}
