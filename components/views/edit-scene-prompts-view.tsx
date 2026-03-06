"use client";

import { ArrowLeft, Bot, Copy, Plus, Save, Trash2 } from "lucide-react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import type { Character, Location } from "@/components/project-form";
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
import type { PromptShot, Scene } from "@/lib/scenes-client";
import { createNewPromptShot } from "@/lib/scenes-client";

interface EditScenePromptsViewProps {
  scene: Scene;
  projectId: string;
  projectTitle: string;
  characters: Character[];
  locations: Location[];
}

function buildScenePromptSummary(scene: Scene): string {
  return (scene.promptShots || [])
    .map(
      (shot) =>
        `Shot ${shot.shotNumber}: ${shot.title}\n${shot.prompt}\nFraming: ${shot.framing}\nCamera: ${shot.cameraMovement}\nAction: ${shot.action}`
    )
    .join("\n\n");
}

export function EditScenePromptsView({
  scene,
  projectId,
  projectTitle,
  characters,
  locations,
}: EditScenePromptsViewProps) {
  const searchParams = useSearchParams();
  const [draft, setDraft] = useState<Scene>({
    ...scene,
    promptShots: scene.promptShots || [],
  });
  const [isSaving, setIsSaving] = useState(false);
  const [isGenerating, setIsGenerating] = useState(false);
  const returnStep = searchParams.get("returnStep");
  const backHref = returnStep
    ? `/dashboard/projects/${projectId}/edit?step=${returnStep}`
    : `/dashboard/projects/${projectId}/edit`;

  const updatePromptShot = (index: number, field: keyof PromptShot, value: string | number) => {
    const promptShots = [...(draft.promptShots || [])];
    promptShots[index] = { ...promptShots[index], [field]: value };
    setDraft({ ...draft, promptShots });
  };

  const saveScene = async () => {
    setIsSaving(true);
    try {
      const response = await fetch(`/api/scenes/${draft.id}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          projectId,
          scene: {
            ...draft,
            updatedAt: new Date().toISOString(),
          },
        }),
      });
      const result = await response.json();
      if (!result.success) {
        throw new Error(result.error || "Failed to save scene");
      }
      toast.success("Scene prompts saved");
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Failed to save scene");
    } finally {
      setIsSaving(false);
    }
  };

  const generatePrompts = async () => {
    setIsGenerating(true);
    try {
      const { generateShotPrompts } = await import("@/lib/actions/development");
      const promptShots = await generateShotPrompts(
        {
          title: projectTitle,
          screenplayText: draft.screenplay,
          characters,
          setting: { locations },
        },
        draft
      );
      setDraft({ ...draft, promptShots });
      toast.success("Generated scene prompts");
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Failed to generate prompts");
    } finally {
      setIsGenerating(false);
    }
  };

  const copyPromptPacket = async () => {
    const text = buildScenePromptSummary(draft);
    await navigator.clipboard.writeText(text);
    toast.success("Copied prompt packet");
  };

  return (
    <div className="min-h-screen bg-background pt-24 pb-16">
      <div className="container mx-auto max-w-5xl px-4 lg:px-8">
        <div className="mb-6 flex items-center justify-between gap-4">
          <Link
            href={backHref}
            className="inline-flex items-center gap-2 text-primary transition-opacity hover:opacity-80"
          >
            <ArrowLeft className="h-4 w-4" />
            <span className="text-sm font-semibold">Back to Project</span>
          </Link>
          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={copyPromptPacket}>
              <Copy className="mr-2 h-4 w-4" />
              Copy Prompts
            </Button>
            <Button type="button" onClick={saveScene} disabled={isSaving}>
              <Save className="mr-2 h-4 w-4" />
              {isSaving ? "Saving..." : "Save Scene"}
            </Button>
          </div>
        </div>

        <div className="mb-8">
          <h1 className="text-3xl font-bold">{draft.title}</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Prompt-first scene planning for {projectTitle}
          </p>
        </div>

        <div className="grid gap-6 lg:grid-cols-[1.1fr_0.9fr]">
          <div className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Scene Details</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid gap-4 md:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Title</Label>
                    <Input
                      value={draft.title}
                      onChange={(event) => setDraft({ ...draft, title: event.target.value })}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Location</Label>
                    <Select
                      value={draft.locationId || ""}
                      onValueChange={(value) =>
                        setDraft({ ...draft, locationId: value === "__none" ? undefined : value })
                      }
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select location" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__none">No location</SelectItem>
                        {locations.map((location) => (
                          <SelectItem key={location.name} value={location.name}>
                            {location.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Summary</Label>
                  <Textarea
                    value={draft.summary || ""}
                    onChange={(event) => setDraft({ ...draft, summary: event.target.value })}
                    rows={3}
                  />
                </div>
                <div className="grid gap-4 md:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Dramatic Purpose</Label>
                    <Textarea
                      value={draft.dramaticPurpose || ""}
                      onChange={(event) =>
                        setDraft({ ...draft, dramaticPurpose: event.target.value })
                      }
                      rows={2}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Emotional Beat</Label>
                    <Textarea
                      value={draft.emotionalBeat || ""}
                      onChange={(event) =>
                        setDraft({ ...draft, emotionalBeat: event.target.value })
                      }
                      rows={2}
                    />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Visual Intent</Label>
                  <Textarea
                    value={draft.visualIntent || ""}
                    onChange={(event) => setDraft({ ...draft, visualIntent: event.target.value })}
                    rows={2}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Scene Characters</Label>
                  <div className="flex flex-wrap gap-2">
                    {characters.map((character) => {
                      const selected = draft.characters.includes(character.name);
                      return (
                        <button
                          key={character.name}
                          type="button"
                          onClick={() =>
                            setDraft({
                              ...draft,
                              characters: selected
                                ? draft.characters.filter((name) => name !== character.name)
                                : [...draft.characters, character.name],
                            })
                          }
                          className={`rounded-full border px-3 py-1.5 text-sm ${selected ? "border-primary bg-primary text-primary-foreground" : "border-border bg-background"}`}
                        >
                          {character.name}
                        </button>
                      );
                    })}
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Scene Screenplay</Label>
                  <Textarea
                    value={draft.screenplay}
                    onChange={(event) => setDraft({ ...draft, screenplay: event.target.value })}
                    rows={10}
                    className="font-mono text-sm"
                  />
                </div>
              </CardContent>
            </Card>
          </div>

          <div className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Shot Breakdown with Prompts</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="flex flex-wrap gap-2">
                  <Button type="button" onClick={generatePrompts} disabled={isGenerating}>
                    <Bot className="mr-2 h-4 w-4" />
                    {isGenerating ? "Generating..." : "Generate Shot Prompts"}
                  </Button>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() =>
                      setDraft({
                        ...draft,
                        promptShots: [...(draft.promptShots || []), createNewPromptShot((draft.promptShots?.length || 0) + 1)],
                      })
                    }
                  >
                    <Plus className="mr-2 h-4 w-4" />
                    Add Shot
                  </Button>
                </div>

                <div className="space-y-4">
                  {(draft.promptShots || []).map((shot, index) => (
                    <div key={shot.id} className="rounded-lg border border-border bg-background p-4">
                      <div className="mb-3 flex items-center justify-between gap-3">
                        <Input
                          value={shot.title}
                          onChange={(event) => updatePromptShot(index, "title", event.target.value)}
                        />
                        <Button
                          type="button"
                          variant="ghost"
                          size="icon"
                          onClick={() =>
                            setDraft({
                              ...draft,
                              promptShots: draft.promptShots?.filter((promptShot) => promptShot.id !== shot.id),
                            })
                          }
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                      <div className="grid gap-3 md:grid-cols-3">
                        <Input
                          value={shot.framing}
                          onChange={(event) => updatePromptShot(index, "framing", event.target.value)}
                          placeholder="Framing"
                        />
                        <Input
                          value={shot.cameraMovement}
                          onChange={(event) =>
                            updatePromptShot(index, "cameraMovement", event.target.value)
                          }
                          placeholder="Camera movement"
                        />
                        <Input
                          type="number"
                          min={1}
                          max={15}
                          value={shot.durationEstimateSeconds || 4}
                          onChange={(event) =>
                            updatePromptShot(index, "durationEstimateSeconds", Number(event.target.value))
                          }
                          placeholder="Duration"
                        />
                      </div>
                      <Textarea
                        value={shot.action}
                        onChange={(event) => updatePromptShot(index, "action", event.target.value)}
                        placeholder="What happens in the shot?"
                        rows={2}
                        className="mt-3"
                      />
                      <Textarea
                        value={shot.continuityNotes || ""}
                        onChange={(event) =>
                          updatePromptShot(index, "continuityNotes", event.target.value)
                        }
                        placeholder="Continuity notes"
                        rows={2}
                        className="mt-3"
                      />
                      <Textarea
                        value={shot.prompt}
                        onChange={(event) => updatePromptShot(index, "prompt", event.target.value)}
                        placeholder="Final copyable prompt"
                        rows={5}
                        className="mt-3 font-mono text-sm"
                      />
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
