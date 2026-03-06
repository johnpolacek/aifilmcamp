"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import type React from "react";
import { useEffect, useMemo, useState } from "react";
import {
  Bot,
  ChevronLeft,
  ChevronRight,
  ClipboardList,
  Eye,
  FileText,
  Lightbulb,
  Map,
  Users,
} from "lucide-react";
import { toast } from "sonner";
import type { ProjectFormData } from "@/components/project-form";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
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
import {
  canEnterStep,
  derivePhaseStatus,
  ensureProjectPhaseVisibility,
  getFirstIncompleteStep,
  getNextStep,
  getPreviousStep,
  getPromptShotCount,
  getStepOrder,
} from "@/lib/development";
import { cn } from "@/lib/utils";
import {
  FILM_LENGTH_OPTIONS,
  type PhaseVisibility,
  type WorkflowPhase,
} from "@/lib/types/development";

interface ProjectDevelopmentWizardProps {
  data: ProjectFormData;
  projectId?: string;
  onChange: (nextData: ProjectFormData) => void;
  onSyncScenesFromBreakdown: () => void;
  stepContent?: Partial<Record<WizardStep, React.ReactNode>>;
}

type WizardStep = WorkflowPhase;

const stepMeta: Record<
  WizardStep,
  {
    label: string;
    description: string;
    icon: typeof Lightbulb;
  }
> = {
  concept: {
    label: "New Project",
    description: "Start a new project by shaping the core concept you want to develop.",
    icon: Lightbulb,
  },
  "title-logline": {
    label: "Title + Logline",
    description: "Lock the core promise of the film before moving into structure.",
    icon: FileText,
  },
  "film-length": {
    label: "Film Length",
    description: "Choose the target runtime so every downstream draft fits the scope.",
    icon: ClipboardList,
  },
  characters: {
    label: "Characters",
    description: "Define who is in the story and why they matter before plotting scenes.",
    icon: Users,
  },
  outline: {
    label: "Plot Outline",
    description: "Shape the story beats that will become the screenplay.",
    icon: Map,
  },
  "script-breakdown": {
    label: "Script Breakdown",
    description: "Turn the outline into scene-by-scene planning with locations, characters, and intent.",
    icon: ClipboardList,
  },
  screenplay: {
    label: "Screenplay",
    description: "Draft and refine the screenplay while keeping the breakdown as the source of truth.",
    icon: FileText,
  },
  assets: {
    label: "Assets",
    description: "Curate character and location references that keep your visual world consistent.",
    icon: Eye,
  },
  "shot-prompts": {
    label: "Shot Breakdown + Prompts",
    description: "Move from scene planning into prompt-ready shot lists.",
    icon: Bot,
  },
};

function WizardProgressRail({
  data,
  activeStep,
  onStepChange,
}: {
  data: ProjectFormData;
  activeStep: WizardStep;
  onStepChange: (step: WizardStep) => void;
}) {
  const status = derivePhaseStatus(data);

  return (
    <div className="grid gap-2 md:grid-cols-3 xl:grid-cols-5">
      {getStepOrder().map((step) => {
        const Icon = stepMeta[step].icon;
        const enabled = canEnterStep(data, step);

        return (
          <button
            key={step}
            type="button"
            disabled={!enabled}
            onClick={() => onStepChange(step)}
            className={cn(
              "rounded-xl border px-4 py-3 text-left transition-colors",
              activeStep === step
                ? "border-primary bg-primary text-primary-foreground"
                : "border-border bg-background",
              enabled ? "hover:border-primary/40" : "cursor-not-allowed opacity-50"
            )}
          >
            <div className="flex items-center gap-2">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-black/10 text-inherit">
                <Icon className="h-4 w-4" />
              </div>
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold">{stepMeta[step].label}</p>
              </div>
            </div>
            <p className="mt-2 text-xs opacity-80">{status[step].status}</p>
          </button>
        );
      })}
    </div>
  );
}

