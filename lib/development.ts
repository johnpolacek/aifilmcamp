import type { ProjectFormData } from "@/components/project-form";
import type { Scene } from "@/lib/scenes-client";
import {
  createDefaultPhaseStatus,
  createDefaultPhaseVisibility,
  type PhaseStatus,
  type PhaseVisibility,
  type WorkflowPhase,
  WORKFLOW_PHASES,
} from "@/lib/types/development";

export function getPromptShotCount(scenes: Scene[] = []): number {
  return scenes.reduce((sum, scene) => sum + (scene.promptShots?.length || 0), 0);
}

export function derivePhaseStatus(project: ProjectFormData): Record<WorkflowPhase, PhaseStatus> {
  const defaults = createDefaultPhaseStatus();
  const outlineCount = project.development?.outline?.length || 0;
  const breakdownCount = project.development?.scriptBreakdown?.length || 0;
  const promptShotCount = getPromptShotCount(project.scenes);
  const characterCount = project.characters?.length || 0;
  const locationCount = project.setting?.locations?.length || 0;
  const screenplayWords = project.screenplayText?.trim().split(/\s+/).filter(Boolean).length || 0;
  const conceptReady = Boolean(
    project.development?.conceptStatement ||
      project.development?.conceptDirections?.length ||
      project.logline ||
      project.title
  );

  return {
    ...defaults,
    concept: { status: conceptReady ? "complete" : "not_started" },
    "title-logline": {
      status: project.title || project.logline ? "complete" : "not_started",
    },
    "film-length": { status: project.filmLength || project.duration ? "complete" : "not_started" },
    characters: {
      status: characterCount > 0 ? "complete" : "not_started",
    },
    outline: {
      status: outlineCount > 0 ? "complete" : "not_started",
    },
    "script-breakdown": {
      status: breakdownCount > 0 || (project.scenes?.length || 0) > 0 ? "complete" : "not_started",
    },
    screenplay: {
      status: screenplayWords > 0 ? "complete" : "not_started",
    },
    assets: {
      status:
        project.characters?.some((character) => character.mainImage || character.images?.length) ||
        project.setting?.locations?.some((location) => location.image || location.images?.length)
          ? "complete"
          : "not_started",
    },
    "shot-prompts": {
      status: promptShotCount > 0 ? "complete" : "not_started",
    },
  };
}

export function ensureProjectPhaseStatus(project: ProjectFormData): Record<WorkflowPhase, PhaseStatus> {
  return {
    ...derivePhaseStatus(project),
    ...project.phaseStatus,
  };
}

export function ensureProjectPhaseVisibility(
  project: ProjectFormData
): Record<WorkflowPhase, PhaseVisibility> {
  return {
    ...createDefaultPhaseVisibility(),
    ...project.phaseVisibility,
  };
}

export function getPublishedPhases(project: ProjectFormData): WorkflowPhase[] {
  const visibility = ensureProjectPhaseVisibility(project);
  return WORKFLOW_PHASES.filter((phase) => visibility[phase] === "published");
}
