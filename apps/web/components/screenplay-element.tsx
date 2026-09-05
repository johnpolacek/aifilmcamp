"use client";

import { forwardRef, useCallback, useEffect, useRef, useState } from "react";
import type {
  ScreenplayElementType as ElementType,
  ScreenplayElement as ScreenplayElementType,
} from "@/lib/types/screenplay";
import { ELEMENT_TYPE_LABELS } from "@/lib/types/screenplay";
import { cn } from "@/lib/utils";

interface ScreenplayElementProps {
  element: ScreenplayElementType;
  index: number;
  isFocused: boolean;
  onFocus: (index: number) => void;
  onChange: (id: string, content: string) => void;
  onTypeChange: (id: string, type: ElementType) => void;
  onKeyDown: (e: React.KeyboardEvent, index: number) => void;
  onDelete: (id: string) => void;
  onInsertAfter: (index: number, type: ElementType) => void;
  sceneNumber?: number;
  extraTopSpacing?: boolean;
}

/**
 * Get CSS classes for element type styling
 * Standard screenplay format:
 * - Dialogue is ~35 characters wide (~3.5 inches), left-aligned text, block centered
 * - Character names are centered, uppercase
 * - Parentheticals are centered, narrower than dialogue
 */
function getElementStyles(type: ElementType): string {
  switch (type) {
    case "scene_heading":
      return "font-bold uppercase tracking-wide text-primary pt-4";
    case "action":
      return "font-normal";
    case "character":
      return "uppercase font-semibold mt-4";
    case "parenthetical":
      return "italic text-muted-foreground text-sm";
    case "dialogue":
      return ""; // Styling handled by wrapper
    case "transition":
      return "uppercase text-right font-semibold text-muted-foreground";
    default:
      return "";
  }
}

/**
 * Get wrapper classes for element type (for centering blocks)
 */
function getWrapperStyles(type: ElementType): string {
  switch (type) {
    case "character":
      return "flex justify-center";
    case "parenthetical":
      return "flex justify-center";
    case "dialogue":
      return "flex justify-center";
    default:
      return "";
  }
}

/**
 * Get placeholder text for element type
 */
function getPlaceholder(type: ElementType): string {
  switch (type) {
    case "scene_heading":
      return "INT. LOCATION - DAY";
    case "action":
      return "Action description...";
    case "character":
      return "CHARACTER NAME";
    case "parenthetical":
      return "(direction)";
    case "dialogue":
      return "Dialogue...";
    case "transition":
      return "CUT TO:";
    default:
      return "";
  }
}

/**
 * Individual screenplay element component
 * Renders as an editable input with type-specific styling
 */
