/**
 * Screenplay Parser
 * Parses screenplay text into individual scenes and structured elements
 * Supports standard screenplay format with INT/EXT scene headings
 */

import {
  generateElementId,
  type ScreenplayElement,
  type ScreenplayElementType,
} from "@/lib/types/screenplay";

export interface ParsedScene {
  sceneNumber: number;
  title: string;
  heading: string; // Original scene heading (e.g., "INT. COFFEE SHOP - DAY")
  content: string; // Scene content (action, dialogue)
  characters: string[]; // Characters mentioned in dialogue
  startIndex: number; // Character position in original text
  endIndex: number; // Character position in original text
}

export interface ParseResult {
  success: boolean;
  scenes: ParsedScene[];
  error?: string;
}

/**
 * Scene heading patterns
 * Matches standard screenplay format:
 * - INT. LOCATION - TIME
 * - EXT. LOCATION - TIME
 * - INT./EXT. LOCATION - TIME
 * - I/E. LOCATION - TIME
 */
const _SCENE_HEADING_PATTERNS = [
  /^(INT\.|EXT\.|INT\/EXT\.|I\/E\.|INTERIOR|EXTERIOR)\s+(.+?)(?:\s*[-–—]\s*(.+?))?$/im,
  /^(SCENE\s+\d+[.:])?\s*(INT\.|EXT\.|INT\/EXT\.|I\/E\.)\s+(.+?)(?:\s*[-–—]\s*(.+?))?$/im,
];

/**
 * Character name pattern
 * Matches character names in dialogue (ALL CAPS followed by dialogue)
 */