function WizardStepFrame({
  data,
  step,
  onVisibilityChange,
  onPrevious,
  onNext,
  nextDisabled,
  isLastStep,
  children,
}: {
  data: ProjectFormData;
  step: WizardStep;
  onVisibilityChange: (step: WizardStep, value: PhaseVisibility) => void;
  onPrevious?: () => void;
  onNext: () => void;
  nextDisabled: boolean;
  isLastStep: boolean;
  children: React.ReactNode;
}) {
  const meta = stepMeta[step];
  const Icon = meta.icon;
  const visibility = ensureProjectPhaseVisibility(data)[step];
  const status = derivePhaseStatus(data)[step].status;

  return (
    <Card className="border-border bg-card/70">
      <CardHeader className="space-y-4">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div className="flex items-start gap-3">
            <div className="flex h-11 w-11 items-center justify-center rounded-full bg-primary/10 text-primary">
              <Icon className="h-5 w-5" />
            </div>
            <div>
              <CardTitle className="text-2xl">{meta.label}</CardTitle>
              <p className="mt-2 max-w-2xl text-sm text-muted-foreground">{meta.description}</p>
              <div className="mt-3 flex items-center gap-2">
                <Badge variant={status === "complete" ? "default" : "secondary"}>{status}</Badge>
                <Badge variant="outline">{visibility}</Badge>
              </div>
            </div>
          </div>
          <div className="w-full md:w-[180px]">
            <Select
              value={visibility}
              onValueChange={(value) => onVisibilityChange(step, value as PhaseVisibility)}
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
      <CardFooter className="flex items-center justify-between border-t border-border pt-6">
        <Button type="button" variant="outline" onClick={onPrevious} disabled={!onPrevious}>
          <ChevronLeft className="mr-2 h-4 w-4" />
          Previous
        </Button>
        <Button type="button" onClick={onNext} disabled={nextDisabled}>
          {isLastStep ? "Finish" : "Next"}
          {!isLastStep && <ChevronRight className="ml-2 h-4 w-4" />}
        </Button>
      </CardFooter>
    </Card>
  );
}

