"use client";

import { Code, Copy, FileText, SquareArrowOutUpRight } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { Post } from "@/lib/posts";

interface PostExportProps {
  post: Post;
  projectTitle?: string;
  authorName?: string;
}

export function PostExport({ post, projectTitle: _projectTitle, authorName }: PostExportProps) {
  const [isExporting, setIsExporting] = useState(false);

  const copyToClipboard = async (text: string) => {
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text);
        return true;
      } else {
        // Fallback for older browsers
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
      console.error("Failed to copy to clipboard:", err);
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

  const handleCopyHTML = async () => {
    setIsExporting(true);
    try {
      // Call API to convert markdown to HTML
      const response = await fetch("/api/export/html", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ markdown: post.content }),
      });
      const { html } = await response.json();

      const success = await copyToClipboard(html);
      if (success) {
        toast.success("HTML copied to clipboard!");
      } else {
        toast.error("Failed to copy to clipboard");
      }
    } catch (error) {
      console.error("Error copying HTML:", error);
      toast.error("Failed to copy HTML");
    } finally {
      setIsExporting(false);
    }
  };

  const handleCopyMarkdown = async () => {
    setIsExporting(true);
    try {
      const success = await copyToClipboard(post.content);
      if (success) {
        toast.success("Markdown copied to clipboard!");
      } else {
        toast.error("Failed to copy to clipboard");
      }
    } catch (error) {
      console.error("Error copying markdown:", error);
      toast.error("Failed to copy markdown");
    } finally {
      setIsExporting(false);
    }
  };

  const handleDownloadHTML = async () => {
    setIsExporting(true);
    try {
      const response = await fetch("/api/export/html", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          markdown: post.content,
          title: post.title,
          author: authorName,
        }),
      });
      const { html } = await response.json();

      const filename = `${post.title.replace(/[^a-z0-9]/gi, "_").toLowerCase()}.html`;
      downloadFile(html, filename, "text/html");
      toast.success("HTML file downloaded!");
    } catch (error) {
      console.error("Error downloading HTML:", error);
      toast.error("Failed to download HTML");
    } finally {
      setIsExporting(false);
    }
  };

  const handleDownloadMarkdown = () => {
    setIsExporting(true);
    try {
      const filename = `${post.title.replace(/[^a-z0-9]/gi, "_").toLowerCase()}.md`;
      downloadFile(post.content, filename, "text/markdown");
      toast.success("Markdown file downloaded!");
    } catch (error) {
      console.error("Error downloading markdown:", error);
      toast.error("Failed to download markdown");
    } finally {
      setIsExporting(false);
    }
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" disabled={isExporting}>
          <SquareArrowOutUpRight className="h-4 w-4 mr-2" />
          Export
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={handleCopyHTML}>
          <Copy className="h-4 w-4 mr-2" />
          Copy HTML
        </DropdownMenuItem>
        <DropdownMenuItem onClick={handleCopyMarkdown}>
          <Copy className="h-4 w-4 mr-2" />
          Copy Markdown
        </DropdownMenuItem>
        <DropdownMenuItem onClick={handleDownloadHTML}>
          <FileText className="h-4 w-4 mr-2" />
          Download HTML
        </DropdownMenuItem>
        <DropdownMenuItem onClick={handleDownloadMarkdown}>
          <Code className="h-4 w-4 mr-2" />
          Download Markdown
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
