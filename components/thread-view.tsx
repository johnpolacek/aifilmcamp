"use client";

import { Check, Copy, X } from "lucide-react";
import Image from "next/image";
import { useState } from "react";
import { remark } from "remark";
import remarkGfm from "remark-gfm";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface ThreadViewProps {
  title: string;
  content: string;
  onClose?: () => void;
}

interface ContentItem {
  type: "text" | "image";
  text?: string;
  image?: { url: string; alt: string };
  youtubeUrls?: string[]; // YouTube URLs extracted from this text item
}

interface ChunkWithImages {
  text: string;
  images: Array<{ url: string; alt: string }>;
  youtubeUrls: string[];
}

/**
 * Extracts content items (text and images) in order, preserving their relationships
 */
function extractContentItems(markdown: string): ContentItem[] {
  console.log(
    "[ThreadView] Extracting content items from markdown:",
    JSON.stringify(
      {
        markdownLength: markdown.length,
        markdownPreview: markdown.substring(0, 200),
        hasYoutubeRef: /\[youtube:[^\]]+\]/.test(markdown),
        youtubeMatches: markdown.match(/\[youtube:[^\]]+\]/g),
      },
      null,
      2
    )
  );

  const processor = remark().use(remarkGfm);
  const ast = processor.parse(markdown);

  const items: ContentItem[] = [];

  // Extract text from AST nodes, tracking images
  function extractContent(node: unknown): string {
    if (typeof node === "string") {
      return node;
    }

    if (!node || typeof node !== "object") {
      return "";
    }

    const astNode = node as Record<string, unknown>;

    // Handle text nodes
    if (astNode.type === "text") {
      return (astNode.value as string) || "";
    }

    // Handle image nodes - extract and add to items
    if (astNode.type === "image" || astNode.type === "imageReference") {
      const url = (astNode.url as string) || "";
      const alt = (astNode.alt as string) || "";
      if (url) {
        items.push({
          type: "image",
          image: { url, alt },
        });
      }
      return ""; // Images don't contribute to text
    }

    // Handle links - include both text and URL
    if (astNode.type === "link" || astNode.type === "linkReference") {
      const children = (astNode.children as unknown[]) || [];
      const text = children.map(extractContent).join("") || "";
      const url = (astNode.url as string) || "";
      return url ? `${text} ${url}` : text;
    }

    // Handle code blocks and inline code
    if (astNode.type === "code") {
      return (astNode.value as string) || "";
    }

    // Handle line breaks
    if (astNode.type === "break") {
      return " ";
    }

    // Handle list items - preserve bullet point format
    if (astNode.type === "listItem") {
      const children = (astNode.children as unknown[]) || [];
      const content = children.map(extractContent).join("") || "";
      // Return content with bullet point preserved
      return `- ${content}`;
    }

    // Handle paragraphs
    if (astNode.type === "paragraph") {
      const children = (astNode.children as unknown[]) || [];
      const content = children.map(extractContent).join("") || "";
      return content;
    }

    // Handle headings
    if (typeof astNode.type === "string" && astNode.type.startsWith("heading")) {
      const children = (astNode.children as unknown[]) || [];
      const content = children.map(extractContent).join("") || "";
      return content;
    }

    // Handle lists - preserve list structure with line breaks
    if (astNode.type === "list") {
      const children = (astNode.children as unknown[]) || [];
      // Join list items with newlines to preserve structure
      return children.map(extractContent).join("\n") || "";
    }

    // Handle blockquotes
    if (astNode.type === "blockquote") {
      const children = (astNode.children as unknown[]) || [];
      return children.map(extractContent).join(" ") || "";
    }

    // Handle horizontal rules
    if (astNode.type === "thematicBreak") {
      return " ";
    }

    // For other nodes with children, recursively extract
    if (astNode.children && Array.isArray(astNode.children)) {
      return (astNode.children as unknown[]).map(extractContent).join("");
    }

    return "";
  }

  // Process the AST and build content items
  function processNode(node: unknown): void {
    if (!node || typeof node !== "object") {
      return;
    }

    const astNode = node as Record<string, unknown>;

    // Process top-level nodes (paragraphs, headings, images, etc.)
    if (astNode.type === "root" && astNode.children && Array.isArray(astNode.children)) {
      for (const child of astNode.children as unknown[]) {
        const childNode = child as Record<string, unknown>;

        // Check if this is an image
        if (childNode.type === "image" || childNode.type === "imageReference") {
          const url = (childNode.url as string) || "";
          const alt = (childNode.alt as string) || "";
          if (url) {
            items.push({
              type: "image",
              image: { url, alt },
            });
          }
        } else {
          // Extract text from this node
          const text = extractContent(child);
          if (text.trim()) {
            items.push({
              type: "text",
              text: text.trim(),
            });
          }
        }
      }
    }
  }

  processNode(ast);

  // Normalize whitespace in text items and extract YouTube references
  const processedItems = items
    .map((item) => {
      if (item.type === "text" && item.text) {
        const youtubeUrls: string[] = [];

        // Extract YouTube references [youtube:VIDEO_ID] and convert to URLs
        const youtubeRegex = /\[youtube:([^\]]+)\]/g;
        let match: RegExpExecArray | null;

        // Reset regex
        youtubeRegex.lastIndex = 0;
        match = youtubeRegex.exec(item.text);
        while (match !== null) {
          const videoId = match[1];
          youtubeUrls.push(`https://www.youtube.com/watch?v=${videoId}`);
          match = youtubeRegex.exec(item.text);
        }

        if (youtubeUrls.length > 0) {
          console.log(
            "[ThreadView] Found YouTube URLs in text item:",
            JSON.stringify(
              {
                originalText: item.text,
                youtubeUrls,
                videoIds: youtubeUrls.map((url) => url.split("v=")[1]),
              },
              null,
              2
            )
          );
        }

        // Remove YouTube references from text
        let cleanedText = item.text.replace(/\[youtube:[^\]]+\]/g, "").trim();

        // Normalize whitespace but preserve newlines for lists
        // Replace multiple spaces with single space, but preserve newlines
        cleanedText = cleanedText.replace(/[ \t]+/g, " ");
        // Normalize multiple newlines to single newline
        cleanedText = cleanedText.replace(/\n{3,}/g, "\n\n");
        // Trim but preserve leading/trailing newlines that might be part of list structure
        cleanedText = cleanedText.trim();

        return {
          ...item,
          text: cleanedText,
          youtubeUrls: youtubeUrls.length > 0 ? youtubeUrls : undefined,
        };
      }
      return item;
    })
    .filter((item) => {
      // Remove empty text items (unless they have YouTube URLs)
      if (item.type === "text") {
        return (
          (item.text && item.text.length > 0) || (item.youtubeUrls && item.youtubeUrls.length > 0)
        );
      }
      return true;
    });

  console.log(
    "[ThreadView] Processed content items:",
    JSON.stringify(
      processedItems.map((item) => ({
        type: item.type,
        text: item.text?.substring(0, 100),
        youtubeUrls: item.youtubeUrls,
        imageUrl: item.image?.url,
      })),
      null,
      2
    )
  );

  return processedItems;
}