const CHARACTER_NAME_PATTERN = /^([A-Z][A-Z\s.']+)(?:\s*\(.*?\))?\s*$/;

/**
 * Check if a line is a scene heading
 */
function isSceneHeading(line: string): boolean {
  const trimmedLine = line.trim().toUpperCase();
  return (
    trimmedLine.startsWith("INT.") ||
    trimmedLine.startsWith("EXT.") ||
    trimmedLine.startsWith("INT/EXT.") ||
    trimmedLine.startsWith("I/E.") ||
    trimmedLine.startsWith("INTERIOR") ||
    trimmedLine.startsWith("EXTERIOR")
  );
}

/**
 * Extract a title from a scene heading
 */
function extractTitle(heading: string): string {
  // Remove the INT./EXT. prefix
  let title = heading.replace(/^(INT\.|EXT\.|INT\/EXT\.|I\/E\.|INTERIOR|EXTERIOR)\s*/i, "").trim();

  // Remove time of day suffix if present
  title = title
    .replace(
      /\s*[-–—]\s*(DAY|NIGHT|MORNING|EVENING|AFTERNOON|LATER|CONTINUOUS|SAME|MOMENTS LATER).*$/i,
      ""
    )
    .trim();

  // Capitalize properly
  return title
    .split(" ")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(" ");
}

/**
 * Extract character names from scene content (dialogue cues only)
 */
function extractCharactersFromDialogue(content: string): string[] {
  const lines = content.split("\n");
  const characters = new Set<string>();

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();

    // Check if this line looks like a character name (all caps, short, followed by dialogue)
    if (
      line.length > 0 &&
      line.length < 40 &&
      line === line.toUpperCase() &&
      !isSceneHeading(line) &&
      !line.startsWith("(") &&
      !line.endsWith(")") &&
      !/^\d+\.?\s*$/.test(line) && // Not just a number
      !/^(FADE|CUT|DISSOLVE|SMASH|MATCH|JUMP|TIME|CONTINUED|MORE|CONT'D)/.test(line)
    ) {
      // This might be a character name
      const match = line.match(CHARACTER_NAME_PATTERN);
      if (match) {
        // Clean up the character name
        let characterName = match[1].trim();
        // Remove parentheticals like (V.O.), (O.S.), etc.
        characterName = characterName.replace(/\s*\(.*?\)\s*/g, "").trim();
        if (characterName.length > 1 && characterName.length < 30) {
          characters.add(characterName);
        }
      }
    }
  }

  return Array.from(characters);
}

/**
 * Match project character names found in scene content (narrative/action lines)
 * Returns character names that appear in the scene
 */
function matchCharactersInNarrative(content: string, projectCharacterNames: string[]): string[] {
  if (projectCharacterNames.length === 0) return [];

  const matchedCharacters = new Set<string>();
  const contentLower = content.toLowerCase();

  for (const characterName of projectCharacterNames) {
    if (!characterName) continue;

    // Create a word-boundary regex to match the character name
    // This prevents matching "MARK" inside "MARKER" or "BOOKMARK"
    const namePattern = new RegExp(
      `\\b${characterName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`,
      "i"
    );

    if (namePattern.test(contentLower) || namePattern.test(content)) {
      matchedCharacters.add(characterName);
    }
  }

  return Array.from(matchedCharacters);
}

/**
 * Extract all character references from scene content
 * Combines dialogue cues and narrative mentions of project characters
 */
function extractCharacters(content: string, projectCharacterNames: string[] = []): string[] {
  // Get characters from dialogue cues (ALL CAPS names)
  const dialogueCharacters = extractCharactersFromDialogue(content);

  // Get characters mentioned in narrative (matched against project characters)
  const narrativeCharacters = matchCharactersInNarrative(content, projectCharacterNames);

  // Combine both, using a Set to avoid duplicates
  const allCharacters = new Set<string>();

  // Add dialogue characters (these are from the screenplay itself)
  for (const char of dialogueCharacters) {
    allCharacters.add(char);
  }

  // Add narrative matches (these are project character names)
  for (const char of narrativeCharacters) {
    allCharacters.add(char);
  }

  return Array.from(allCharacters);
}

/**
 * Parse screenplay text into scenes
 * @param text - The screenplay text to parse
 * @param projectCharacterNames - Optional list of project character names to match in narrative
 */
export function parseScreenplay(text: string, projectCharacterNames: string[] = []): ParseResult {
  if (!text || typeof text !== "string") {
    return {
      success: false,
      scenes: [],
      error: "No screenplay text provided",
    };
  }

  try {
    const lines = text.split("\n");
    const scenes: ParsedScene[] = [];
    let currentScene: Partial<ParsedScene> | null = null;
    let currentContent: string[] = [];
    let sceneNumber = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmedLine = line.trim();

      if (isSceneHeading(trimmedLine)) {
        // Save the previous scene if exists
        if (currentScene?.heading) {
          const content = currentContent.join("\n").trim();
          scenes.push({
            sceneNumber: currentScene.sceneNumber || sceneNumber,
            title: currentScene.title || `Scene ${sceneNumber}`,
            heading: currentScene.heading,
            content,
            characters: extractCharacters(content, projectCharacterNames),
            startIndex: currentScene.startIndex || 0,
            endIndex: text.indexOf(trimmedLine, currentScene.startIndex || 0),
          });
        }

        // Start a new scene
        sceneNumber++;
        const startIndex = text.indexOf(
          trimmedLine,
          scenes.length > 0 ? scenes[scenes.length - 1].endIndex : 0
        );

        currentScene = {
          sceneNumber,
          heading: trimmedLine,
          title: extractTitle(trimmedLine),
          startIndex,
        };
        currentContent = [];
      } else if (currentScene) {
        // Add to current scene content
        currentContent.push(line);
      }
    }

    // Don't forget the last scene
    if (currentScene?.heading) {
      const content = currentContent.join("\n").trim();
      scenes.push({
        sceneNumber: currentScene.sceneNumber || sceneNumber,
        title: currentScene.title || `Scene ${sceneNumber}`,
        heading: currentScene.heading,
        content,
        characters: extractCharacters(content, projectCharacterNames),
        startIndex: currentScene.startIndex || 0,
        endIndex: text.length,
      });
    }

    return {
      success: true,
      scenes,
    };
  } catch (error) {
    console.error("[parseScreenplay] Error:", JSON.stringify({ error }, null, 2));
    return {
      success: false,
      scenes: [],
      error: error instanceof Error ? error.message : "Failed to parse screenplay",
    };
  }
}

/**
 * Extract all unique character names from screenplay text
 * Returns an array of character names found in dialogue cues
 * Only includes characters who speak at least minDialogueCount times (default: 3)
 */
export function extractAllCharacters(text: string, minDialogueCount: number = 3): string[] {
  if (!text || typeof text !== "string") return [];

  const lines = text.split("\n");
  const characterCounts = new Map<string, number>();

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();

    // Check if this line looks like a character name (all caps, short)
    if (
      line.length > 0 &&
      line.length < 40 &&
      line === line.toUpperCase() &&
      !isSceneHeading(line) &&
      !line.startsWith("(") &&
      !line.endsWith(")") &&
      !/^\d+\.?\s*$/.test(line) && // Not just a number
      !/^(FADE|CUT|DISSOLVE|SMASH|MATCH|JUMP|TIME|CONTINUED|MORE|CONT'D|THE END|END CREDITS|CREDITS ROLL)/.test(
        line
      )
    ) {
      const match = line.match(CHARACTER_NAME_PATTERN);
      if (match) {
        let characterName = match[1].trim();
        // Remove parentheticals like (V.O.), (O.S.), etc.
        characterName = characterName.replace(/\s*\(.*?\)\s*/g, "").trim();
        if (characterName.length > 1 && characterName.length < 30) {
          // Count occurrences instead of just adding to a set
          characterCounts.set(characterName, (characterCounts.get(characterName) || 0) + 1);
        }
      }
    }
  }

  // Filter to only include characters with at least minDialogueCount speaking parts
  // Sort by dialogue count (descending) so characters who speak most appear first
  const characters: Array<{ name: string; count: number }> = [];
  for (const [name, count] of characterCounts) {
    if (count >= minDialogueCount) {
      characters.push({ name, count });
    }
  }

  // Sort by count descending, then alphabetically for ties
  characters.sort((a, b) => {
    if (b.count !== a.count) {
      return b.count - a.count;
    }
    return a.name.localeCompare(b.name);
  });

  return characters.map((c) => c.name);
}

