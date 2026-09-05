import { readFile, realpath, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { generateImage } from "ai";
import { generatedImageOutput, generationOptions, imageModel } from "./generation.js";
import { protocolVersion, providers, sanitizeError, validateRequest, type HelperRequest } from "./protocol.js";

const maximumFrameBytes = 16 * 1024 * 1024;

async function readFramedRequest(): Promise<HelperRequest> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(Buffer.from(chunk));
  const input = Buffer.concat(chunks);
  if (input.length < 4) throw new Error("invalid_request");
  const length = input.readUInt32BE(0);
  if (length < 2 || length > maximumFrameBytes || input.length !== length + 4) throw new Error("invalid_request");
  let value: unknown;
  try {
    value = JSON.parse(input.subarray(4).toString("utf8"));
  } catch {
    throw new Error("invalid_request");
  }
  return validateRequest(value);
}

async function requireContainedFiles(request: HelperRequest): Promise<void> {
  const workspace = await realpath(process.cwd());
  const jobRoot = path.dirname(workspace) + path.sep;
  const outputParent = await realpath(path.dirname(request.outputPath));
  if (outputParent !== workspace) throw new Error("invalid_request");
  for (const reference of request.references) {
    const resolved = await realpath(reference.path);
    if (!resolved.startsWith(jobRoot)) throw new Error("invalid_request");
    if (!(await stat(resolved)).isFile()) throw new Error("invalid_request");
  }
}

async function run(request: HelperRequest): Promise<void> {
  await requireContainedFiles(request);
  const images = await Promise.all(request.references.map((reference) => readFile(reference.path)));
  const abortController = new AbortController();
  const timeout = setTimeout(() => abortController.abort(), 175_000);
  try {
    const result = await generateImage(generationOptions(
      request,
      imageModel(request),
      images,
      abortController.signal,
    ));
    if (result.images.length !== 1) throw new Error("provider_unavailable");
    const output = generatedImageOutput(request, result.images[0]!);
    await writeFile(output.path, output.uint8Array, { flag: "wx" });
    process.stdout.write(`${JSON.stringify({
      type: "result", path: output.path, mediaType: output.mediaType,
    })}\n`);
  } finally {
    clearTimeout(timeout);
  }
}

async function main(): Promise<void> {
  if (process.argv.length === 2 || (process.argv.length === 3 && process.argv[2] === "--capabilities")) {
    process.stdout.write(JSON.stringify({ protocolVersion, helperVersion: "1.0.0", providers }));
    return;
  }
  if (process.argv.length !== 3 || process.argv[2] !== "--stdio") throw new Error("invalid_request");
  const request = await readFramedRequest();
  await run(request);
}

main().catch((error: unknown) => {
  process.stdout.write(`${JSON.stringify({ type: "error", code: sanitizeError(error) })}\n`);
  process.exitCode = 1;
});
