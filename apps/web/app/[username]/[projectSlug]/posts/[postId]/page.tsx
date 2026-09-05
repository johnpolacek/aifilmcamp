import { redirect } from "next/navigation";
export default async function RetiredPostPage({
  params,
}: {
  params: Promise<{ username: string; projectSlug: string }>;
}) {
  const { username, projectSlug } = await params;
  redirect(`/${username}/${projectSlug}`);
}