/**
 * Extract all unique locations from screenplay text
 * Returns an array of location names from scene headings
 */
export function extractAllLocations(text: string): string[] {
  if (!text || typeof text !== "string") return [];

  const lines = text.split("\n");
  const locations = new Set<string>();

  for (const line of lines) {
    const trimmedLine = line.trim();
    if (isSceneHeading(trimmedLine)) {
      // Extract location from scene heading
      let location = trimmedLine
        .replace(/^(INT\.|EXT\.|INT\/EXT\.|I\/E\.|INTERIOR|EXTERIOR)\s*/i, "")
        .trim();

      // Remove time of day suffix
      location = location
        .replace(
          /\s*[-–—]\s*(DAY|NIGHT|MORNING|EVENING|AFTERNOON|LATER|CONTINUOUS|SAME|MOMENTS LATER).*$/i,
          ""
        )
        .trim();

      if (location.length > 0) {
        // Title case the location for better display
        location = location
          .split(" ")
          .map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
          .join(" ");
        locations.add(location);
      }
    }
  }

  return Array.from(locations).sort();
}

/**
 * Extract location key from scene heading for deduplication
 * Normalizes location by removing INT./EXT. prefix and time suffix
 */
export function extractLocationKey(heading: string): string {
  // Remove INT./EXT. prefix
  let location = heading
    .replace(/^(INT\.|EXT\.|INT\/EXT\.|I\/E\.|INTERIOR|EXTERIOR)\s*/i, "")
    .trim();

  // Remove time of day suffix
  location = location
    .replace(
      /\s*[-–—]\s*(DAY|NIGHT|MORNING|EVENING|AFTERNOON|LATER|CONTINUOUS|SAME|MOMENTS LATER).*$/i,
      ""
    )
    .trim();

  // Normalize to lowercase for comparison
  return location.toLowerCase();
}

/**
 * Label scenes at the same location with numbers (#1, #2, etc.)
 * Keeps scenes separate but adds numbering when there are multiple scenes at the same location
 */
