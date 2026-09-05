export const protocolVersion = 2;

export const providers = [
  {
    id: "google-nano-banana-2",
    modelIDs: ["gemini-3.1-flash-image"],
    aspectRatios: ["2:3", "16:9", "1:1"],
    outputFormats: ["png", "jpeg"],
    maximumReferenceImages: 14,
    maximumCharacterReferences: 4,
    maximumNonCharacterReferences: 10,
  },
  {
    id: "openai-gpt-image-2",
    modelIDs: ["gpt-image-2-2026-04-21"],
    aspectRatios: ["2:3", "16:9", "1:1"],
    outputFormats: ["png"],
    maximumReferenceImages: 14,
    maximumCharacterReferences: null,
    maximumNonCharacterReferences: null,
  },
] as const;

export type ProviderID = (typeof providers)[number]["id"];

export interface HelperReference {
  path: string;
  entityKind: string;
}

export interface HelperRequest {
  protocolVersion: number;
  providerID: ProviderID;
  modelID: string;
  authorization: string;
  prompt: string;
  references: HelperReference[];
  outputPath: string;
  aspectRatio: "2:3" | "16:9" | "1:1";
  width: number;
  height: number;
  outputFormat: "png";
}

const sizes = new Set(["768x1152", "1280x720", "1024x1024"]);
const kinds = new Set(["character", "creature", "location", "vehicle", "prop", "object"]);

export function validateRequest(value: unknown): HelperRequest {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("invalid_request");
  }
  const record = value as Record<string, unknown>;
  const expected = new Set([
    "protocolVersion", "providerID", "modelID", "authorization", "prompt",
    "references", "outputPath", "aspectRatio", "width", "height", "outputFormat",
  ]);
  if (Object.keys(record).some((key) => !expected.has(key))) throw new Error("invalid_request");
  if (record.protocolVersion !== protocolVersion) throw new Error("invalid_request");
  const provider = providers.find((item) => item.id === record.providerID);
  if (!provider || typeof record.modelID !== "string" || !provider.modelIDs.includes(record.modelID as never)) {
    throw new Error("invalid_request");
  }
  if (typeof record.authorization !== "string" || record.authorization.length < 1 || record.authorization.length > 16_384) {
    throw new Error("authentication");
  }
  if (record.authorization.includes("\n") || record.authorization.includes("\r")) throw new Error("authentication");
  if (typeof record.prompt !== "string" || record.prompt.trim().length === 0 || Buffer.byteLength(record.prompt) > 65_536) {
    throw new Error("invalid_request");
  }
  if (!Array.isArray(record.references) || record.references.length > 14) throw new Error("invalid_request");
  for (const item of record.references) {
    if (typeof item !== "object" || item === null || Array.isArray(item)) throw new Error("invalid_request");
    const ref = item as Record<string, unknown>;
    if (Object.keys(ref).some((key) => key !== "path" && key !== "entityKind")) throw new Error("invalid_request");
    if (typeof ref.path !== "string" || typeof ref.entityKind !== "string" || !kinds.has(ref.entityKind)) {
      throw new Error("invalid_request");
    }
  }
  if (record.providerID === "google-nano-banana-2") {
    const characterCount = record.references.filter((item) => {
      const kind = (item as Record<string, unknown>).entityKind;
      return kind === "character" || kind === "creature";
    }).length;
    if (characterCount > 4) throw new Error("invalid_request");
    if (record.references.length - characterCount > 10) throw new Error("invalid_request");
  }
  if (typeof record.outputPath !== "string" || !record.outputPath.startsWith("/")) throw new Error("invalid_request");
  if (record.outputFormat !== "png") throw new Error("invalid_request");
  if (record.aspectRatio !== "2:3" && record.aspectRatio !== "16:9" && record.aspectRatio !== "1:1") {
    throw new Error("invalid_request");
  }
  if (!Number.isInteger(record.width) || !Number.isInteger(record.height)) throw new Error("invalid_request");
  if (!sizes.has(`${record.width}x${record.height}`)) throw new Error("invalid_request");
  return record as unknown as HelperRequest;
}

export function sanitizeError(error: unknown): string {
  if (error instanceof Error) {
    const direct = new Set([
      "authentication", "billing", "quota", "rate_limit", "moderation",
      "invalid_request", "provider_unavailable", "timeout", "network",
    ]);
    if (direct.has(error.message)) return error.message;
    const value = error as Error & { statusCode?: number; status?: number; code?: string };
    const status = value.statusCode ?? value.status;
    if (status === 401 || status === 403) return "authentication";
    if (status === 402) return "billing";
    if (status === 429) return "rate_limit";
    if (typeof status === "number" && status >= 500) return "provider_unavailable";
    if (value.code === "ETIMEDOUT" || value.code === "ABORT_ERR") return "timeout";
    if (value.code === "ENETUNREACH" || value.code === "ECONNRESET") return "network";
  }
  return "unknown";
}
