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
  Shuffle,
  Users,
} from "lucide-react";
import { toast } from "sonner";
import type { ProjectFormData } from "@/components/project-form";
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
import { Switch } from "@/components/ui/switch";
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

const GENRE_OPTIONS = [
  "Action",
  "Adventure",
  "Animation",
  "Biopic",
  "Coming-of-Age",
  "Comedy",
  "Crime",
  "Documentary",
  "Drama",
  "Dystopian",
  "Experimental",
  "Family",
  "Fantasy",
  "Historical",
  "Horror",
  "Mystery",
  "Noir",
  "Romance",
  "Sci-Fi",
  "Sports",
  "Supernatural",
  "Surreal",
  "Thriller",
  "Western",
] as const;

const INFLUENCE_OPTIONS = [
  "A24",
  "Alfonso Cuaron",
  "Alex Garland",
  "Alien",
  "Arrival",
  "Barry Jenkins",
  "Blade Runner",
  "Blade Runner 2049",
  "Brandon Cronenberg",
  "Brazil",
  "Andrei Tarkovsky",
  "Bong Joon-ho",
  "Black Mirror",
  "Celine Sciamma",
  "Children of Men",
  "Chloe Zhao",
  "Coen Brothers",
  "Christopher Nolan",
  "Claire Denis",
  "Darren Aronofsky",
  "Dark",
  "Dario Argento",
  "David Fincher",
  "Denis Villeneuve",
  "David Lynch",
  "Drive",
  "Dune",
  "Edward Yang",
  "Eternal Sunshine of the Spotless Mind",
  "Ex Machina",
  "Fallen Angels",
  "Fight Club",
  "Gaspar Noe",
  "Get Out",
  "Guillermo del Toro",
  "Greta Gerwig",
  "Hayao Miyazaki",
  "Her",
  "Hirokazu Kore-eda",
  "Interstellar",
  "In the Mood for Love",
  "Jane Campion",
  "Julia Ducournau",
  "Kogonada",
  "Krzysztof Kieslowski",
  "La Haine",
  "Lars von Trier",
  "Luca Guadagnino",
  "Mad Max: Fury Road",
  "Michael Haneke",
  "Moonlight",
  "Mandy",
  "Mulholland Drive",
  "Memories of Murder",
  "Metropolis",
  "Midsommar",
  "Minority Report",
  "Mirror",
  "Nausicaa",
  "Neon Genesis Evangelion",
  "Network",
  "Nosferatu",
  "Nicholas Winding Refn",
  "No Country for Old Men",
  "Oldboy",
  "Only Lovers Left Alive",
  "Only God Forgives",
  "Ozu",
  "Pan's Labyrinth",
  "Paprika",
  "Persona",
  "Jordan Peele",
  "Parasite",
  "Park Chan-wook",
  "Paul Thomas Anderson",
  "Perfect Blue",
  "Picnic at Hanging Rock",
  "Portrait of a Lady on Fire",
  "Possession",
  "Princess Mononoke",
  "Prisoners",
  "Punch-Drunk Love",
  "Roma",
  "Robert Eggers",
  "Ryuichi Sakamoto",
  "Quentin Tarantino",
  "Ridley Scott",
  "Requiem for a Dream",
  "Rashomon",
  "Satoshi Kon",
  "Se7en",
  "Shane Carruth",
  "Sicario",
  "Sofia Coppola",
  "Solaris",
  "Stalker",
  "Spike Jonze",
  "Studio Ghibli",
  "Stranger Things",
  "Suspiria",
  "Tarkovsky",
  "Taxi Driver",
  "The Fall",
  "The Grand Budapest Hotel",
  "The Handmaiden",
  "The Matrix",
  "The Lighthouse",
  "The Shining",
  "The Social Network",
  "The Tree of Life",
  "The Virgin Suicides",
  "The Witch",
  "There Will Be Blood",
  "Terrence Malick",
  "Twin Peaks",
  "Upstream Color",
  "Under the Skin",
  "Upgrade",
  "Villeneuve",
  "Vertigo",
  "Videodrome",
  "WALL-E",
  "Wes Anderson",
  "Woman in the Dunes",
  "Yi Yi",
  "Wong Kar-wai",
  "Yorgos Lanthimos",
  "Zhang Yimou",
  "2001: A Space Odyssey",
  "8 1/2",
  "Akira",
  "Amelie",
  "Annihilation",
  "Beau Travail",
  "Before Sunrise",
  "Being John Malkovich",
  "Blue Velvet",
  "Burning",
  "Cache",
  "Chungking Express",
  "Cinema Paradiso",
  "City of God",
  "Close-Up",
  "Columbus",
  "Decision to Leave",
  "Donnie Darko",
  "Enter the Void",
  "Eyes Wide Shut",
  "Fantastic Planet",
  "First Reformed",
  "Fitzcarraldo",
  "Ghost in the Shell",
  "Good Time",
  "Hausu",
  "Holy Motors",
  "Ikiru",
  "Incendies",
  "Inland Empire",
  "Jeanne Dielman",
  "Last Year at Marienbad",
  "Lost Highway",
  "Melancholia",
  "MirrorMask",
  "My Neighbor Totoro",
  "Nostalghia",
  "Once Upon a Time in Hollywood",
  "Orpheus",
  "Paris, Texas",
  "Picnic at Hanging Rock",
  "Playtime",
  "Ran",
  "Run Lola Run",
  "Shoplifters",
  "Singin' in the Rain",
  "Son of Saul",
  "Spirited Away",
  "Synecdoche, New York",
  "The Act of Killing",
  "The Seventh Seal",
  "The Substance",
  "The Thing",
  "Three Colors Trilogy",
  "Tokyo Story",
  "Under the Silver Lake",
  "Uncut Gems",
  "Uncle Boonmee Who Can Recall His Past Lives",
  "Wings of Desire",
] as const;