export function labelDuplicateLocationScenes(parsedScenes: ParsedScene[]): ParsedScene[] {
  // First pass: count occurrences of each location
  const locationCounts = new Map<string, number>();
  for (const scene of parsedScenes) {
    const locationKey = extractLocationKey(scene.heading);
    locationCounts.set(locationKey, (locationCounts.get(locationKey) || 0) + 1);
  }

  // Second pass: track current index for each location and label scenes
  const locationCurrentIndex = new Map<string, number>();
  const labeledScenes: ParsedScene[] = [];

  for (let i = 0; i < parsedScenes.length; i++) {
    const scene = parsedScenes[i];
    const locationKey = extractLocationKey(scene.heading);
    const totalCount = locationCounts.get(locationKey) || 1;

    if (totalCount > 1) {
      // Multiple scenes at this location, add numbering
      const currentIndex = (locationCurrentIndex.get(locationKey) || 0) + 1;
      locationCurrentIndex.set(locationKey, currentIndex);

      labeledScenes.push({
        ...scene,
        sceneNumber: i + 1,
        title: `${scene.title} #${currentIndex}`,
      });
    } else {
      // Single scene at this location, no numbering needed
      labeledScenes.push({
        ...scene,
        sceneNumber: i + 1,
      });
    }
  }

  return labeledScenes;
}

/**
 * Match extracted location key to project location names
 * Returns the matching location name or undefined
 */
function matchLocationToProject(
  heading: string,
  projectLocationNames: string[]
): string | undefined {
  if (projectLocationNames.length === 0) return undefined;

  const locationKey = extractLocationKey(heading).toLowerCase();
  if (!locationKey) return undefined;

  // Try exact match first (case-insensitive)
  for (const locationName of projectLocationNames) {
    if (locationName.toLowerCase() === locationKey) {
      return locationName;
    }
  }

  // Try partial match (location key contains or is contained in project location)
  for (const locationName of projectLocationNames) {
    const lowerName = locationName.toLowerCase();
    if (locationKey.includes(lowerName) || lowerName.includes(locationKey)) {
      return locationName;
    }
  }

  return undefined;
}

/**
 * Convert parsed scenes to Scene objects for storage
 */
