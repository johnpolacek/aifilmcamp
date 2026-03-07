"use server";

import { auth } from "@clerk/nextjs/server";
import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { generateText, Output } from "ai";
import { z } from "zod";
import type { ProjectFormData } from "@/components/project-form";
import type { Scene } from "@/lib/scenes-client";
import { getObjectFromS3 } from "@/lib/s3";
import type { SourceContextPack } from "@/lib/types/development";

function getTextModel() {
  const apiKey =
    process.env.GOOGLE_GEMINI_API_KEY || process.env.GOOGLE_GENERATIVE_AI_API_KEY;

  if (!apiKey) {
    throw new Error(
      "Google Gemini API key is missing. Set GOOGLE_GEMINI_API_KEY or GOOGLE_GENERATIVE_AI_API_KEY."
    );
  }

  const google = createGoogleGenerativeAI({ apiKey });
  return google("gemini-2.5-flash");
}

async function requireAuth() {
  const { userId } = await auth();
  if (!userId) {
    throw new Error("You must be signed in to generate project drafts");
  }
}

function buildProjectContext(project: Partial<ProjectFormData>): string {
  return JSON.stringify(
    {
      startMode: project.development?.startMode || "",
      title: project.title || "",
      logline: project.logline || "",
      genre: project.genre || "",
      genres: project.development?.genres || [],
      filmLength: project.filmLength || project.duration || "",
      conceptSeed: project.development?.conceptSeed || "",
      conceptStatement: project.development?.conceptStatement || "",
      vibe: project.development?.vibe || "",
      influences: project.development?.influences || [],
      sourceContextPack: project.development?.sourceContextPack || null,
      characters: (project.characters || []).map((character) => ({
        name: character.name,
        role: character.role,
        motivation: character.motivation,
        arc: character.arc,
        appearance: character.appearance,
      })),
      locations: (project.setting?.locations || []).map((location) => ({
        name: location.name,
        description: location.description,
        storyPurpose: location.storyPurpose,
      })),
      outline: project.development?.outline || [],
      scriptBreakdown: project.development?.scriptBreakdown || [],
      screenplayText: project.screenplayText || "",
    },
    null,
    2
  );
}

const sourceContextEntitySchema = z.object({
  name: z.string(),
  description: z.string(),
});

const sourceContextPackSchema = z.object({
  brief: z.string(),
  conceptSeed: z.string(),
  genreSuggestions: z.array(z.string()).max(6),
  influenceSuggestions: z.array(z.string()).max(8),
  vibeKeywords: z.array(z.string()).max(8),
  characterSeeds: z.array(sourceContextEntitySchema).max(8),
  locationSeeds: z.array(sourceContextEntitySchema).max(8),
  storyFacts: z.array(z.string()).max(12),
});

function chunkSourceText(text: string, chunkSize = 12000): string[] {
  const paragraphs = text.split(/\n\s*\n/);
  const chunks: string[] = [];
  let currentChunk = "";

  for (const paragraph of paragraphs) {
    const normalized = paragraph.trim();
    if (!normalized) continue;

    const candidate = currentChunk ? `${currentChunk}\n\n${normalized}` : normalized;
    if (candidate.length > chunkSize && currentChunk) {
      chunks.push(currentChunk);
      currentChunk = normalized;
      continue;
    }

    if (normalized.length > chunkSize) {
      for (let index = 0; index < normalized.length; index += chunkSize) {
        chunks.push(normalized.slice(index, index + chunkSize));
      }
      currentChunk = "";
      continue;
    }

    currentChunk = candidate;
  }

  if (currentChunk) {
    chunks.push(currentChunk);
  }

  return chunks.length > 0 ? chunks : [text.slice(0, chunkSize)];
}

function dedupeStrings(values: string[], limit: number): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))].slice(0, limit);
}

function mergeSourceContextPacks(packs: SourceContextPack[]): SourceContextPack {
  return {
    brief: packs.map((pack) => pack.brief).filter(Boolean).join("\n"),
    conceptSeed: packs.map((pack) => pack.conceptSeed).find(Boolean) || "",
    genreSuggestions: dedupeStrings(packs.flatMap((pack) => pack.genreSuggestions), 6),
    influenceSuggestions: dedupeStrings(packs.flatMap((pack) => pack.influenceSuggestions), 8),
    vibeKeywords: dedupeStrings(packs.flatMap((pack) => pack.vibeKeywords), 8),
    characterSeeds: packs.flatMap((pack) => pack.characterSeeds).slice(0, 8),
    locationSeeds: packs.flatMap((pack) => pack.locationSeeds).slice(0, 8),
    storyFacts: dedupeStrings(packs.flatMap((pack) => pack.storyFacts), 12),
  };
}

async function generateSourceContextFromText(
  project: Partial<ProjectFormData>,
  sourceText: string
): Promise<SourceContextPack> {
  if (sourceText.length <= 14000) {
    const { output } = await generateText({
      model: getTextModel(),
      output: Output.object({ schema: sourceContextPackSchema }),
      prompt: `You are ingesting a source document for an AI film project.

Turn this source into a compact reusable creative context pack. Keep it high-signal and practical for later project generation.

Project context:
${buildProjectContext(project)}

Source document text:
${sourceText}`,
    });

    return output;
  }

  const chunks = chunkSourceText(sourceText);
  const partialPacks = await Promise.all(
    chunks.map(async (chunk, index) => {
      const { output } = await generateText({
        model: getTextModel(),
        output: Output.object({ schema: sourceContextPackSchema }),
        prompt: `You are summarizing one chunk of a source document for an AI film project.

Return the most useful creative signals from this chunk only.

Chunk ${index + 1} of ${chunks.length}

Project context:
${buildProjectContext(project)}

Source chunk:
${chunk}`,
      });

      return output;
    })
  );

  const mergedPack = mergeSourceContextPacks(partialPacks);
  const { output } = await generateText({
    model: getTextModel(),
    output: Output.object({ schema: sourceContextPackSchema }),
    prompt: `You are combining partial source-document summaries into one final reusable context pack for an AI film project.

Project context:
${buildProjectContext(project)}

Partial summaries:
${JSON.stringify(mergedPack, null, 2)}`,
  });

  return output;
}

