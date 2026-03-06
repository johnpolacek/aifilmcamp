"use server";

import { auth } from "@clerk/nextjs/server";
import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { generateText, Output } from "ai";
import { z } from "zod";
import type { ProjectFormData } from "@/components/project-form";
import type { Scene } from "@/lib/scenes-client";

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
      title: project.title || "",
      logline: project.logline || "",
      genre: project.genre || "",
      genres: project.development?.genres || [],
      filmLength: project.filmLength || project.duration || "",
      conceptSeed: project.development?.conceptSeed || "",
      conceptStatement: project.development?.conceptStatement || "",
      vibe: project.development?.vibe || "",
      influences: project.development?.influences || [],
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