export function parsedScenesToScenes(
  projectId: string,
  parsedScenes: ParsedScene[],
  labelDuplicates: boolean = true,
  projectLocationNames: string[] = []
): Array<{
  id: string;
  projectId: string;
  sceneNumber: number;
  title: string;
  screenplay: string;
  characters: string[];
  locationId?: string;
  shots: [];
  audioTracks: [];
  generatedImages: [];
  generatedVideos: [];
  createdAt: string;
  updatedAt: string;
}> {
  const now = new Date().toISOString();

  // Label duplicate location scenes with #1, #2, etc. if requested
  const scenesToProcess = labelDuplicates
    ? labelDuplicateLocationScenes(parsedScenes)
    : parsedScenes;

  return scenesToProcess.map((parsed) => {
    // Try to match the scene heading to a project location
    const matchedLocation = matchLocationToProject(parsed.heading, projectLocationNames);

    return {
      id: `scene-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
      projectId,
      sceneNumber: parsed.sceneNumber,
      title: parsed.title,
      screenplay: `${parsed.heading}\n\n${parsed.content}`,
      summary: parsed.content.split(/\n+/).slice(0, 2).join(" ").trim(),
      dramaticPurpose: "",
      emotionalBeat: "",
      visualIntent: "",
      characters: parsed.characters,
      locationId: matchedLocation,
      promptShots: [],
      shots: [],
      audioTracks: [],
      generatedImages: [],
      generatedVideos: [],
      createdAt: now,
      updatedAt: now,
    };
  });
}

/**
 * Transition patterns (CUT TO:, FADE OUT., etc.)
 */
const TRANSITION_PATTERNS = [
  /^(CUT TO|FADE IN|FADE OUT|FADE TO|DISSOLVE TO|SMASH CUT TO|MATCH CUT TO|JUMP CUT TO|TIME CUT|FLASH CUT TO|IRIS IN|IRIS OUT|WIPE TO):?\.?$/i,
  /^(THE END|END CREDITS|CREDITS ROLL)\.?$/i,
];

/**
 * Check if a line is a transition
 */
function isTransition(line: string): boolean {
  const trimmed = line.trim();
  return TRANSITION_PATTERNS.some((pattern) => pattern.test(trimmed));
}

/**
 * Check if a line is a character name (for dialogue)
 * Character names are ALL CAPS, optionally with (V.O.), (O.S.), etc.
 */
function isCharacterName(line: string, nextLine?: string): boolean {
  const trimmed = line.trim();

  // Must be relatively short
  if (trimmed.length < 2 || trimmed.length > 40) return false;

  // Remove parenthetical extensions like (V.O.), (O.S.), (CONT'D)
  const withoutExtension = trimmed.replace(/\s*\([^)]+\)\s*$/, "").trim();

  // Must be all uppercase letters, spaces, apostrophes, and periods
  if (!/^[A-Z\s'.]+$/.test(withoutExtension)) return false;

  // Should not be a scene heading or transition
  if (isSceneHeading(trimmed) || isTransition(trimmed)) return false;

  // Common non-character ALL CAPS lines to exclude
  const excludePatterns = [/^(CONTINUED|MORE|CONT'D)$/i, /^\d+$/, /^(V\.O\.|O\.S\.|O\.C\.)$/];
  if (excludePatterns.some((p) => p.test(withoutExtension))) return false;

  // If there's a next line, it should look like dialogue or parenthetical
  if (nextLine !== undefined) {
    const nextTrimmed = nextLine.trim();
    // Next line should have content (dialogue or parenthetical)
    if (nextTrimmed.length === 0) return false;
  }

  return true;
}

/**
 * Check if a line is a parenthetical
 */
function isParenthetical(line: string): boolean {
  const trimmed = line.trim();
  return trimmed.startsWith("(") && trimmed.endsWith(")");
}

/**
 * Parse screenplay text into structured elements
 * This is the main function for converting plain text to JSON structure
 */
export function parseScreenplayToElements(text: string): ScreenplayElement[] {
  if (!text || typeof text !== "string") {
    return [];
  }

  const lines = text.split("\n");
  const _linesToLog = lines.slice(0, 40);
  const elements: ScreenplayElement[] = [];

  let i = 0;
  let lastWasCharacter = false;
  let lastWasDialogue = false;

  while (i < lines.length) {
    const line = lines[i];
    const trimmedLine = line.trim();
    const nextLine = i + 1 < lines.length ? lines[i + 1] : undefined;

    // Skip empty lines but reset dialogue context after empty lines
    if (trimmedLine === "") {
      // Check for multiple consecutive empty lines
      let emptyCount = 1;
      let j = i + 1;
      while (j < lines.length && lines[j].trim() === "") {
        emptyCount++;
        j++;
      }

      // Reset dialogue/character context after any empty line
      // This ensures action lines after dialogue aren't misclassified
      if (emptyCount >= 1) {
        lastWasCharacter = false;
        lastWasDialogue = false;
      }

      i++;
      continue;
    }

    let elementType: ScreenplayElementType;

    // Determine element type
    if (isSceneHeading(trimmedLine)) {
      elementType = "scene_heading";
      lastWasCharacter = false;
      lastWasDialogue = false;
    } else if (isTransition(trimmedLine)) {
      elementType = "transition";
      lastWasCharacter = false;
      lastWasDialogue = false;
    } else if (isParenthetical(trimmedLine)) {
      elementType = "parenthetical";
      // Parentheticals can appear after character or during dialogue
    } else if (isCharacterName(trimmedLine, nextLine?.trim())) {
      elementType = "character";
      lastWasCharacter = true;
      lastWasDialogue = false;
    } else if (lastWasCharacter || lastWasDialogue) {
      // After a character name, everything until blank line is dialogue (or parenthetical)
      // Blank lines reset the context (handled above), so we just check for parenthetical
      if (isParenthetical(trimmedLine)) {
        elementType = "parenthetical";
      } else {
        elementType = "dialogue";
        lastWasDialogue = true;
        lastWasCharacter = false;
      }
    } else {
      // Default to action
      elementType = "action";
      lastWasCharacter = false;
      lastWasDialogue = false;
    }

    // For action blocks, collect lines that are part of the same wrapped paragraph
    // Use trailing space to detect wrapped lines (from PDF conversion)
    // Lines ending with space are continuations; lines ending without space are paragraph ends
    if (elementType === "action") {
      const actionLines: string[] = [trimmedLine];

      // Check if current line ends with trailing space (indicates wrapped/continued line)
      let currentEndsWithSpace = line.endsWith(" ");
      let j = i + 1;

      // Only continue collecting if current line is wrapped (ends with space)
      while (currentEndsWithSpace && j < lines.length) {
        const nextLine = lines[j];
        const nextTrimmed = nextLine.trim();

        // Stop at empty lines or other element types
        if (
          nextTrimmed === "" ||
          isSceneHeading(nextTrimmed) ||
          isTransition(nextTrimmed) ||
          isCharacterName(nextTrimmed, j + 1 < lines.length ? lines[j + 1] : undefined)
        ) {
          break;
        }

        actionLines.push(nextTrimmed);

        // Check if this line also ends with space (continues wrapping)
        currentEndsWithSpace = nextLine.endsWith(" ");
        j++;
      }

      // Join lines with spaces to form the paragraph
      const actionContent = actionLines.join(" ");

      elements.push({
        id: generateElementId(),
        type: "action",
        content: actionContent,
      });

      i = j;
      continue;
    }

    // For dialogue, collect lines that are part of the same wrapped paragraph
    // Use trailing space to detect wrapped lines (from PDF conversion)
    // Lines ending with space are continuations; lines ending without space are paragraph ends
    if (elementType === "dialogue") {
      const dialogueLines: string[] = [trimmedLine];

      // Check if current line ends with trailing space (indicates wrapped/continued line)
      let currentEndsWithSpace = line.endsWith(" ");
      let j = i + 1;

      // Only continue collecting if current line is wrapped (ends with space)
      while (currentEndsWithSpace && j < lines.length) {
        const nextLine = lines[j];
        const nextDialogueLine = nextLine.trim();

        // Stop at empty lines
        if (nextDialogueLine === "") {
          break;
        }

        // Stop at other element types
        if (
          isSceneHeading(nextDialogueLine) ||
          isTransition(nextDialogueLine) ||
          isParenthetical(nextDialogueLine) ||
          isCharacterName(nextDialogueLine, j + 1 < lines.length ? lines[j + 1] : undefined)
        ) {
          break;
        }

        dialogueLines.push(nextDialogueLine);

        // Check if this line also ends with space (continues wrapping)
        currentEndsWithSpace = nextLine.endsWith(" ");
        j++;
      }

      elements.push({
        id: generateElementId(),
        type: "dialogue",
        content: dialogueLines.join(" "),
      });

      i = j;
      // Reset dialogue context - we've collected the complete dialogue block
      lastWasDialogue = false;
      lastWasCharacter = false;
      continue;
    }

    // Single-line elements
    elements.push({
      id: generateElementId(),
      type: elementType,
      content: trimmedLine,
    });

    i++;
  }

  const _elementsToLog = elements.slice(0, 40);
  return elements;
}

/**
 * Convert structured elements back to plain text
 * Useful for export or backwards compatibility
 */
export function elementsToText(elements: ScreenplayElement[]): string {
  const lines: string[] = [];

  for (let i = 0; i < elements.length; i++) {
    const element = elements[i];
    const prevElement = i > 0 ? elements[i - 1] : null;

    // Add spacing before elements based on type
    if (prevElement) {
      if (element.type === "scene_heading") {
        lines.push("", ""); // Double blank line before scene headings
      } else if (element.type === "character") {
        lines.push(""); // Blank line before character
      } else if (element.type === "action" && prevElement.type !== "action") {
        lines.push(""); // Blank line before first action in a block
      } else if (element.type === "transition") {
        lines.push(""); // Blank line before transitions
      }
      // Note: Consecutive action elements don't get extra spacing
    }

    // Add the content with proper formatting
    switch (element.type) {
      case "scene_heading":
        lines.push(element.content.toUpperCase());
        break;
      case "character":
        lines.push(element.content.toUpperCase());
        break;
      case "transition":
        lines.push(element.content.toUpperCase());
        break;
      case "parenthetical":
        // Ensure parentheticals are wrapped in parens
        if (!element.content.startsWith("(")) {
          lines.push(`(${element.content})`);
        } else {
          lines.push(element.content);
        }
        break;
      default:
        lines.push(element.content);
    }
  }

  return lines.join("\n");
}
