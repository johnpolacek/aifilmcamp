export type IdeaPromptOptions = {
  duration: string;
  genre: string;
  inspirations: string;
  instructions: string;
  count: string;
};

export const defaultIdeaOptions: IdeaPromptOptions = {
  duration: "1-minute",
  genre: "",
  inspirations: "",
  instructions: "",
  count: "5",
};

export const ideaPresets = [
  {
    name: "A twist in 30 seconds",
    description: "A tiny thriller with a big reveal.",
    options: {
      duration: "30-second",
      genre: "thriller",
      inspirations: "Twilight Zone-style irony\nAn ordinary object that feels out of place",
      instructions:
        "Use one location, one character, and no dialogue. End with a surprising visual reveal.",
      count: "5",
    },
  },
  {
    name: "Small sci-fi, big feeling",
    description: "Human stories in unfamiliar worlds.",
    options: {
      duration: "2-minute",
      genre: "science fiction",
      inspirations:
        "Retro-futurist illustration\nThe feeling of missing someone\nAn abandoned space station",
      instructions:
        "Focus on an intimate emotional story with no more than two characters. Make the science-fiction premise easy to understand visually.",
      count: "5",
    },
  },
  {
    name: "Everyday absurdity",
    description: "Turn a familiar routine into a comedy.",
    options: {
      duration: "1-minute",
      genre: "comedy",
      inspirations: "Silent-film physical comedy\nA mundane daily ritual taken too far",
      instructions:
        "Build around one simple visual joke that escalates three times. Keep dialogue minimal and finish with a strong payoff.",
      count: "5",
    },
  },
] satisfies { name: string; description: string; options: IdeaPromptOptions }[];

export function buildIdeaPrompt(options: IdeaPromptOptions): string {
  const film = [options.duration.trim(), options.genre.trim(), "film"].filter(Boolean).join(" ");
  const inspirations = options.inspirations
    .split("\n")
    .map((item) => item.trim())
    .filter(Boolean);

  return [
    `Give me ${options.count} distinct, original ideas for a ${film}.`,
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