const RANDOMIZED_INFLUENCE_COUNT = 24;

function getRandomizedOptions<T>(options: readonly T[], count: number): T[] {
  const shuffled = [...new Set(options)];
  for (let index = shuffled.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1));
    [shuffled[index], shuffled[swapIndex]] = [shuffled[swapIndex], shuffled[index]];
  }

  return shuffled.slice(0, count);
}

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

  return (
    <Card className="border-border bg-card/70">
      <CardHeader className="space-y-4">
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <div className="flex h-11 w-11 items-center justify-center rounded-full bg-primary/10 text-primary">
              <Icon className="h-5 w-5" />
            </div>
            <CardTitle className="text-2xl">{meta.label}</CardTitle>
            <div className="ml-auto flex items-center gap-3">
              <Label htmlFor={`${step}-public-switch`} className="text-sm font-medium text-foreground">
                Public
              </Label>
              <Switch
                id={`${step}-public-switch`}
                checked={visibility === "published"}
                onCheckedChange={(checked) =>
                  onVisibilityChange(step, checked ? "published" : "private")
                }
                aria-label="Toggle public visibility"
              />
            </div>
          </div>
          <p className="w-full text-sm text-muted-foreground">{meta.description}</p>
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
  const [customGenre, setCustomGenre] = useState("");
  const [customInfluence, setCustomInfluence] = useState("");
  const [randomizedInfluenceOptions, setRandomizedInfluenceOptions] = useState(() =>
    getRandomizedOptions(INFLUENCE_OPTIONS, RANDOMIZED_INFLUENCE_COUNT)
  );
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

  const conceptValue = data.development?.conceptStatement || data.development?.conceptSeed || "";
  const selectedGenres =
    data.development?.genres ||
    data.genre
      .split(",")
      .map((genre) => genre.trim())
      .filter(Boolean);
  const selectedInfluences = data.development?.influences || [];
  const genreOptions = [
    ...GENRE_OPTIONS,
    ...selectedGenres.filter(
      (genre) => !GENRE_OPTIONS.includes(genre as (typeof GENRE_OPTIONS)[number])
    ),
  ];
  const influenceOptions = [
    ...randomizedInfluenceOptions,
    ...selectedInfluences.filter(
      (influence) =>
        !randomizedInfluenceOptions.includes(
          influence as (typeof randomizedInfluenceOptions)[number]
        )
    ),
  ];

  const updateConcept = (value: string) => {
    updateData({
      ...data,
      development: {
        ...data.development,
        conceptSeed: value,
        conceptStatement: value,
      },
    });
  };

  const updateGenres = (nextGenres: string[]) => {
    updateData({
      ...data,
      genre: nextGenres.join(", "),
      development: {
        ...data.development,
        genres: nextGenres,
      },
    });
  };

  const toggleGenre = (value: string) => {
    const nextGenres = selectedGenres.includes(value)
      ? selectedGenres.filter((genre) => genre !== value)
      : [...selectedGenres, value];

    updateGenres(nextGenres);
  };

  const addCustomGenre = () => {
    const value = customGenre.trim();
    if (!value || selectedGenres.includes(value)) {
      setCustomGenre("");
      return;
    }

    updateGenres([...selectedGenres, value]);
    setCustomGenre("");
  };

  const toggleInfluence = (value: string) => {
    const nextInfluences = selectedInfluences.includes(value)
      ? selectedInfluences.filter((influence) => influence !== value)
      : [...selectedInfluences, value];

    updateData({
      ...data,
      development: {
        ...data.development,
        influences: nextInfluences,
      },
    });
  };

  const addCustomInfluence = () => {
    const value = customInfluence.trim();
    if (!value || selectedInfluences.includes(value)) {
      setCustomInfluence("");
      return;
    }

    updateData({
      ...data,
      development: {
        ...data.development,
        influences: [...selectedInfluences, value],
      },
    });
    setCustomInfluence("");
  };

  const reshuffleInfluences = () => {
    setRandomizedInfluenceOptions(
      getRandomizedOptions(INFLUENCE_OPTIONS, RANDOMIZED_INFLUENCE_COUNT)
    );
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
          <div className="space-y-6">
            <div className="space-y-2">
              <Label htmlFor="concept-statement">Concept</Label>
              <Textarea
                id="concept-statement"
                value={conceptValue}
                onChange={(event) => updateConcept(event.target.value)}
                placeholder="Theme, image, mood, or story spark..."
                className="bg-background"
                rows={3}
              />
            </div>

            <div className="space-y-3">
              <Label>Genre</Label>
              <div className="flex flex-wrap gap-2">
                {genreOptions.map((genre) => (
                  <Button
                    key={genre}
                    type="button"
                    variant="outline"
                    onClick={() => toggleGenre(genre)}
                    className={cn(
                      "bg-transparent",
                      selectedGenres.includes(genre) &&
                        "border-primary bg-primary/10 text-primary hover:bg-primary/10"
                    )}
                  >
                    {genre}
                  </Button>
                ))}
              </div>
              <div className="flex gap-2">
                <Input
                  value={customGenre}
                  onChange={(event) => setCustomGenre(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      addCustomGenre();
                    }
                  }}
                  placeholder="Add your own genre"
                  className="bg-background"
                />
                <Button type="button" variant="outline" onClick={addCustomGenre} className="bg-transparent">
                  Add
                </Button>
              </div>
            </div>

            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <Label>Influences</Label>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={reshuffleInfluences}
                  className="h-8 w-8 p-0 bg-transparent"
                  aria-label="Shuffle influence suggestions"
                >
                  <Shuffle className="h-4 w-4" />
                </Button>
              </div>
              <div className="flex flex-wrap gap-2">
                {influenceOptions.map((influence) => (
                  <Button
                    key={influence}
                    type="button"
                    variant="outline"
                    onClick={() => toggleInfluence(influence)}
                    className={cn(
                      "bg-transparent",
                      selectedInfluences.includes(influence) &&
                        "border-primary bg-primary/10 text-primary hover:bg-primary/10"
                    )}
                  >
                    {influence}
                  </Button>
                ))}
              </div>
              <div className="flex gap-2">
                <Input
                  value={customInfluence}
                  onChange={(event) => setCustomInfluence(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      addCustomInfluence();
                    }
                  }}
                  placeholder="Add your own influence"
                  className="bg-background"
                />
                <Button type="button" variant="outline" onClick={addCustomInfluence} className="bg-transparent">
                  Add
                </Button>
              </div>
            </div>

            <Button
              type="button"
              onClick={() => void generateConcept()}
              disabled={loadingStep === "concept"}
            >
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
                            conceptSeed: direction.premise,
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