/**
 * Associates images with text chunks based on their position in the content
 */
function associateImagesWithChunks(
  contentItems: ContentItem[],
  chunks: string[]
): ChunkWithImages[] {
  const chunksWithImages: ChunkWithImages[] = chunks.map((chunk) => ({
    text: chunk,
    images: [],
    youtubeUrls: [],
  }));

  if (chunks.length === 0) {
    return chunksWithImages;
  }

  // Build full text from content items to find chunk boundaries
  // Join text items intelligently: preserve newlines, add space only when needed
  const allText = contentItems
    .filter((item) => item.type === "text")
    .map((item) => item.text || "")
    .reduce((acc, text, index, array) => {
      if (index === 0) return text;
      const prevText = array[index - 1];
      // If previous text ends with newline or current starts with newline, don't add space
      if (prevText.endsWith("\n") || text.startsWith("\n")) {
        return acc + text;
      }
      return `${acc} ${text}`;
    }, "");

  // Track which chunk we're currently building
  // Use character position in allText to accurately determine which chunk we're in
  let currentPositionInAllText = 0;
  let accumulatedText = "";

  // Helper function to find which chunk contains a given position in allText
  const findChunkIndexForPosition = (position: number): number => {
    let charCount = 0;
    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      const chunkStart = allText.indexOf(chunk, charCount);
      if (chunkStart < 0) continue;

      const chunkEnd = chunkStart + chunk.length;
      if (position >= chunkStart && position < chunkEnd) {
        return i;
      }
      // Move search forward
      charCount = Math.max(charCount, chunkEnd);
    }
    // Default to last chunk if position is beyond all chunks
    return Math.max(0, chunks.length - 1);
  };

  for (const item of contentItems) {
    // Handle text items with YouTube URLs but empty text (YouTube-only items)
    if (
      item.type === "text" &&
      item.youtubeUrls &&
      item.youtubeUrls.length > 0 &&
      (!item.text || item.text.trim() === "")
    ) {
      // Associate YouTube URLs with the chunk at current position
      const targetChunkIndex =
        currentPositionInAllText === 0 ? 0 : findChunkIndexForPosition(currentPositionInAllText);
      console.log(
        "[ThreadView] Associating YouTube URLs from empty text item:",
        JSON.stringify(
          {
            youtubeUrls: item.youtubeUrls,
            targetChunkIndex,
            currentPositionInAllText,
            totalChunks: chunksWithImages.length,
          },
          null,
          2
        )
      );

      if (targetChunkIndex < chunksWithImages.length) {
        chunksWithImages[targetChunkIndex].youtubeUrls.push(...item.youtubeUrls);
      }
      // Don't accumulate text for empty text items
      continue;
    }

    if (item.type === "text" && item.text) {
      // Join text intelligently: preserve newlines, add space only when needed
      let textToAdd: string;
      if (!accumulatedText) {
        textToAdd = item.text;
      } else if (accumulatedText.endsWith("\n") || item.text.startsWith("\n")) {
        // Don't add space if there's a newline boundary
        textToAdd = item.text;
      } else {
        textToAdd = ` ${item.text}`;
      }
      const testAccumulated = accumulatedText + textToAdd;

      // Associate YouTube URLs with the chunk at current position
      if (item.youtubeUrls && item.youtubeUrls.length > 0) {
        const targetChunkIndex =
          currentPositionInAllText === 0 ? 0 : findChunkIndexForPosition(currentPositionInAllText);
        console.log(
          "[ThreadView] Associating YouTube URLs with chunk:",
          JSON.stringify(
            {
              itemText: item.text?.substring(0, 50),
              youtubeUrls: item.youtubeUrls,
              targetChunkIndex,
              currentPositionInAllText,
              totalChunks: chunksWithImages.length,
            },
            null,
            2
          )
        );

        if (targetChunkIndex < chunksWithImages.length) {
          chunksWithImages[targetChunkIndex].youtubeUrls.push(...item.youtubeUrls);
        }
      }

      // Update position by finding where this text item appears in allText
      // Find the item text in allText starting from current position
      const itemStartPos = allText.indexOf(item.text, currentPositionInAllText);
      if (itemStartPos >= currentPositionInAllText) {
        // Found it, update position to end of this item
        currentPositionInAllText = itemStartPos + item.text.length;
        // Update accumulated text to match what we've processed in allText
        accumulatedText = allText.substring(0, currentPositionInAllText);
      } else {
        // Fallback: if we can't find exact match, try to find a similar position
        // Find where the accumulated text appears in allText
        const searchStart = Math.max(0, currentPositionInAllText - item.text.length);
        const foundIndex = allText.indexOf(testAccumulated, searchStart);
        if (foundIndex >= 0) {
          currentPositionInAllText = foundIndex + testAccumulated.length;
          accumulatedText = testAccumulated;
        } else {
          // Last resort: just increment by the added length
          currentPositionInAllText += textToAdd.length;
          accumulatedText = testAccumulated;
        }
      }
    } else if (item.type === "image" && item.image) {
      // Associate image with the chunk at current position
      const targetChunkIndex =
        currentPositionInAllText === 0 ? 0 : findChunkIndexForPosition(currentPositionInAllText);
      console.log(
        "[ThreadView] Associating image with chunk:",
        JSON.stringify(
          {
            imageUrl: item.image.url.substring(0, 50),
            targetChunkIndex,
            currentPositionInAllText,
            totalChunks: chunksWithImages.length,
          },
          null,
          2
        )
      );
      if (targetChunkIndex < chunksWithImages.length) {
        chunksWithImages[targetChunkIndex].images.push(item.image);
      }
    }
  }

  // Append YouTube URLs to the end of each chunk's text
  console.log(
    "[ThreadView] Chunks before appending YouTube URLs:",
    JSON.stringify(
      chunksWithImages.map((chunk, index) => ({
        chunkIndex: index,
        text: chunk.text.substring(0, 100),
        youtubeUrls: chunk.youtubeUrls,
        hasYoutubeUrls: chunk.youtubeUrls.length > 0,
      })),
      null,
      2
    )
  );

  const finalChunks = chunksWithImages.map((chunk, index) => {
    if (chunk.youtubeUrls.length > 0) {
      const urlsText = chunk.youtubeUrls.join(" ");
      const finalText = chunk.text ? `${chunk.text} ${urlsText}` : urlsText;
      console.log(
        "[ThreadView] Appending YouTube URLs to chunk:",
        JSON.stringify(
          {
            chunkIndex: index,
            originalText: chunk.text.substring(0, 100),
            youtubeUrls: chunk.youtubeUrls,
            finalText: finalText.substring(0, 150),
          },
          null,
          2
        )
      );
      return {
        ...chunk,
        text: finalText,
      };
    }
    return chunk;
  });

  console.log(
    "[ThreadView] Final chunks with YouTube URLs:",
    JSON.stringify(
      finalChunks.map((chunk, index) => ({
        chunkIndex: index,
        text: chunk.text.substring(0, 150),
        youtubeUrls: chunk.youtubeUrls,
      })),
      null,
      2
    )
  );

  return finalChunks;
}

