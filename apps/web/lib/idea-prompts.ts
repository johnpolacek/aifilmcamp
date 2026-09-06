export type IdeaPromptOptions = {
  duration: string;
  genres: string[];
  inspirations: string;
  instructions: string;
  count: string;
};

export const defaultIdeaOptions: IdeaPromptOptions = {
  duration: "1-minute",
  genres: [],
  inspirations: "",
  instructions: "",
  count: "5",
};

export function buildIdeaPrompt(options: IdeaPromptOptions): string {
  const film = [options.duration.trim(), options.genres.join(" / "), "film"]
    .filter(Boolean)
    .join(" ");
  const inspirations = options.inspirations
    .split("\n")
    .map((item) => item.trim())
    .filter(Boolean);

  return [
    `Give me ${options.count} distinct, original ideas for a ${film}.`,
    options.genres.length > 1
      ? `Blend these genres in each idea: ${options.genres.join(", ")}.`
      : "",
    inspirations.length
      ? `Draw inspiration from:\n${inspirations.map((item) => `- ${item}`).join("\n")}\nUse these as creative starting points for an original story.`
      : "Explore a variety of creative directions.",
    options.instructions.trim() ? `Additional instructions:\n${options.instructions.trim()}` : "",
    "For each idea, include:\n- A working title.\n- A one-sentence logline with a protagonist, a goal, and a complication.\n- A brief beginning, middle, and ending that fit the runtime.\n- A memorable visual moment.\n- A practical note on making it with AI filmmaking tools, including any visual consistency challenges.",
    "Keep the ideas specific, visually driven, and achievable at the requested length. Give each a different premise. Finish by recommending the strongest idea and briefly explaining why. Wait for me to choose an idea before expanding it into a screenplay or shot list.",
  ]
    .filter(Boolean)
    .join("\n\n");
}
