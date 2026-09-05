import { remark } from "remark";
import remarkGfm from "remark-gfm";
import remarkHtml from "remark-html";
import stripMarkdown from "strip-markdown";
import type { Post } from "./posts";

/**
 * Export a post as HTML (server-side)
 */
export async function exportPostAsHTML(post: Post): Promise<string> {
  const processor = remark().use(remarkGfm).use(remarkHtml);
  const result = await processor.process(post.content);
  return result.toString();
}

/**
 * Export a post as formatted HTML document
 */
export async function exportPostAsHTMLDocument(
  post: Post,
  options?: { title?: string; author?: string }
): Promise<string> {
  const htmlContent = await exportPostAsHTML(post);
  const title = options?.title || post.title;
  const author = options?.author || "";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)}</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      line-height: 1.6;
      max-width: 800px;
      margin: 0 auto;
      padding: 20px;
      color: #333;
    }
    h1, h2, h3, h4, h5, h6 {
      margin-top: 1.5em;
      margin-bottom: 0.5em;
    }
    p {
      margin-bottom: 1em;
    }
    code {
      background-color: #f4f4f4;
      padding: 2px 4px;
      border-radius: 3px;
      font-family: monospace;
    }
    pre {
      background-color: #f4f4f4;
      padding: 10px;
      border-radius: 5px;
      overflow-x: auto;
    }
    blockquote {
      border-left: 4px solid #ddd;
      margin-left: 0;
      padding-left: 20px;
      color: #666;
    }
    a {
      color: #0066cc;
    }
  </style>
</head>
<body>
  <article>
    <header>
      <h1>${escapeHtml(title)}</h1>
      ${author ? `<p><em>By ${escapeHtml(author)}</em></p>` : ""}
      <p><small>Published: ${new Date(post.createdAt).toLocaleDateString()}</small></p>
    </header>
    <div>
      ${htmlContent}
    </div>
  </article>
</body>
</html>`;
}

/**
 * Export a post as Markdown
 */
export function exportPostAsMarkdown(post: Post): string {
  return post.content;
}

/**
 * Export a post as plain text (strips markdown)
 */
export async function exportPostAsPlainText(post: Post): Promise<string> {
  const processor = remark().use(stripMarkdown);
  const result = await processor.process(post.content);
  return result.toString();
}

/**
 * Escape HTML entities (server-side safe)
 */
function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
