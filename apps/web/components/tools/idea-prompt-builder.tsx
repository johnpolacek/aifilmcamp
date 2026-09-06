"use client";

import { Check, Copy } from "lucide-react";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  buildIdeaPrompt,
  defaultIdeaOptions,
  type IdeaPromptOptions,
  ideaPresets,
} from "@/lib/idea-prompts";

export function IdeaPromptBuilder() {
  const [options, setOptions] = useState(defaultIdeaOptions);
  const [copyResult, setCopyResult] = useState<{ prompt: string; success: boolean } | null>(null);
  const outputRef = useRef<HTMLTextAreaElement>(null);
  const prompt = buildIdeaPrompt(options);
  const copied = copyResult?.prompt === prompt && copyResult.success;
  const copyFailed = copyResult?.prompt === prompt && !copyResult.success;

  function update(field: keyof IdeaPromptOptions, value: string) {
    setOptions((current) => ({ ...current, [field]: value }));
    setCopyResult(null);
  }

  async function copyPrompt() {
    try {
      await navigator.clipboard.writeText(prompt);
      setCopyResult({ prompt, success: true });
    } catch {
      setCopyResult({ prompt, success: false });
      outputRef.current?.focus();
      outputRef.current?.select();
    }
  }

  return (
    <div className="mt-8">
      <section aria-labelledby="presets-heading">
        <h2 id="presets-heading" className="text-sm font-semibold">
          Try a starting point
        </h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Each preset fills in the builder. Make it your own before copying.
        </p>
        <div className="mt-3 grid gap-3 sm:grid-cols-3">
          {ideaPresets.map((preset) => (
            <button
              key={preset.name}
              type="button"
              onClick={() => {
                setOptions({ ...preset.options });
                setCopyResult(null);
              }}
              className="rounded-xl border border-border bg-card p-4 text-left transition-colors hover:border-primary/60 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring"
            >
              <span className="block text-sm font-semibold">{preset.name}</span>
              <span className="mt-1 block text-sm text-muted-foreground">{preset.description}</span>
            </button>
          ))}
        </div>
      </section>

      <div className="mt-6 grid items-start gap-6 lg:grid-cols-2">
        <section
          aria-labelledby="builder-heading"
          className="rounded-2xl border border-border p-5 sm:p-6"
        >
          <div className="flex items-center justify-between gap-3">
            <h2 id="builder-heading" className="text-xl font-semibold">
              Shape your brief
            </h2>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setOptions({ ...defaultIdeaOptions });
                setCopyResult(null);
              }}
            >
              Reset
            </Button>
          </div>
          <div className="mt-6 grid gap-5 sm:grid-cols-2">
            <div className="space-y-2">
              <label htmlFor="idea-duration" className="text-sm font-medium">
                Film duration
              </label>
              <Input
                id="idea-duration"
                list="idea-durations"
                value={options.duration}
                onChange={(event) => update("duration", event.target.value)}
                placeholder="e.g. 90-second"
              />
              <datalist id="idea-durations">
                {["15-second", "30-second", "1-minute", "2-minute", "5-minute", "10-minute"].map(
                  (duration) => (
                    <option key={duration} value={duration} />
                  )
                )}
              </datalist>
            </div>
            <div className="space-y-2">
              <label htmlFor="idea-genre" className="text-sm font-medium">
                Genre
              </label>
              <Input
                id="idea-genre"
                list="idea-genres"
                value={options.genre}
                onChange={(event) => update("genre", event.target.value)}
                placeholder="Any genre, or mix a few"
              />
              <datalist id="idea-genres">
                {[
                  "science fiction",
                  "horror",
                  "comedy",
                  "drama",
                  "thriller",
                  "fantasy",
                  "romance",
                  "experimental",
                ].map((genre) => (
                  <option key={genre} value={genre} />
                ))}
              </datalist>
            </div>
            <p className="-mt-2 text-xs text-muted-foreground sm:col-span-2">
              Choose a suggestion or type your own duration and genre.
            </p>
            <div className="space-y-2 sm:col-span-2">
              <label htmlFor="idea-inspirations" className="text-sm font-medium">
                Inspirations <span className="font-normal text-muted-foreground">(optional)</span>
              </label>
              <Textarea
                id="idea-inspirations"
                aria-describedby="inspiration-help"
                value={options.inspirations}
                onChange={(event) => update("inspirations", event.target.value)}
                className="min-h-28"
                placeholder={"A favorite film or filmmaker\nAn image, a song, a place, a feeling…"}
              />
              <p id="inspiration-help" className="text-xs text-muted-foreground">
                Add one inspiration per line.
              </p>
            </div>
            <div className="space-y-2 sm:col-span-2">
              <label htmlFor="idea-instructions" className="text-sm font-medium">
                Other instructions{" "}
                <span className="font-normal text-muted-foreground">(optional)</span>
              </label>
              <Textarea
                id="idea-instructions"
                value={options.instructions}
                onChange={(event) => update("instructions", event.target.value)}
                className="min-h-28"
                placeholder="e.g. One location, no dialogue, a hopeful ending. Avoid space travel."
              />
            </div>
            <div className="space-y-2">
              <label htmlFor="idea-count" className="block text-sm font-medium">
                Number of ideas
              </label>
              <select
                id="idea-count"
                value={options.count}
                onChange={(event) => update("count", event.target.value)}
                className="h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring"
              >
                {[3, 5, 10].map((count) => (
                  <option key={count} value={count}>
                    {count} ideas
                  </option>
                ))}
              </select>
            </div>
          </div>
        </section>

        <section
          aria-labelledby="prompt-heading"
          className="rounded-2xl border border-primary/30 bg-card p-5 sm:p-6 lg:sticky lg:top-24"
        >
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 id="prompt-heading" className="text-xl font-semibold">
              Your prompt
            </h2>
            <Button onClick={copyPrompt} className="gap-2">
              {copied ? <Check aria-hidden="true" /> : <Copy aria-hidden="true" />}
              {copied ? "Copied!" : "Copy prompt"}
            </Button>
          </div>
          <p id="prompt-help" className="mt-3 text-sm text-muted-foreground">
            Copy this into your own LLM agent to generate the ideas. It updates as you change the
            brief.
          </p>
          <Textarea
            ref={outputRef}
            aria-label="Generated idea prompt"
            aria-describedby="prompt-help"
            readOnly
            value={prompt}
            className="mt-5 min-h-96 resize-y bg-background font-mono text-sm leading-relaxed"
          />
          <p role="status" className="mt-3 min-h-5 text-sm text-muted-foreground">
            {copyFailed
              ? "Clipboard unavailable. The prompt is selected; press ⌘C on Mac or Ctrl+C to copy."
              : copied
                ? "Ready to paste into your agent."
                : "No account or API key needed."}
          </p>
        </section>
      </div>
    </div>
  );
}