/**
 * Splits content into chunks suitable for thread posting
 * Target: ~250 characters per chunk to leave room for thread numbering
 * Prioritizes splitting by complete sentences when possible
 */
function splitIntoThreadChunks(text: string, maxLength: number = 250): string[] {
  const chunks: string[] = [];

  // Normalize whitespace first
  const normalizedText = text.replace(/\s+/g, " ").trim();

  if (!normalizedText) {
    return [];
  }

  // Improved sentence splitting regex that handles:
  // - Sentence endings (. ! ?) followed by space or end of string
  // - Avoids splitting on abbreviations (requires space after punctuation)
  // - Handles multiple punctuation marks
  const sentenceRegex = /[.!?]+\s+/g;
  const sentences: string[] = [];
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  // Reset regex lastIndex to ensure we start from the beginning
  sentenceRegex.lastIndex = 0;

  // Find all sentence boundaries
  match = sentenceRegex.exec(normalizedText);
  while (match !== null) {
    const sentenceEnd = match.index + match[0].length;
    const sentence = normalizedText.substring(lastIndex, sentenceEnd).trim();

    if (sentence && sentence.length > 0) {
      sentences.push(sentence);
    }

    lastIndex = sentenceEnd;
    match = sentenceRegex.exec(normalizedText);
  }

  // Add any remaining text after the last sentence
  if (lastIndex < normalizedText.length) {
    const remaining = normalizedText.substring(lastIndex).trim();
    if (remaining && remaining.length > 0) {
      sentences.push(remaining);
    }
  }

  // If no sentences were found (e.g., no punctuation), treat entire text as one sentence
  if (sentences.length === 0) {
    sentences.push(normalizedText);
  }

  // Group sentences into chunks
  let currentChunk = "";

  for (const sentence of sentences) {
    const trimmedSentence = sentence.trim();
    if (!trimmedSentence) continue;

    // Try adding this sentence to the current chunk
    const testChunk = currentChunk ? `${currentChunk} ${trimmedSentence}` : trimmedSentence;

    if (testChunk.length <= maxLength) {
      // Sentence fits, add it to current chunk
      currentChunk = testChunk;
    } else {
      // Sentence doesn't fit - save current chunk first
      if (currentChunk.trim()) {
        chunks.push(currentChunk.trim());
        currentChunk = "";
      }

      // If the sentence itself is too long, split it by words
      if (trimmedSentence.length > maxLength) {
        const words = trimmedSentence.split(/\s+/);
        let wordChunk = "";

        for (const word of words) {
          const testWordChunk = wordChunk ? `${wordChunk} ${word}` : word;

          if (testWordChunk.length <= maxLength) {
            wordChunk = testWordChunk;
          } else {
            // Word chunk is full, save it and start new one
            if (wordChunk.trim()) {
              chunks.push(wordChunk.trim());
            }
            wordChunk = word;
          }
        }

        // Set the remaining word chunk as the current chunk
        currentChunk = wordChunk.trim();
      } else {
        // Sentence fits on its own, start a new chunk
        currentChunk = trimmedSentence;
      }
    }
  }

  // Add any remaining chunk
  if (currentChunk.trim()) {
    chunks.push(currentChunk.trim());
  }

  // Remove any empty chunks and ensure no duplicates
  return chunks.filter((chunk, index, self) => chunk.length > 0 && self.indexOf(chunk) === index);
}

