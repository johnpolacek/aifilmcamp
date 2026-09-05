import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { createOpenAI } from "@ai-sdk/openai";
import type { generateImage } from "ai";
import path from "node:path";
import type { HelperRequest } from "./protocol.js";

type GenerateImageOptions = Parameters<typeof generateImage>[0];
type ImageModel = GenerateImageOptions["model"];

export interface ImageModelFactories {
  google(apiKey: string, modelID: string): ImageModel;
  openAI(apiKey: string, modelID: string): ImageModel;
}

export interface GeneratedImagePayload {
  mediaType: string;
  uint8Array: Uint8Array;
}

export interface GeneratedImageOutput extends GeneratedImagePayload {
  path: string;
}

const liveFactories: ImageModelFactories = {
  google(apiKey, modelID) {
    return createGoogleGenerativeAI({ apiKey }).image(modelID);
  },
  openAI(apiKey, modelID) {
    return createOpenAI({ apiKey }).image(modelID);
  },
};

export function imageModel(
  request: HelperRequest,
  factories: ImageModelFactories = liveFactories,
): ImageModel {
  return request.providerID === "google-nano-banana-2"
    ? factories.google(request.authorization, request.modelID)
    : factories.openAI(request.authorization, request.modelID);
}

export function generationOptions(
  request: HelperRequest,
  model: ImageModel,
  images: Uint8Array[],
  abortSignal: AbortSignal,
): GenerateImageOptions {
  const referenceGuide = request.references.map((reference, index) =>
    `Reference ${index + 1} is the canonical ${reference.entityKind} continuity image.`
  ).join(" ");
  const text = referenceGuide.length === 0 ? request.prompt : `${request.prompt}\n\n${referenceGuide}`;
  const prompt = images.length === 0 ? text : { text, images };

  return {
    model,
    prompt,
    ...(request.providerID === "google-nano-banana-2"
      ? {
          aspectRatio: request.aspectRatio,
          providerOptions: { google: { imageConfig: { imageSize: "1K" } } },
        }
      : {
          size: `${request.width}x${request.height}` as `${number}x${number}`,
          providerOptions: { openai: { outputFormat: "png" } },
        }),
    maxRetries: 0,
    abortSignal,
  };
}

/** Keeps the on-disk suffix truthful when a provider returns a supported native format. */
export function generatedImageOutput(
  request: HelperRequest,
  image: GeneratedImagePayload,
): GeneratedImageOutput {
  const mediaType = image.mediaType.toLowerCase().split(";", 1)[0]!.trim();
  const extension = mediaType === "image/png"
    ? "png"
    : mediaType === "image/jpeg" || mediaType === "image/jpg"
    ? "jpg"
    : undefined;
  if (extension === undefined) throw new Error("provider_unavailable");
  if (request.providerID === "openai-gpt-image-2" && extension !== "png") {
    throw new Error("provider_unavailable");
  }
  const parsed = path.parse(request.outputPath);
  return {
    path: path.join(parsed.dir, `${parsed.name}.${extension}`),
    mediaType: extension === "png" ? "image/png" : "image/jpeg",
    uint8Array: image.uint8Array,
  };
}
