import type { ProjectFormData } from "@/components/project-form";
import { exportPostAsHTML } from "./export-posts";
import type { Post } from "./posts";
import type { UserProfile } from "./profiles";

/**
 * Generate RSS feed XML for a project's posts
 */
export async function generateRSSFeed(
  posts: Post[],
  project: ProjectFormData & { id: string },
  userProfile: UserProfile,
  baseUrl: string
): Promise<string> {
  const projectUrl = `${baseUrl}/${userProfile.username}/${project.slug}`;
  const _rssUrl = `${baseUrl}/api/rss/${userProfile.username}/${project.slug}`;

  // Get project logline for RSS description
  const description = project.logline || `Posts from ${project.title}`;
  const escapedDescription = escapeXml(description);

  // Generate items for each post
  const items = await Promise.all(
    posts.map(async (post) => {
      const postUrl = `${projectUrl}#post-${post.id}`;
      const pubDate = new Date(post.createdAt).toUTCString();

      // Convert markdown to HTML for description
      const htmlContent = await exportPostAsHTML(post);

      // Escape HTML entities
      const escapedTitle = escapeXml(post.title);
      const escapedContent = escapeXml(htmlContent.substring(0, 500)); // Limit description length

      return `    <item>
      <title>${escapedTitle}</title>
      <link>${postUrl}</link>
      <guid isPermaLink="false">${post.id}</guid>
      <pubDate>${pubDate}</pubDate>
      <description>${escapedContent}</description>
      <content:encoded><![CDATA[${htmlContent}]]></content:encoded>
    </item>`;
    })
  );

  const rssFeed = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>${escapeXml(project.title)}</title>
    <link>${projectUrl}</link>
    <description>${escapedDescription}</description>
    <language>en-us</language>
    <lastBuildDate>${new Date().toUTCString()}</lastBuildDate>
    <generator>AI Film Camp</generator>
${items.join("\n")}
  </channel>
</rss>`;

  return rssFeed;
}

/**
 * Escape XML special characters
 */
function escapeXml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}
