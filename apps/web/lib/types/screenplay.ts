/**
 * Screenplay element types following standard screenplay formatting
 */
export type ScreenplayElementType =
  | "scene_heading" // INT. COFFEE SHOP - DAY
  | "action" // Description/action lines
  | "character" // CHARACTER NAME (centered, caps)
  | "parenthetical" // (quietly)
  | "dialogue" // The spoken words
  | "transition"; // CUT TO:, FADE OUT., etc.

/**
 * A single element in a screenplay
 */
export interface ScreenplayElement {
  id: string;
  type: ScreenplayElementType;
  content: string;
}

/**
 * The full screenplay stored as an array of elements
 */
export type Screenplay = ScreenplayElement[];

/**
 * Helper to generate unique IDs for screenplay elements
 */
export function generateElementId(): string {
  return `el_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}

/**
 * Create a new screenplay element with defaults
 */
export function createScreenplayElement(
  type: ScreenplayElementType = "action",
  content: string = ""
): ScreenplayElement {
  return {
    id: generateElementId(),
    type,
    content,
  };
}

/**
 * Display names for element types
 */
export const ELEMENT_TYPE_LABELS: Record<ScreenplayElementType, string> = {
  scene_heading: "Heading",
  action: "Action",
  character: "Character",
  parenthetical: "Parenthetical",
  dialogue: "Dialogue",
  transition: "Transition",
};

/**
 * Keyboard shortcuts for quickly changing element types
 */
export const ELEMENT_TYPE_SHORTCUTS: Record<string, ScreenplayElementType> = {
  s: "scene_heading",
  a: "action",
  c: "character",
  p: "parenthetical",
  d: "dialogue",
  t: "transition",
};
