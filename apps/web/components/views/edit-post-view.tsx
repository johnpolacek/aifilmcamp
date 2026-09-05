"use client";

import { ArrowLeft, Code2, Copy, FileText, MessageSquare, Rss, Share2 } from "lucide-react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { useState } from "react";
import { remark } from "remark";
import remarkGfm from "remark-gfm";
import remarkHtml from "remark-html";
import { toast } from "sonner";
import { PostForm } from "@/components/post-form";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { Post } from "@/lib/posts";

// Dynamically import ThreadView to prevent SSR (avoids hydration errors with Radix UI)
const ThreadView = dynamic(() => import("@/components/thread-view").then((mod) => mod.ThreadView), {
  ssr: false,
});

interface EditPostViewProps {
  projectId: string;
  post: Post | null;
}

// Helper functions for export
const copyToClipboard = async (text: string) => {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return true;
    } else {
      const textArea = document.createElement("textarea");
      textArea.value = text;
      textArea.style.position = "fixed";
      textArea.style.left = "-999999px";
      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();
      try {
        document.execCommand("copy");
        document.body.removeChild(textArea);
        return true;
      } catch (_err) {
        document.body.removeChild(textArea);
        return false;
      }
    }
  } catch (err) {
    console.error(
      "[EditPostView] Failed to copy to clipboard:",
      JSON.stringify(
        {
          error: err instanceof Error ? err.message : String(err),
        },
        null,
        2
      )
    );
    return false;
  }
};

const downloadFile = (content: string, filename: string, mimeType: string) => {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
};

const renderVideoEmbeds = (content: string): string => {
  // Replace [youtube:VIDEO_ID] with HTML embed
  content = content.replace(
    /\[youtube:([^\]]+)\]/g,
    '<div class="video-container"><iframe width="100%" height="315" src="https://www.youtube.com/embed/$1?rel=0&modestbranding=1&iv_load_policy=3" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe></div>'
  );

  // Replace [vimeo:VIDEO_ID] with HTML embed
  content = content.replace(
    /\[vimeo:([^\]]+)\]/g,
    '<div class="video-container"><iframe src="https://player.vimeo.com/video/$1" width="100%" height="315" frameborder="0" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe></div>'
  );

  return content;
};

const convertToHTML = async (markdown: string): Promise<string> => {
  const processedContent = renderVideoEmbeds(markdown);
  try {
    const processor = remark().use(remarkGfm).use(remarkHtml);
    const result = await processor.process(processedContent);
    return result.toString();
  } catch (error) {
    console.error(
      "[EditPostView] Error converting to HTML:",
      JSON.stringify(
        {
          error: error instanceof Error ? error.message : String(error),
          stack: error instanceof Error ? error.stack : undefined,
        },
        null,
        2
      )
    );
    throw error;
  }
};

