"use client";

import { useRouter } from "next/navigation";
import type React from "react";
import { useMemo, useState } from "react";
import { Bot, CheckCircle2, ClipboardList, Eye, FileText, Lightbulb, Map, Users } from "lucide-react";
import { toast } from "sonner";
import type { ProjectFormData } from "@/components/project-form";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { derivePhaseStatus, ensureProjectPhaseVisibility, getPromptShotCount } from "@/lib/development";
import {
  FILM_LENGTH_OPTIONS,
  type PhaseVisibility,
  type WorkflowPhase,
  WORKFLOW_PHASES,
} from "@/lib/types/development";

interface ProjectDevelopmentPhasesProps {
  data: ProjectFormData;
  projectId?: string;
  onChange: (nextData: ProjectFormData) => void;
  onSyncScenesFromBreakdown: () => void;
}

const phaseMeta: Record<WorkflowPhase, { label: string; icon: typeof Lightbulb }> = {
  concept: { label: "Concept", icon: Lightbulb },
  "title-logline": { label: "Title + Logline", icon: FileText },
  "film-length": { label: "Film Length", icon: ClipboardList },
  characters: { label: "Characters", icon: Users },
  outline: { label: "Outline", icon: Map },
  "script-breakdown": { label: "Script Breakdown", icon: ClipboardList },
  screenplay: { label: "Screenplay", icon: FileText },
  assets: { label: "Assets", icon: Eye },
  "shot-prompts": { label: "Shot Prompts", icon: Bot },
};

function PhaseCard({
  phase,
  data,
  onVisibilityChange,
  children,
}: {
  phase: WorkflowPhase;
  data: ProjectFormData;
  onVisibilityChange: (phase: WorkflowPhase, value: PhaseVisibility) => void;
  children: React.ReactNode;
}) {
  const visibility = ensureProjectPhaseVisibility(data)[phase];
  const status = derivePhaseStatus(data)[phase]?.status || "not_started";
  const meta = phaseMeta[phase];
  const Icon = meta.icon;

  return (
    <Card className="border-border bg-card/70">
      <CardHeader className="pb-3">
        <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary/10 text-primary">
              <Icon className="h-5 w-5" />
            </div>
            <div>
              <CardTitle className="text-lg">{meta.label}</CardTitle>
              <div className="mt-1 flex items-center gap-2">
                <Badge variant={status === "complete" ? "default" : "secondary"}>{status}</Badge>
                <Badge variant="outline">{visibility}</Badge>
              </div>
            </div>
          </div>
          <div className="w-full md:w-[180px]">
            <Select
              value={visibility}
              onValueChange={(value) => onVisibilityChange(phase, value as PhaseVisibility)}
            >
              <SelectTrigger className="bg-background">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="private">Private</SelectItem>
                <SelectItem value="published">Published</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  );
}