export const ScreenplayElementComponent = forwardRef<HTMLTextAreaElement, ScreenplayElementProps>(
  function ScreenplayElementComponent(
    {
      element,
      index,
      isFocused,
      onFocus,
      onChange,
      onTypeChange,
      onKeyDown,
      // These are passed but handled by parent - prefixed to suppress unused warnings
      onDelete: _onDelete,
      onInsertAfter: _onInsertAfter,
      sceneNumber,
      extraTopSpacing = false,
    },
    ref
  ) {
    const [showTypeMenu, setShowTypeMenu] = useState(false);
    const internalRef = useRef<HTMLTextAreaElement>(null);

    // Merge the forwarded ref with our internal ref
    const setRefs = useCallback(
      (node: HTMLTextAreaElement | null) => {
        // Set internal ref
        (internalRef as React.MutableRefObject<HTMLTextAreaElement | null>).current = node;
        // Forward to parent ref if provided
        if (typeof ref === "function") {
          ref(node);
        } else if (ref) {
          (ref as React.MutableRefObject<HTMLTextAreaElement | null>).current = node;
        }
      },
      [ref]
    );

    // Auto-resize textarea based on content
    const adjustHeight = useCallback(() => {
      const textarea = internalRef.current;
      if (textarea) {
        // Reset height to auto first to get accurate scrollHeight
        textarea.style.height = "auto";
        // Use requestAnimationFrame to ensure layout is calculated with width constraints
        requestAnimationFrame(() => {
          if (internalRef.current) {
            internalRef.current.style.height = `${internalRef.current.scrollHeight}px`;
          }
        });
      }
    }, []);

    // Re-calculate height on mount and when content changes (for multi-line wrapping)
    const contentLength = element.content?.length ?? 0;
    useEffect(() => {
      // contentLength triggers recalculation when content changes
      if (contentLength >= 0) {
        adjustHeight();
      }
    }, [adjustHeight, contentLength]);

    // Also recalculate on window resize (viewport changes affect text wrapping)
    useEffect(() => {
      const handleResize = () => adjustHeight();
      window.addEventListener("resize", handleResize);
      return () => window.removeEventListener("resize", handleResize);
    }, [adjustHeight]);

    // Focus the textarea when this element becomes focused
    useEffect(() => {
      if (isFocused && internalRef.current) {
        internalRef.current.focus();
      }
    }, [isFocused]);

    const handleChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      onChange(element.id, e.target.value);
      adjustHeight();
    };

    const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      // Escape closes type menu
      if (e.key === "Escape" && showTypeMenu) {
        setShowTypeMenu(false);
        e.preventDefault();
        return;
      }

      // Cmd/Ctrl + / opens type menu
      if ((e.metaKey || e.ctrlKey) && e.key === "/") {
        e.preventDefault();
        setShowTypeMenu(!showTypeMenu);
        return;
      }

      // Pass other key events to parent
      onKeyDown(e, index);
    };

    const handleTypeSelect = (type: ElementType) => {
      onTypeChange(element.id, type);
      setShowTypeMenu(false);
      internalRef.current?.focus();
    };

    const elementTypes: ElementType[] = [
      "scene_heading",
      "action",
      "character",
      "parenthetical",
      "dialogue",
      "transition",
    ];

    // Get max-width for centered elements
    const getMaxWidth = () => {
      if (element.type === "dialogue") return "w-full max-w-[35ch]";
      if (element.type === "parenthetical") return "w-full max-w-[35ch]";
      if (element.type === "character") return "w-full max-w-[35ch]";
      return "w-full";
    };

    return (
      <div
        className={cn(
          "group flex transition-all cursor-text",
          isFocused && "bg-white/10 border-r-2 border-primary/70",
          !isFocused && "border-r-2 border-transparent"
        )}
      >
        {/* Left column: Type label with right border */}
        <div className="relative shrink-0 w-24 border-r border-border pl-4 text-right">
          <button
            type="button"
            className={cn(
              "w-full h-full py-1 pr-3 text-xs uppercase tracking-wider text-right transition-opacity cursor-pointer select-none text-muted-foreground bg-transparent border-none",
              isFocused ? "opacity-100" : "opacity-0 group-hover:opacity-60"
            )}
            onClick={(e) => {
              e.stopPropagation();
              setShowTypeMenu(!showTypeMenu);
            }}
            tabIndex={-1}
          >
            {ELEMENT_TYPE_LABELS[element.type]}
          </button>

          {/* Type menu */}
          {showTypeMenu && (
            <div className="absolute left-0 top-full mt-1 z-50 bg-background border border-border rounded-lg shadow-lg py-1 min-w-[150px]">
              {elementTypes.map((type) => (
                <button
                  key={type}
                  type="button"
                  className={cn(
                    "w-full px-3 py-1.5 text-left text-sm hover:bg-muted transition-colors",
                    element.type === type && "bg-muted text-primary"
                  )}
                  onClick={(e) => {
                    e.stopPropagation();
                    handleTypeSelect(type);
                  }}
                >
                  {ELEMENT_TYPE_LABELS[type]}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Right column: Content area */}
        <div
          className={cn(
            "flex-1 pb-0.5 pl-4 pr-4 relative",
            getWrapperStyles(element.type),
            extraTopSpacing ? "pt-4" : "pt-0.5"
          )}
        >
          <textarea
            ref={setRefs}
            value={element.content}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            onFocus={() => onFocus(index)}
            placeholder={getPlaceholder(element.type)}
            className={cn(
              "bg-transparent border-none outline-none resize-none overflow-hidden leading-relaxed",
              "placeholder:text-muted-foreground/40",
              "focus:ring-0 focus:outline-none",
              getMaxWidth(),
              getElementStyles(element.type),
              // Dialogue: left-aligned text within centered block
              element.type === "dialogue" && "text-left",
              // Character: centered text
              element.type === "character" && "text-center",
              // Parenthetical: centered text
              element.type === "parenthetical" && "text-center"
            )}
            rows={1}
            spellCheck={true}
          />
          {/* Scene number - only visible on xl screens */}
          {element.type === "scene_heading" && sceneNumber !== undefined && (
            <span className="hidden lg:block absolute -left-24 top-1/2 text-left -translate-y-1/2 text-xs text-muted-foreground font-mono -translate-x-full xl:pr-4">
              SCENE {sceneNumber}
            </span>
          )}
        </div>
      </div>
    );
  }
);
