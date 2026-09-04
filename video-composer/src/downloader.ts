import { createWriteStream } from "node:fs";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

/**
 * Download a file from a URL to a local path
 */
export async function downloadFile(url: string, destPath: string): Promise<void> {
  console.log(
    "[downloader] Downloading:",
    JSON.stringify({ url: url.substring(0, 100), destPath }, null, 2)
  );

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download: ${response.status} ${response.statusText}`);
  }

  if (!response.body) {
    throw new Error("Response body is null");
  }

  const fileStream = createWriteStream(destPath);

  // Convert web ReadableStream to Node.js Readable
  const nodeStream = Readable.fromWeb(response.body as import("stream/web").ReadableStream);

  await pipeline(nodeStream, fileStream);

  console.log("[downloader] Download complete:", JSON.stringify({ destPath }, null, 2));
}