export function ProjectDevelopmentPhases({
  data,
  projectId,
  onChange,
  onSyncScenesFromBreakdown,
}: ProjectDevelopmentPhasesProps) {
  const router = useRouter();
  const [activePhase, setActivePhase] = useState<WorkflowPhase>("concept");
  const [loadingPhase, setLoadingPhase] = useState<string | null>(null);
  const publishedCount = useMemo(
    () =>
      WORKFLOW_PHASES.filter((phase) => ensureProjectPhaseVisibility(data)[phase] === "published")
        .length,
    [data]
  );

  const updateData = (nextData: ProjectFormData) => {
    onChange({
      ...nextData,
      duration: nextData.duration || nextData.filmLength || "",
    });
  };

  const updateVisibility = (phase: WorkflowPhase, visibility: PhaseVisibility) => {
    updateData({
      ...data,
      phaseVisibility: {
        ...ensureProjectPhaseVisibility(data),
        [phase]: visibility,
      },
    });
  };

  const withLoading = async (key: string, action: () => Promise<void>) => {
    setLoadingPhase(key);
    try {
      await action();
    } finally {
      setLoadingPhase(null);
    }
  };

  const generateConcept = async () =>
    withLoading("concept", async () => {
      const { generateConceptDirections } = await import("@/lib/actions/development");
      const directions = await generateConceptDirections(data);
      updateData({
        ...data,
        development: {
          ...data.development,
          conceptDirections: directions,
          selectedConceptId: directions[0]?.id,
          conceptStatement: directions[0]?.premise || data.development?.conceptStatement,
        },
      });
      toast.success("Generated concept directions");
    });

  const generateTitle = async () =>
    withLoading("title-logline", async () => {
      const { generateTitleAndLogline } = await import("@/lib/actions/development");
      const next = await generateTitleAndLogline(data);
      updateData({
        ...data,
        title: next.title,
        logline: next.logline,
        development: {
          ...data.development,
          conceptStatement: next.conceptStatement,
        },
      });
      toast.success("Generated title and logline");
    });

  const generateOutlineDraft = async () =>
    withLoading("outline", async () => {
      const { generateOutline } = await import("@/lib/actions/development");
      const outline = await generateOutline(data);
      updateData({
        ...data,
        development: {
          ...data.development,
          outline,
        },
      });
      toast.success("Generated plot outline");
    });

  const generateBreakdownDraft = async () =>
    withLoading("script-breakdown", async () => {
      const { generateScriptBreakdown } = await import("@/lib/actions/development");
      const scriptBreakdown = await generateScriptBreakdown(data);
      updateData({
        ...data,
        development: {
          ...data.development,
          scriptBreakdown,
        },
      });
      toast.success("Generated script breakdown");
    });

  const generateScreenplay = async () =>
    withLoading("screenplay", async () => {
      const { generateScreenplayDraft } = await import("@/lib/actions/development");
      const screenplayText = await generateScreenplayDraft(data);
      updateData({
        ...data,
        screenplayText,
      });
      toast.success("Generated screenplay draft");
    });

  return (
    <div className="space-y-6">
      <Card className="border-border bg-muted/30">
        <CardContent className="space-y-4 p-4">
          <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <div>
              <h2 className="text-xl font-semibold">Development Workflow</h2>
              <p className="text-sm text-muted-foreground">
                Guide the project from concept through prompt-ready scenes.
              </p>
            </div>
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <CheckCircle2 className="h-4 w-4 text-primary" />
              {publishedCount} published phases
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            {WORKFLOW_PHASES.map((phase) => {
              const status = derivePhaseStatus(data)[phase]?.status || "not_started";
              return (
                <button
                  key={phase}
                  type="button"
                  onClick={() => setActivePhase(phase)}
                  className={cn(
                    "rounded-full border px-3 py-1.5 text-sm transition-colors",
                    activePhase === phase
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-border bg-background hover:border-primary/40 hover:text-foreground"
                  )}
                >
                  {phaseMeta[phase].label} · {status}
                </button>
              );
            })}
          </div>
        </CardContent>
      </Card>

      <div className="space-y-6">
        <div className={cn(activePhase !== "concept" && "hidden")}>
          <PhaseCard phase="concept" data={data} onVisibilityChange={updateVisibility}>
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="concept-seed">Concept Seed</Label>
                <Textarea
                  id="concept-seed"
                  value={data.development?.conceptSeed || ""}
                  onChange={(event) =>
                    updateData({
                      ...data,
                      development: {
                        ...data.development,
                        conceptSeed: event.target.value,
                      },
                    })
                  }
                  placeholder="Theme, image, mood, or story spark..."
                  className="bg-background"
                  rows={3}
                />
              </div>
              <div className="flex gap-2">
                <Button type="button" onClick={() => void generateConcept()} disabled={loadingPhase === "concept"}>
                  <Bot className="mr-2 h-4 w-4" />
                  {loadingPhase === "concept" ? "Generating..." : "Generate Concepts"}
                </Button>
              </div>
              {(data.development?.conceptDirections || []).length > 0 && (
                <div className="grid gap-3 lg:grid-cols-3">
                  {data.development?.conceptDirections?.map((direction) => {
                    const selected = data.development?.selectedConceptId === direction.id;
                    return (
                      <button
                        key={direction.id}
                        type="button"
                        onClick={() =>
                          updateData({
                            ...data,
                            development: {
                              ...data.development,
                              selectedConceptId: direction.id,
                              conceptStatement: direction.premise,
                            },
                          })
                        }
                        className={cn(
                          "rounded-lg border p-4 text-left transition-colors",
                          selected ? "border-primary bg-primary/5" : "border-border bg-background"
                        )}
                      >
                        <p className="font-medium">{direction.title}</p>
                        <p className="mt-2 text-sm text-muted-foreground">{direction.premise}</p>
                        <p className="mt-2 text-xs uppercase tracking-wide text-primary">{direction.tone}</p>
                      </button>
                    );
                  })}
                </div>
              )}
              <div className="space-y-2">
                <Label htmlFor="concept-statement">Canonical Concept</Label>
                <Textarea
                  id="concept-statement"
                  value={data.development?.conceptStatement || ""}
                  onChange={(event) =>
                    updateData({
                      ...data,
                      development: {
                        ...data.development,
                        conceptStatement: event.target.value,
                      },
                    })
                  }
                  className="bg-background"
                  rows={3}
                />
              </div>
            </div>
          </PhaseCard>
        </div>

        <div className={cn(activePhase !== "title-logline" && "hidden")}>
          <PhaseCard phase="title-logline" data={data} onVisibilityChange={updateVisibility}>
            <div className="space-y-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="phase-title">Title</Label>
                  <Input
                    id="phase-title"
                    value={data.title}
                    onChange={(event) => updateData({ ...data, title: event.target.value })}
                    className="bg-background"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="phase-logline">Logline</Label>
                  <Textarea
                    id="phase-logline"
                    value={data.logline}
                    onChange={(event) => updateData({ ...data, logline: event.target.value })}
                    className="bg-background"
                    rows={2}
                  />
                </div>
              </div>
              <Button type="button" onClick={() => void generateTitle()} disabled={loadingPhase === "title-logline"}>
                <Bot className="mr-2 h-4 w-4" />
                {loadingPhase === "title-logline" ? "Generating..." : "Generate Title + Logline"}
              </Button>
            </div>
          </PhaseCard>
        </div>

        <div className={cn(activePhase !== "film-length" && "hidden")}>
          <PhaseCard phase="film-length" data={data} onVisibilityChange={updateVisibility}>
            <div className="space-y-2">
              <Label>Film Length</Label>
              <Select
                value={data.filmLength || data.duration || ""}
                onValueChange={(value) =>
                  updateData({
                    ...data,
                    filmLength: value as ProjectFormData["filmLength"],
                    duration: value,
                  })
                }
              >
                <SelectTrigger className="bg-background">
                  <SelectValue placeholder="Select target runtime" />
                </SelectTrigger>
                <SelectContent>
                  {FILM_LENGTH_OPTIONS.map((option) => (
                    <SelectItem key={option} value={option}>
                      {option}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </PhaseCard>
        </div>

        <div className={cn(activePhase !== "characters" && "hidden")}>
          <PhaseCard phase="characters" data={data} onVisibilityChange={updateVisibility}>
            <p className="text-sm text-muted-foreground">
              {data.characters?.length || 0} characters defined. Use the character editor below to manage roles, motivations, arcs, visuals, and reference images.
            </p>
          </PhaseCard>
        </div>

        <div className={cn(activePhase !== "outline" && "hidden")}>
          <PhaseCard phase="outline" data={data} onVisibilityChange={updateVisibility}>
            <div className="space-y-4">
              <div className="flex gap-2">
                <Button type="button" onClick={() => void generateOutlineDraft()} disabled={loadingPhase === "outline"}>
                  <Bot className="mr-2 h-4 w-4" />
                  {loadingPhase === "outline" ? "Generating..." : "Generate Outline"}
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  onClick={() =>
                    updateData({
                      ...data,
                      development: {
                        ...data.development,
                        outline: [
                          ...(data.development?.outline || []),
                          {
                            id: `beat-${Date.now()}`,
                            order: (data.development?.outline?.length || 0) + 1,
                            title: "",
                            summary: "",
                            purpose: "",
                          },
                        ],
                      },
                    })
                  }
                >
                  Add Beat
                </Button>
              </div>
              <div className="space-y-3">
                {(data.development?.outline || []).map((beat, index) => (
                  <div key={beat.id} className="rounded-lg border border-border bg-background p-4">
                    <div className="grid gap-3 md:grid-cols-3">
                      <Input
                        value={beat.title}
                        onChange={(event) => {
                          const outline = [...(data.development?.outline || [])];
                          outline[index] = { ...outline[index], title: event.target.value };
                          updateData({ ...data, development: { ...data.development, outline } });
                        }}
                        placeholder={`Beat ${index + 1} title`}
                      />
                      <Textarea
                        value={beat.summary}
                        onChange={(event) => {
                          const outline = [...(data.development?.outline || [])];
                          outline[index] = { ...outline[index], summary: event.target.value };
                          updateData({ ...data, development: { ...data.development, outline } });
                        }}
                        placeholder="What happens?"
                        rows={2}
                        className="md:col-span-2"
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </PhaseCard>
        </div>

        <div className={cn(activePhase !== "script-breakdown" && "hidden")}>
          <PhaseCard phase="script-breakdown" data={data} onVisibilityChange={updateVisibility}>
            <div className="space-y-4">
              <div className="flex flex-wrap gap-2">
                <Button type="button" onClick={() => void generateBreakdownDraft()} disabled={loadingPhase === "script-breakdown"}>
                  <Bot className="mr-2 h-4 w-4" />
                  {loadingPhase === "script-breakdown" ? "Generating..." : "Generate Breakdown"}
                </Button>
                <Button type="button" variant="outline" onClick={onSyncScenesFromBreakdown}>
                  Sync Scenes From Breakdown
                </Button>
              </div>
              <div className="space-y-3">
                {(data.development?.scriptBreakdown || []).map((scene, index) => (
                  <div key={scene.id} className="rounded-lg border border-border bg-background p-4">
                    <div className="grid gap-3 md:grid-cols-2">
                      <Input
                        value={scene.title}
                        onChange={(event) => {
                          const scriptBreakdown = [...(data.development?.scriptBreakdown || [])];
                          scriptBreakdown[index] = { ...scriptBreakdown[index], title: event.target.value };
                          updateData({ ...data, development: { ...data.development, scriptBreakdown } });
                        }}
                        placeholder={`Scene ${index + 1} title`}
                      />
                      <Input
                        value={scene.locationName || ""}
                        onChange={(event) => {
                          const scriptBreakdown = [...(data.development?.scriptBreakdown || [])];
                          scriptBreakdown[index] = {
                            ...scriptBreakdown[index],
                            locationName: event.target.value,
                          };
                          updateData({ ...data, development: { ...data.development, scriptBreakdown } });
                        }}
                        placeholder="Location"
                      />
                      <Textarea
                        value={scene.summary}
                        onChange={(event) => {
                          const scriptBreakdown = [...(data.development?.scriptBreakdown || [])];
                          scriptBreakdown[index] = { ...scriptBreakdown[index], summary: event.target.value };
                          updateData({ ...data, development: { ...data.development, scriptBreakdown } });
                        }}
                        placeholder="Scene summary"
                        rows={2}
                        className="md:col-span-2"
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </PhaseCard>
        </div>

        <div className={cn(activePhase !== "screenplay" && "hidden")}>
          <PhaseCard phase="screenplay" data={data} onVisibilityChange={updateVisibility}>
            <div className="space-y-4">
              <div className="flex flex-wrap gap-2">
                <Button type="button" onClick={() => void generateScreenplay()} disabled={loadingPhase === "screenplay"}>
                  <Bot className="mr-2 h-4 w-4" />
                  {loadingPhase === "screenplay" ? "Generating..." : "Generate Screenplay Draft"}
                </Button>
                {projectId && (
                  <Button type="button" variant="outline" onClick={() => router.push(`/dashboard/projects/${projectId}/screenplay`)}>
                    Open Screenplay Editor
                  </Button>
                )}
              </div>
              <p className="text-sm text-muted-foreground">
                {data.screenplayText?.trim()
                  ? `${data.screenplayText.trim().split(/\s+/).length} screenplay words available.`
                  : "No screenplay draft yet."}
              </p>
            </div>
          </PhaseCard>
        </div>

        <div className={cn(activePhase !== "assets" && "hidden")}>
          <PhaseCard phase="assets" data={data} onVisibilityChange={updateVisibility}>
            <p className="text-sm text-muted-foreground">
              Character reference images:{" "}
              {data.characters?.filter((character) => character.mainImage || character.images?.length).length || 0}
              {" · "}Location reference images:{" "}
              {data.setting?.locations?.filter((location) => location.image || location.images?.length).length || 0}
            </p>
          </PhaseCard>
        </div>

        <div className={cn(activePhase !== "shot-prompts" && "hidden")}>
          <PhaseCard phase="shot-prompts" data={data} onVisibilityChange={updateVisibility}>
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">
                {data.scenes?.length || 0} scenes and {getPromptShotCount(data.scenes)} prompt shots. Use the scene editor links below to build prompt-ready shot lists.
              </p>
              {projectId && data.scenes?.[0] && (
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => router.push(`/dashboard/projects/${projectId}/scenes/${data.scenes?.[0]?.id}/edit`)}
                >
                  Open First Scene Prompt Editor
                </Button>
              )}
            </div>
          </PhaseCard>
        </div>
      </div>
    </div>
  );
}
