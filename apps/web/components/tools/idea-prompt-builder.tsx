"use client";

import { Check, Copy, X } from "lucide-react";
import { useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { buildIdeaPrompt, defaultIdeaOptions, type IdeaPromptOptions } from "@/lib/idea-prompts";

const suggestedGenres = [
  "science fiction",
  "horror",
  "comedy",
  "drama",
  "thriller",
  "fantasy",
  "romance",
  "experimental",
];

export function IdeaPromptBuilder() {
  const [options, setOptions] = useState(defaultIdeaOptions);
  const [customGenre, setCustomGenre] = useState("");
  const [copyResult, setCopyResult] = useState<{ prompt: string; success: boolean } | null>(null);
  const outputRef = useRef<HTMLTextAreaElement>(null);
  const prompt = buildIdeaPrompt(options);
  const copied = copyResult?.prompt === prompt && copyResult.success;
  const copyFailed = copyResult?.prompt === prompt && !copyResult.success;

  function update<K extends keyof IdeaPromptOptions>(field: K, value: IdeaPromptOptions[K]) {
    setOptions((current) => ({ ...current, [field]: value }));
    setCopyResult(null);
  }

  function toggleGenre(genre: string) {
    setOptions((current) => ({
      ...current,
      genres: current.genres.includes(genre)
        ? current.genres.filter((item) => item !== genre)
        : [...current.genres, genre],
    }));
    setCopyResult(null);
  }

  function addCustomGenre() {
    const genre = customGenre.trim().toLowerCase();
    if (!genre) return;
    setOptions((current) => ({
      ...current,
      genres: current.genres.includes(genre) ? current.genres : [...current.genres, genre],
    }));
    setCustomGenre("");
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
      <div className="grid items-start gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
        <section
          aria-labelledby="builder-heading"
          className="rounded-2xl border border-border p-5 sm:p-6"
        >
          <div className="flex items-center justify-between gap-3">
            <h1 id="builder-heading" className="text-xl font-semibold">
              AI Film Idea Generator
            </h1>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setOptions({ ...defaultIdeaOptions });
                setCustomGenre("");
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
            <fieldset className="space-y-3 sm:col-span-2">
              <legend className="text-sm font-medium">Genres</legend>
              <p id="genre-help" className="text-xs text-muted-foreground">
                Select any combination, or add your own.
              </p>
              <div className="flex flex-wrap gap-2">
                {suggestedGenres.map((genre) => (
                  <Button
                    key={genre}
                    type="button"
                    variant={options.genres.includes(genre) ? "default" : "outline"}
                    size="sm"
                    aria-pressed={options.genres.includes(genre)}
                    onClick={() => toggleGenre(genre)}
                    className="rounded-full capitalize"
                  >
                    {options.genres.includes(genre) ? <Check aria-hidden="true" /> : null}
                    {genre}
                  </Button>
                ))}
                {options.genres
                  .filter((genre) => !suggestedGenres.includes(genre))
                  .map((genre) => (
                    <Button
                      key={genre}
                      type="button"
                      size="sm"
                      onClick={() => toggleGenre(genre)}
                      aria-label={`Remove ${genre} genre`}
                      className="max-w-full rounded-full"
                    >
                      <span className="truncate">{genre}</span>
                      <X aria-hidden="true" />
                    </Button>
                  ))}
              </div>
              <div className="flex gap-2">
                <Input
                  id="idea-custom-genre"
                  aria-label="Custom genre"
                  aria-describedby="genre-help"
                  value={customGenre}
                  onChange={(event) => setCustomGenre(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter" && !event.nativeEvent.isComposing) {
                      event.preventDefault();
                      addCustomGenre();
                    }
                  }}
                  placeholder="e.g. magical realism"
                />
                <Button
                  type="button"
                  variant="outline"
                  onClick={addCustomGenre}
                  disabled={!customGenre.trim()}
                >
                  Add
                </Button>
              </div>
            </fieldset>
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
