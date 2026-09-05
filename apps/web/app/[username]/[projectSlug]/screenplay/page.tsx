import { notFound, redirect } from "next/navigation";
import { isProjectOwner } from "@/lib/project-access";
import { getProjectByUsernameAndSlug } from "@/lib/projects";
export const metadata = { title: "Project - AI Film Camp" };
export default async function LegacyScreenplayPage({
  params,
}: {
  params: Promise<{ username: string; projectSlug: string }>;
}) {
  const { username, projectSlug } = await params;
  const result = await getProjectByUsernameAndSlug(username, projectSlug);
  if (!result) notFound();
  if (await isProjectOwner(result.project.username))
    redirect(`/dashboard/projects/${result.id}/screenplay`);
  if (!result.project.isPublished) notFound();
  redirect(`/${username}/${projectSlug}`);
}
