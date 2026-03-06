export const FILM_LENGTH_OPTIONS = [
  "30-60 seconds",
  "1-3 minutes",
  "3-5 minutes",
  "5-10 minutes",
  "10-20 minutes",
  "20+ minutes",
] as const;

export type FilmLengthOption = (typeof FILM_LENGTH_OPTIONS)[number];

export const WORKFLOW_PHASES = [
  "concept",
  "title-logline",
  "film-length",
  "characters",
  "outline",
  "script-breakdown",
  "screenplay",
  "assets",
  "shot-prompts",
] as const;

export type WorkflowPhase = (typeof WORKFLOW_PHASES)[number];

export type PhaseCompletionState = "not_started" | "in_progress" | "complete";

export type PhaseVisibility = "private" | "published";

export interface PhaseStatus {
  status: PhaseCompletionState;
  updatedAt?: string;
}

export type PhaseStatusMap = Partial<Record<WorkflowPhase, PhaseStatus>>;
export type PhaseVisibilityMap = Partial<Record<WorkflowPhase, PhaseVisibility>>;

export interface DevelopmentConceptDirection {
  id: string;
  title: string;
  premise: string;
  tone: string;
  whyItWorks: string;
}

export interface StoryOutlineBeat {
  id: string;
  order: number;
  title: string;
  summary: string;
  purpose?: string;
}

export interface ScenePlanItem {
  id: string;
  order: number;
  title: string;
  summary: string;
  locationName?: string;
  characters: string[];
  dramaticPurpose: string;
  emotionalBeat: string;
  visualIntent: string;
}

export interface ProjectDevelopmentData {
  conceptSeed?: string;
  conceptDirections?: DevelopmentConceptDirection[];
  selectedConceptId?: string;
  conceptStatement?: string;
  genres?: string[];
  influences?: string[];
  outline?: StoryOutlineBeat[];
  scriptBreakdown?: ScenePlanItem[];
}

export function createDefaultPhaseVisibility(): Record<WorkflowPhase, PhaseVisibility> {
  return {
    concept: "published",
    "title-logline": "published",
    "film-length": "published",
    characters: "published",
    outline: "published",
    "script-breakdown": "published",
    screenplay: "published",
    assets: "published",
    "shot-prompts": "published",
  };
}

export function createDefaultPhaseStatus(): Record<WorkflowPhase, PhaseStatus> {
  return {
    concept: { status: "not_started" },
    "title-logline": { status: "not_started" },
    "film-length": { status: "not_started" },
    characters: { status: "not_started" },
    outline: { status: "not_started" },
    "script-breakdown": { status: "not_started" },
    screenplay: { status: "not_started" },
    assets: { status: "not_started" },
    "shot-prompts": { status: "not_started" },
  };
}