export function EditPostView({ projectId, post }: EditPostViewProps) {
  const [showThreadView, setShowThreadView] = useState(false);

  const handleCopyMarkdown = async () => {
    if (!post?.content.trim()) {
      toast.error("No content to export");
      return;
    }

    try {
      const success = await copyToClipboard(post.content);
      if (success) {
        toast.success("Markdown copied to clipboard!");
      } else {
        toast.error("Failed to copy to clipboard");
      }
    } catch (error) {
      console.error(
        "[EditPostView] Error copying markdown:",
        JSON.stringify(
          {
            error: error instanceof Error ? error.message : String(error),
          },
          null,
          2
        )
      );
      toast.error("Failed to copy markdown");
    }
  };

  const handleCopyHTML = async () => {
    if (!post?.content.trim()) {
      toast.error("No content to export");
      return;
    }

    try {
      const html = await convertToHTML(post.content);
      const fullHTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>${post.title}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; }
    .video-container { position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden; margin: 20px 0; }
    .video-container iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
  </style>
</head>
<body>
  <h1>${post.title}</h1>
  ${html}
</body>
</html>`;

      const success = await copyToClipboard(fullHTML);
      if (success) {
        toast.success("HTML copied to clipboard!");
      } else {
        toast.error("Failed to copy to clipboard");
      }
    } catch (error) {
      console.error(
        "[EditPostView] Error copying HTML:",
        JSON.stringify(
          {
            error: error instanceof Error ? error.message : String(error),
            stack: error instanceof Error ? error.stack : undefined,
          },
          null,
          2
        )
      );
      toast.error("Failed to convert to HTML");
    }
  };

  const handleDownloadHTML = async () => {
    if (!post?.content.trim()) {
      toast.error("No content to export");
      return;
    }

    try {
      const html = await convertToHTML(post.content);
      const fullHTML = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>${post.title}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; }
    .video-container { position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden; margin: 20px 0; }
    .video-container iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
  </style>
</head>
<body>
  <h1>${post.title}</h1>
  ${html}
</body>
</html>`;

      const filename = `${post.title.replace(/[^a-z0-9]/gi, "_").toLowerCase()}.html`;
      downloadFile(fullHTML, filename, "text/html");
      toast.success("HTML file downloaded!");
    } catch (error) {
      console.error(
        "[EditPostView] Error downloading HTML:",
        JSON.stringify(
          {
            error: error instanceof Error ? error.message : String(error),
            stack: error instanceof Error ? error.stack : undefined,
          },
          null,
          2
        )
      );
      toast.error("Failed to download HTML");
    }
  };

  const handleDownloadMarkdown = () => {
    if (!post?.content.trim()) {
      toast.error("No content to export");
      return;
    }

    try {
      const filename = `${post.title.replace(/[^a-z0-9]/gi, "_").toLowerCase()}.md`;
      downloadFile(post.content, filename, "text/markdown");
      toast.success("Markdown file downloaded!");
    } catch (error) {
      console.error(
        "[EditPostView] Error downloading markdown:",
        JSON.stringify(
          {
            error: error instanceof Error ? error.message : String(error),
          },
          null,
          2
        )
      );
      toast.error("Failed to download markdown");
    }
  };

  const handleExportRSS = async () => {
    if (!post?.content.trim() || !post?.title.trim()) {
      toast.error("Title and content are required for RSS export");
      return;
    }

    try {
      const html = await convertToHTML(post.content);
      const pubDate = new Date().toUTCString();
      const guid = post.id || `post-${Date.now()}`;

      const rssItem = `  <item>
    <title><![CDATA[${post.title}]]></title>
    <description><![CDATA[${html}]]></description>
    <pubDate>${pubDate}</pubDate>
    <guid>${guid}</guid>
  </item>`;

      const success = await copyToClipboard(rssItem);
      if (success) {
        toast.success("RSS item copied to clipboard!");
      } else {
        toast.error("Failed to copy to clipboard");
      }
    } catch (error) {
      console.error(
        "[EditPostView] Error exporting RSS:",
        JSON.stringify(
          {
            error: error instanceof Error ? error.message : String(error),
            stack: error instanceof Error ? error.stack : undefined,
          },
          null,
          2
        )
      );
      toast.error("Failed to export RSS");
    }
  };

  if (!post) {
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
          <div className="text-center py-12">
            <h2 className="text-2xl font-bold mb-2">Post Not Found</h2>
            <p className="text-muted-foreground">
              The post you&apos;re looking for doesn&apos;t exist.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background pt-24 pb-16">
      <div className="container mx-auto px-4 lg:px-8 max-w-3xl">
        <div className="flex items-center justify-between mb-6">
          <Link
            href="/dashboard"
            className="inline-flex items-center gap-2 text-primary hover:opacity-80 transition-opacity"
          >
            <ArrowLeft className="h-4 w-4" />
            <span className="text-sm font-semibold">Back to Dashboard</span>
          </Link>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm" disabled={!post.content.trim()}>
                <Share2 className="h-4 w-4 mr-2" />
                Share
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={() => setShowThreadView(!showThreadView)}>
                <MessageSquare className="h-4 w-4 mr-2" />
                Share as Thread
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={handleCopyMarkdown}>
                <Copy className="h-4 w-4 mr-2" />
                Copy Markdown
              </DropdownMenuItem>
              <DropdownMenuItem onClick={handleCopyHTML}>
                <Copy className="h-4 w-4 mr-2" />
                Copy HTML
              </DropdownMenuItem>
              <DropdownMenuItem onClick={handleExportRSS}>
                <Rss className="h-4 w-4 mr-2" />
                Copy RSS Item
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={handleDownloadMarkdown}>
                <Code2 className="h-4 w-4 mr-2" />
                Download Markdown
              </DropdownMenuItem>
              <DropdownMenuItem onClick={handleDownloadHTML}>
                <FileText className="h-4 w-4 mr-2" />
                Download HTML
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        {showThreadView && (
          <div className="mb-6">
            <ThreadView
              title={post.title}
              content={post.content}
              onClose={() => setShowThreadView(false)}
            />
          </div>
        )}

        <PostForm projectId={projectId} initialPost={post} redirectPath="/dashboard" />
      </div>
    </div>
  );
}