export function ThreadView({ title, content, onClose }: ThreadViewProps) {
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);
  const [copiedImageIndex, setCopiedImageIndex] = useState<Record<string, number>>({});

  // Extract content items and split into chunks
  const contentItems = extractContentItems(content);
  const allText = contentItems
    .filter((item) => item.type === "text")
    .map((item) => item.text || "")
    .join(" ");
  const chunks = splitIntoThreadChunks(allText);
  const chunksWithImages = associateImagesWithChunks(contentItems, chunks);

  const totalImages = chunksWithImages.reduce((sum, chunk) => sum + chunk.images.length, 0);

  const handleCopy = async (text: string, index: number) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopiedIndex(index);
      toast.success(`Copied chunk ${index + 1}/${chunks.length}`);
      setTimeout(() => setCopiedIndex(null), 2000);
    } catch (error) {
      console.error("[ThreadView] Copy error:", JSON.stringify(error, null, 2));
      toast.error("Failed to copy to clipboard");
    }
  };

  const handleCopyImage = async (url: string, chunkIndex: number, imageIndex: number) => {
    try {
      await navigator.clipboard.writeText(url);
      setCopiedImageIndex({ ...copiedImageIndex, [`${chunkIndex}-${imageIndex}`]: Date.now() });
      toast.success(`Copied image URL`);
      setTimeout(() => {
        setCopiedImageIndex((prev) => {
          const newState = { ...prev };
          delete newState[`${chunkIndex}-${imageIndex}`];
          return newState;
        });
      }, 2000);
    } catch (error) {
      console.error("[ThreadView] Copy image error:", JSON.stringify(error, null, 2));
      toast.error("Failed to copy to clipboard");
    }
  };

  if (chunks.length === 0 && totalImages === 0) {
    return (
      <div className="text-center py-8 text-muted-foreground">No content to split into threads</div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold">{title}</h3>
          <p className="text-sm text-muted-foreground">
            {chunks.length > 0 && (
              <>
                Split into {chunks.length} {chunks.length === 1 ? "chunk" : "chunks"} for thread
                posting
                {totalImages > 0 && " • "}
              </>
            )}
            {totalImages > 0 && (
              <>
                {totalImages} {totalImages === 1 ? "image" : "images"} available
              </>
            )}
          </p>
        </div>
        {onClose && (
          <Button onClick={onClose} variant="outline" size="sm">
            <X className="h-4 w-4 mr-2" />
            Close Thread View
          </Button>
        )}
      </div>

      <div className="h-[500px] overflow-y-auto pr-4">
        <div className="space-y-3">
          {/* Display chunks with their associated images */}
          {chunksWithImages.map((chunkWithImages, chunkIndex) => (
            <Card
              key={`chunk-${chunkWithImages.text.substring(0, 50)}-${chunkWithImages.text.length}`}
              className="relative"
            >
              <CardHeader>
                <div className="flex items-center justify-between">
                  <CardTitle className="text-xs font-mono text-muted-foreground">
                    {chunkIndex + 1}/{chunks.length}
                  </CardTitle>
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-muted-foreground">
                      {chunkWithImages.text.length} chars
                    </span>
                    <Button
                      onClick={() => handleCopy(chunkWithImages.text, chunkIndex)}
                      variant="ghost"
                      size="sm"
                      className="h-7 w-7 p-0"
                    >
                      {copiedIndex === chunkIndex ? (
                        <Check className="h-4 w-4 text-green-600" />
                      ) : (
                        <Copy className="h-4 w-4" />
                      )}
                    </Button>
                  </div>
                </div>
              </CardHeader>
              <CardContent>
                <div className="space-y-3 -mt-4">
                  {/* Display text chunk */}
                  {chunkWithImages.text && (
                    <p className="text-sm whitespace-pre-wrap wrap-break-word">
                      {chunkWithImages.text}
                    </p>
                  )}
                  {/* Display images associated with this chunk */}
                  {chunkWithImages.images.map((image, imageIndex) => (
                    <div
                      key={`image-${image.url}-${imageIndex}`}
                      className="border border-blue-200 rounded-md p-3"
                    >
                      <div className="flex items-center gap-3">
                        {/* Thumbnail */}
                        <div className="w-24 shrink-0 relative aspect-video">
                          <Image
                            src={image.url}
                            alt=""
                            fill
                            className="rounded object-cover"
                            unoptimized
                            onError={(e) => {
                              // Hide image if it fails to load
                              e.currentTarget.style.display = "none";
                            }}
                          />
                        </div>
                        {/* URL and copy button */}
                        <div className="flex-1 flex items-center justify-between gap-2 min-w-0">
                          <p className="text-xs font-mono break-all flex-1">{image.url}</p>
                          <Button
                            onClick={() => handleCopyImage(image.url, chunkIndex, imageIndex)}
                            variant="ghost"
                            size="sm"
                            className="h-7 w-7 p-0 shrink-0"
                          >
                            {copiedImageIndex[`${chunkIndex}-${imageIndex}`] ? (
                              <Check className="h-4 w-4 text-green-600" />
                            ) : (
                              <Copy className="h-4 w-4" />
                            )}
                          </Button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>

      <div className="text-xs text-muted-foreground bg-muted p-3 rounded-md">
        <p className="font-semibold mb-1">Tips:</p>
        <ul className="list-disc list-inside space-y-1">
          <li>Each text chunk is optimized for X/Twitter (~280 chars) and Bluesky (~300 chars)</li>
          <li>
            Images are displayed with their associated text chunks - copy the image URL and add it
            manually to your post
          </li>
          <li>Click the copy icon on each chunk or image to copy it individually</li>
          <li>You can edit chunks before posting if needed</li>
        </ul>
      </div>
    </div>
  );
}