export function ProjectDevelopmentWizard({
  data,
  projectId,
  onChange,
  onSyncScenesFromBreakdown,
  stepContent,
}: ProjectDevelopmentWizardProps) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [loadingStep, setLoadingStep] = useState<WizardStep | null>(null);
  const stepOrder = useMemo(() => getStepOrder(), []);
  const requestedStep = searchParams.get("step") as WizardStep | null;
  const activeStep =
    requestedStep && canEnterStep(data, requestedStep)
      ? requestedStep
      : getFirstIncompleteStep(data);
  const activeStepIndex = stepOrder.indexOf(activeStep);
  const currentStatus = derivePhaseStatus(data)[activeStep].status;

  const setStep = (step: WizardStep) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("step", step);
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  };

  useEffect(() => {
    if (requestedStep !== activeStep) {
      const params = new URLSearchParams(searchParams.toString());
      params.set("step", activeStep);
      router.replace(`${pathname}?${params.toString()}`, { scroll: false });
    }
  }, [activeStep, pathname, requestedStep, router, searchParams]);

  const updateData = (nextData: ProjectFormData) => {
    onChange({
      ...nextData,
      duration: nextData.duration || nextData.filmLength || "",
    });
  };

  const updateVisibility = (step: WizardStep, visibility: PhaseVisibility) => {
    updateData({
      ...data,
      phaseVisibility: {
        ...ensureProjectPhaseVisibility(data),
        [step]: visibility,
      },
    });
  };

  const withLoading = async (step: WizardStep, action: () => Promise<void>) => {
    setLoadingStep(step);
    try {
      await action();
    } finally {
      setLoadingStep(null);
    }
  };

  const nextStep = getNextStep(activeStep);
  const previousStep = getPreviousStep(activeStep);

  const handleNext = () => {
    if (!nextStep) {
      toast.success("Wizard complete. Continue refining or publish phases when ready.");
      return;
    }
    setStep(nextStep);
  };

  const handlePrevious = () => {
    if (previousStep) {
      setStep(previousStep);
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

  const renderStepBody = () => {
    const customStepContent = stepContent?.[activeStep];
    if (customStepContent) {
      return customStepContent;
    }

    switch (activeStep) {
      case "concept":
        return (
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
            <Button type="button" onClick={() => void generateConcept()} disabled={loadingStep === "concept"}>
              <Bot className="mr-2 h-4 w-4" />
              {loadingStep === "concept" ? "Generating..." : "Generate Concepts"}
            </Button>
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
        );

      case "title-logline":
        return (
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
            <Button type="button" onClick={() => void generateTitle()} disabled={loadingStep === "title-logline"}>
              <Bot className="mr-2 h-4 w-4" />
              {loadingStep === "title-logline" ? "Generating..." : "Generate Title + Logline"}
            </Button>
          </div>
        );

      case "film-length":
        return (
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
        );

      case "characters":
        return (
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              {data.characters?.length || 0} characters defined. Use the character editor in the
              advanced project details below to manage roles, motivations, arcs, visuals, and
              reference images.
            </p>
            <div className="grid gap-3 md:grid-cols-2">
              {(data.characters || []).map((character, index) => (
                <div key={`${character.name}-${index}`} className="rounded-lg border border-border bg-background p-4">
                  <p className="font-medium">{character.name || `Character ${index + 1}`}</p>
                  {character.role && <p className="mt-1 text-sm text-primary">{character.role}</p>}
                  {character.appearance && (
                    <p className="mt-2 text-sm text-muted-foreground">{character.appearance}</p>
                  )}
                </div>
              ))}
            </div>
          </div>
        );

      case "outline":
        return (
          <div className="space-y-4">
            <div className="flex gap-2">
              <Button type="button" onClick={() => void generateOutlineDraft()} disabled={loadingStep === "outline"}>
                <Bot className="mr-2 h-4 w-4" />
                {loadingStep === "outline" ? "Generating..." : "Generate Outline"}
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
        );

      case "script-breakdown":
        return (
          <div className="space-y-4">
            <div className="flex flex-wrap gap-2">
              <Button
                type="button"
                onClick={() => void generateBreakdownDraft()}
                disabled={loadingStep === "script-breakdown"}
              >
                <Bot className="mr-2 h-4 w-4" />
                {loadingStep === "script-breakdown" ? "Generating..." : "Generate Breakdown"}
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
                        scriptBreakdown[index] = {
                          ...scriptBreakdown[index],
                          title: event.target.value,
                        };
                        updateData({
                          ...data,
                          development: { ...data.development, scriptBreakdown },
                        });
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
                        updateData({
                          ...data,
                          development: { ...data.development, scriptBreakdown },
                        });
                      }}
                      placeholder="Location"
                    />
                    <Textarea
                      value={scene.summary}
                      onChange={(event) => {
                        const scriptBreakdown = [...(data.development?.scriptBreakdown || [])];
                        scriptBreakdown[index] = {
                          ...scriptBreakdown[index],
                          summary: event.target.value,
                        };
                        updateData({
                          ...data,
                          development: { ...data.development, scriptBreakdown },
                        });
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
        );

      case "screenplay":
        return (
          <div className="space-y-4">
            <div className="flex flex-wrap gap-2">
              <Button type="button" onClick={() => void generateScreenplay()} disabled={loadingStep === "screenplay"}>
                <Bot className="mr-2 h-4 w-4" />
                {loadingStep === "screenplay" ? "Generating..." : "Generate Screenplay Draft"}
              </Button>
              {projectId && (
                <Button
                  type="button"
                  variant="outline"
                  onClick={() =>
                    router.push(`/dashboard/projects/${projectId}/screenplay?returnStep=screenplay`)
                  }
                >
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
        );

      case "assets":
        return (
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Character reference images:{" "}
              {data.characters?.filter((character) => character.mainImage || character.images?.length).length || 0}
              {" · "}Location reference images:{" "}
              {data.setting?.locations?.filter((location) => location.image || location.images?.length).length || 0}
            </p>
            <p className="text-sm text-muted-foreground">
              Use the asset and location editors in the advanced project details below to curate
              references.
            </p>
          </div>
        );

      case "shot-prompts":
        const firstScene = data.scenes?.[0];
        return (
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              {data.scenes?.length || 0} scenes and {getPromptShotCount(data.scenes)} prompt shots.
              Use the scene editor flow to build prompt-ready shot lists.
            </p>
            {projectId && firstScene && (
              <Button
                type="button"
                variant="outline"
                onClick={() =>
                  router.push(
                    `/dashboard/projects/${projectId}/scenes/${firstScene.id}/edit?returnStep=shot-prompts`
                  )
                }
              >
                Open First Scene Prompt Editor
              </Button>
            )}
          </div>
        );
    }
  };

  return (
    <div className="space-y-6">
      <WizardProgressRail data={data} activeStep={activeStep} onStepChange={setStep} />
      <WizardStepFrame
        data={data}
        step={activeStep}
        onVisibilityChange={updateVisibility}
        onPrevious={previousStep ? handlePrevious : undefined}
        onNext={handleNext}
        nextDisabled={!nextStep ? false : currentStatus !== "complete"}
        isLastStep={activeStepIndex === stepOrder.length - 1}
      >
        {renderStepBody()}
      </WizardStepFrame>
    </div>
  );
}

export const ProjectDevelopmentPhases = ProjectDevelopmentWizard;