export async function generateConceptDirections(project: Partial<ProjectFormData>) {
  await requireAuth();

  const { output } = await generateText({
    model: getTextModel(),
    output: Output.object({
      schema: z.object({
        directions: z.array(
          z.object({
            title: z.string(),
            premise: z.string(),
            tone: z.string(),
            whyItWorks: z.string(),
          })
        ),
      }),
    }),
    prompt: `You are helping develop an AI film concept.

Return exactly 3 concept directions for this project. Keep each direction distinct and concise.

Project context:
${buildProjectContext(project)}`,
  });

  return output.directions.map((direction, index) => ({
    id: `concept-${Date.now()}-${index}`,
    ...direction,
  }));
}

export async function ingestSourceDocument(project: Partial<ProjectFormData>, sourceTextKey: string) {
  await requireAuth();

  const sourceText = await getObjectFromS3(sourceTextKey);
  if (!sourceText) {
    throw new Error("Imported source text could not be loaded.");
  }

  return generateSourceContextFromText(project, sourceText);
}

export async function generateRandomConceptSeed(input: {
  genre: string;
  influence: string;
  project?: Partial<ProjectFormData>;
}) {
  await requireAuth();

  const { output } = await generateText({
    model: getTextModel(),
    output: Output.object({
      schema: z.object({
        concept: z.string(),
      }),
    }),
    prompt: `Generate one concise film concept seed inspired by this genre and influence pairing.

Genre: ${input.genre}
Influence: ${input.influence}

Project context:
${buildProjectContext({
      ...input.project,
      genre: input.genre,
      development: {
        ...input.project?.development,
        influences: [input.influence],
      },
    })}`,
  });

  return output.concept;
}

export async function generateTitleAndLogline(project: Partial<ProjectFormData>) {
  await requireAuth();

  const { output } = await generateText({
    model: getTextModel(),
    output: Output.object({
      schema: z.object({
        title: z.string(),
        logline: z.string(),
        conceptStatement: z.string(),
        vibe: z.string(),
      }),
    }),
    prompt: `Create one strong title, one logline, one concise concept statement, and one short vibe line for this film project.

Project context:
${buildProjectContext(project)}`,
  });

  return output;
}

export async function generateOutline(project: Partial<ProjectFormData>) {
  await requireAuth();

  const { output } = await generateText({
    model: getTextModel(),
    output: Output.object({
      schema: z.object({
        outline: z.array(
          z.object({
            title: z.string(),
            summary: z.string(),
            purpose: z.string(),
          })
        ),
      }),
    }),
    prompt: `Generate a beat outline sized to the target film length. Keep it realistic for the selected duration.

Project context:
${buildProjectContext(project)}`,
  });

  return output.outline.map((beat, index) => ({
    id: `beat-${Date.now()}-${index}`,
    order: index + 1,
    ...beat,
  }));
}

export async function generateScriptBreakdown(project: Partial<ProjectFormData>) {
  await requireAuth();

  const { output } = await generateText({
    model: getTextModel(),
    output: Output.object({
      schema: z.object({
        scenes: z.array(
          z.object({
            title: z.string(),
            summary: z.string(),
            locationName: z.string().optional(),
            characters: z.array(z.string()),
            dramaticPurpose: z.string(),
            emotionalBeat: z.string(),
            visualIntent: z.string(),
          })
        ),
      }),
    }),
    prompt: `Generate a scene-by-scene script breakdown based on the project context.
The result must fit the requested film length and should be practical for later screenplay drafting and shot prompting.

Project context:
${buildProjectContext(project)}`,
  });

  return output.scenes.map((scene, index) => ({
    id: `scene-plan-${Date.now()}-${index}`,
    order: index + 1,
    ...scene,
  }));
}

export async function generateScreenplayDraft(project: Partial<ProjectFormData>) {
  await requireAuth();

  const { output } = await generateText({
    model: getTextModel(),
    output: Output.object({
      schema: z.object({
        screenplay: z.string(),
      }),
    }),
    prompt: `Write a screenplay draft using standard screenplay formatting with scene headings starting with INT. or EXT.
Fit the requested film length and use the existing breakdown as the source of truth.

Project context:
${buildProjectContext(project)}`,
  });

  return output.screenplay;
}

export async function generateShotPrompts(project: Partial<ProjectFormData>, scene: Partial<Scene>) {
  await requireAuth();

  const { output } = await generateText({
    model: getTextModel(),
    output: Output.object({
      schema: z.object({
        shots: z.array(
          z.object({
            title: z.string(),
            framing: z.string(),
            cameraMovement: z.string(),
            action: z.string(),
            continuityNotes: z.string().optional(),
            durationEstimateSeconds: z.number().int().min(1).max(15),
            prompt: z.string(),
          })
        ),
      }),
    }),
    prompt: `Create a tool-agnostic shot breakdown with ready-to-copy prompts for the scene below.
The output should emphasize framing, camera movement, action, continuity, and visual specificity.

Project context:
${buildProjectContext(project)}

Scene context:
${JSON.stringify(scene, null, 2)}`,
  });

  return output.shots.map((shot, index) => ({
    id: `prompt-shot-${Date.now()}-${index}`,
    shotNumber: index + 1,
    referenceAssetIds: [],
    ...shot,
  }));
}
