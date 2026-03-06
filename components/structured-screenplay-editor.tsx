"use client";

import { ArrowLeft, Download, FileText, Loader2, Plus, Save, Upload } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { ScreenplayElementComponent } from "@/components/screenplay-element";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { updateScreenplayElements, uploadProjectFile } from "@/lib/actions/projects";
import { elementsToText, parseScreenplayToElements } from "@/lib/screenplay-parser";
import type { ScreenplayElement, ScreenplayElementType } from "@/lib/types/screenplay";
import { createScreenplayElement, ELEMENT_TYPE_LABELS } from "@/lib/types/screenplay";

interface StructuredScreenplayEditorProps {
  projectId: string;
  initialElements?: ScreenplayElement[];
  initialScreenplayText?: string; // For migration from plain text
  projectTitle?: string;
}

export function StructuredScreenplayEditor({
  projectId,
  initialElements,
  initialScreenplayText,
  projectTitle,
}: StructuredScreenplayEditorProps) {
  const _router = useRouter();
  const searchParams = useSearchParams();
  const returnStep = searchParams.get("returnStep");
  const backHref = returnStep
    ? `/dashboard/projects/${projectId}/edit?step=${returnStep}`
    : `/dashboard/projects/${projectId}/edit`;

  // Parse initial text to elements if no elements provided
  const getInitialElements = useCallback((): ScreenplayElement[] => {
    if (initialElements && initialElements.length > 0) {
      return initialElements;
    }
    if (initialScreenplayText) {
      return parseScreenplayToElements(initialScreenplayText);
    }
    // Default: start with one scene heading
    return [createScreenplayElement("scene_heading", "")];
  }, [initialElements, initialScreenplayText]);

  const [elements, setElements] = useState<ScreenplayElement[]>(getInitialElements);
  const [focusedIndex, setFocusedIndex] = useState(0);
  const [isSaving, setIsSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const elementRefs = useRef<Map<string, HTMLTextAreaElement>>(new Map());
  const autoSaveTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const lastSavedRef = useRef<string>(JSON.stringify(getInitialElements()));
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Auto-save with debounce
  const autoSave = useCallback(async () => {
    const currentState = JSON.stringify(elements);
    if (!hasChanges || currentState === lastSavedRef.current) return;

    setIsSaving(true);
    try {
      const result = await updateScreenplayElements(projectId, elements);
      if (result.success) {
        lastSavedRef.current = currentState;
        setHasChanges(false);
      }
    } catch (error) {
      console.error("Auto-save error:", JSON.stringify(error, null, 2));
    } finally {
      setIsSaving(false);
    }
  }, [elements, hasChanges, projectId]);

  // Manual save
  const handleSave = async () => {
    const currentState = JSON.stringify(elements);
    if (currentState === lastSavedRef.current) {
      toast.info("No changes to save");
      return;
    }

    setIsSaving(true);
    const loadingToast = toast.loading("Saving screenplay...");

    try {
      const result = await updateScreenplayElements(projectId, elements);

      if (!result.success) {
        throw new Error(result.error || "Failed to save screenplay");
      }

      lastSavedRef.current = currentState;
      setHasChanges(false);

      toast.success("Screenplay saved successfully!", { id: loadingToast });
    } catch (error) {
      console.error("Error saving screenplay:", JSON.stringify(error, null, 2));
      const errorMessage = error instanceof Error ? error.message : "Failed to save screenplay";
      toast.error(errorMessage, { id: loadingToast });
    } finally {
      setIsSaving(false);
    }
  };

  // Handle element content change
  const handleChange = useCallback(
    (id: string, content: string) => {
      setElements((prev) => {
        const updated = prev.map((el) => (el.id === id ? { ...el, content } : el));
        return updated;
      });
      setHasChanges(true);

      // Clear existing timeout and set new one
      if (autoSaveTimeoutRef.current) {
        clearTimeout(autoSaveTimeoutRef.current);
      }
      autoSaveTimeoutRef.current = setTimeout(() => {
        autoSave();
      }, 2000);
    },
    [autoSave]
  );

  // Handle element type change
  const handleTypeChange = useCallback((id: string, type: ScreenplayElementType) => {
    setElements((prev) => prev.map((el) => (el.id === id ? { ...el, type } : el)));
    setHasChanges(true);
  }, []);

  // Delete element
  const handleDelete = useCallback((id: string) => {
    setElements((prev) => {
      const index = prev.findIndex((el) => el.id === id);
      const filtered = prev.filter((el) => el.id !== id);

      // Ensure at least one element remains
      if (filtered.length === 0) {
        return [createScreenplayElement("scene_heading", "")];
      }

      // Update focus
      if (index > 0) {
        setFocusedIndex(index - 1);
      } else {
        setFocusedIndex(0);
      }

      return filtered;
    });
    setHasChanges(true);
  }, []);

  // Insert new element after index
  const handleInsertAfter = useCallback((index: number, type: ScreenplayElementType) => {
    const newElement = createScreenplayElement(type, "");
    setElements((prev) => {
      const updated = [...prev];
      updated.splice(index + 1, 0, newElement);
      return updated;
    });
    setFocusedIndex(index + 1);
    setHasChanges(true);
  }, []);

  // Determine next element type based on current type
  const getNextType = (currentType: ScreenplayElementType): ScreenplayElementType => {
    switch (currentType) {
      case "scene_heading":
        return "action";
      case "action":
        return "action";
      case "character":
        return "dialogue";
      case "parenthetical":
        return "dialogue";
      case "dialogue":
        return "character";
      case "transition":
        return "scene_heading";
      default:
        return "action";
    }
  };

  // Handle keyboard navigation
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent, index: number) => {
      const currentElement = elements[index];
      const target = e.target as HTMLTextAreaElement;
      const cursorAtStart = target.selectionStart === 0 && target.selectionEnd === 0;
      const cursorAtEnd = target.selectionStart === currentElement.content.length;

      // Enter: Create new element after current
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        const nextType = getNextType(currentElement.type);
        handleInsertAfter(index, nextType);
        return;
      }

      // Backspace on empty element: Delete and focus previous
      if (e.key === "Backspace" && currentElement.content === "" && elements.length > 1) {
        e.preventDefault();
        handleDelete(currentElement.id);
        return;
      }

      // Tab on empty element: Change element type cyclically
      if (e.key === "Tab" && !e.shiftKey && currentElement.content === "") {
        e.preventDefault();
        const types: ScreenplayElementType[] = [
          "scene_heading",
          "action",
          "character",
          "dialogue",
          "parenthetical",
          "transition",
        ];
        const currentIndex = types.indexOf(currentElement.type);
        const nextIndex = (currentIndex + 1) % types.length;
        handleTypeChange(currentElement.id, types[nextIndex]);
        return;
      }

      // Tab with content: Move to next element
      if (e.key === "Tab" && !e.shiftKey && currentElement.content !== "") {
        if (index < elements.length - 1) {
          e.preventDefault();
          setFocusedIndex(index + 1);
        }
        return;
      }

      // Shift+Tab: Move to previous element
      if (e.key === "Tab" && e.shiftKey) {
        if (index > 0) {
          e.preventDefault();
          setFocusedIndex(index - 1);
        }
        return;
      }

      // Arrow Down at end of content: Move to next element
      if (e.key === "ArrowDown" && cursorAtEnd) {
        if (index < elements.length - 1) {
          e.preventDefault();
          setFocusedIndex(index + 1);
        }
        return;
      }

      // Arrow Up at start of content: Move to previous element
      if (e.key === "ArrowUp" && cursorAtStart) {
        if (index > 0) {
          e.preventDefault();
          setFocusedIndex(index - 1);
        }
        return;
      }
    },
    [elements, handleDelete, handleInsertAfter, handleTypeChange, getNextType]
  );

  // Handle PDF upload
  const handlePdfUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (file.type !== "application/pdf" && !file.name.toLowerCase().endsWith(".pdf")) {
      toast.error("Please upload a PDF file");
      return;
    }

    const maxSize = 50 * 1024 * 1024;
    if (file.size > maxSize) {
      toast.error("File must be less than 50MB");
      return;
    }

    const loadingToast = toast.loading("Uploading and parsing screenplay...");

    try {
      const uploadFormData = new FormData();
      uploadFormData.append("file", file);

      const uploadResult = await uploadProjectFile(uploadFormData, true);

      if (!uploadResult.success) {
        throw new Error(uploadResult.error || "Failed to upload screenplay");
      }

      if (uploadResult.extractedText) {
        // Parse the extracted text into elements
        const parsedElements = parseScreenplayToElements(uploadResult.extractedText);

        if (parsedElements.length > 0) {
          setElements(parsedElements);
          setHasChanges(true);
          setFocusedIndex(0);

          // Auto-save the parsed elements
          const saveResult = await updateScreenplayElements(projectId, parsedElements);

          if (saveResult.success) {
            lastSavedRef.current = JSON.stringify(parsedElements);
            setHasChanges(false);
            toast.success(`Screenplay imported: ${parsedElements.length} elements parsed!`, {
              id: loadingToast,
            });
          } else {
            toast.warning("Screenplay imported but auto-save failed. Please save manually.", {
              id: loadingToast,
            });
          }
        } else {
          toast.warning(
            "No screenplay elements found in PDF. The text may not follow standard format.",
            {
              id: loadingToast,
              duration: 5000,
            }
          );
        }
      } else {
        const errorMessage = uploadResult.extractionError
          ? `Text extraction failed: ${uploadResult.extractionError}`
          : "Text extraction failed. The PDF may be image-based.";
        toast.error(errorMessage, { id: loadingToast, duration: 8000 });
      }
    } catch (error) {
      console.error("Error uploading PDF:", JSON.stringify(error, null, 2));
      const errorMessage = error instanceof Error ? error.message : "Failed to upload PDF";
      toast.error(errorMessage, { id: loadingToast });
    } finally {
      if (e.target) {
        e.target.value = "";
      }
    }
  };

  // Export as plain text
  const handleExportText = () => {
    const text = elementsToText(elements);
    const blob = new Blob([text], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${projectTitle || "screenplay"}.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    toast.success("Screenplay exported as text file");
  };

  // Add new element at the end
  const handleAddElement = (type: ScreenplayElementType) => {
    const newElement = createScreenplayElement(type, "");
    setElements((prev) => [...prev, newElement]);
    setFocusedIndex(elements.length);
    setHasChanges(true);
  };

  // Calculate statistics
  const wordCount = elements.reduce((count, el) => {
    return (
      count +
      el.content
        .trim()
        .split(/\s+/)
        .filter((w) => w.length > 0).length
    );
  }, 0);
  const sceneCount = elements.filter((el) => el.type === "scene_heading").length;
  const dialogueCount = elements.filter((el) => el.type === "dialogue").length;

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (autoSaveTimeoutRef.current) {
        clearTimeout(autoSaveTimeoutRef.current);
      }
    };
  }, []);

  // Register element ref
  const registerRef = useCallback((id: string, ref: HTMLTextAreaElement | null) => {
    if (ref) {
      elementRefs.current.set(id, ref);
    } else {
      elementRefs.current.delete(id);
    }
  }, []);

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <div className="fixed top-0 left-0 right-0 z-50 bg-background/95 backdrop-blur border-b border-border">
        <div className="container mx-auto px-4 py-3 flex items-center justify-between">
          <div className="flex items-center gap-4">
            <Link
              href={backHref}
              className="flex items-center gap-2 text-muted-foreground hover:text-foreground transition-colors"
            >
              <ArrowLeft className="h-4 w-4" />
              <span className="hidden sm:inline">Back to Project</span>
            </Link>
            <div className="h-4 w-px bg-border" />
            <div className="flex items-center gap-2">
              <FileText className="h-5 w-5 text-primary" />
              <h1 className="font-semibold truncate max-w-[200px] sm:max-w-none">
                {projectTitle || "Screenplay"}
              </h1>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {/* Stats */}
            <div className="hidden md:flex items-center gap-4 text-sm text-muted-foreground mr-4">
              <span>{sceneCount} scenes</span>
              <span>{dialogueCount} dialogue</span>
              <span>{wordCount} words</span>
            </div>

            {/* Actions */}
            <Button
              variant="outline"
              size="sm"
              onClick={() => fileInputRef.current?.click()}
              className="hidden sm:flex"
            >
              <Upload className="h-4 w-4 mr-2" />
              Import PDF
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={handleExportText}
              className="hidden sm:flex"
            >
              <Download className="h-4 w-4 mr-2" />
              Export
            </Button>
            <Button onClick={handleSave} disabled={isSaving || !hasChanges} size="sm">
              {isSaving ? (
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              ) : (
                <Save className="h-4 w-4 mr-2" />
              )}
              {isSaving ? "Saving..." : "Save"}
            </Button>
          </div>
        </div>
      </div>

      {/* Hidden file input */}
      <input
        ref={fileInputRef}
        type="file"
        onChange={handlePdfUpload}
        className="hidden"
        accept=".pdf,application/pdf"
      />

      {/* Main editor area */}
      <div className="pt-20 pb-32">
        <div className="container mx-auto px-4 max-w-5xl">
          <Card className="bg-card/50">
            <CardHeader className="pb-2">
              <CardTitle className="text-lg flex items-center justify-between">
                <span>Screenplay Editor</span>
                <span className="text-xs font-normal text-muted-foreground">
                  Press Enter for new element • Tab to change type • ⌘/ for type menu
                </span>
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {/* Elements */}
              <div className="py-4 font-mono text-sm leading-relaxed">
                {elements.map((element, index) => {
                  // Calculate scene number by counting scene headings up to this index
                  const sceneNumber = elements
                    .slice(0, index + 1)
                    .filter((el) => el.type === "scene_heading").length;

                  // Add extra spacing when action follows dialogue
                  const prevElement = index > 0 ? elements[index - 1] : null;
                  const needsExtraSpacing =
                    element.type === "action" && prevElement?.type === "dialogue";

                  return (
                    <ScreenplayElementComponent
                      key={element.id}
                      element={element}
                      index={index}
                      isFocused={focusedIndex === index}
                      onFocus={setFocusedIndex}
                      onChange={handleChange}
                      onTypeChange={handleTypeChange}
                      onKeyDown={handleKeyDown}
                      onDelete={handleDelete}
                      onInsertAfter={handleInsertAfter}
                      sceneNumber={sceneNumber > 0 ? sceneNumber : undefined}
                      extraTopSpacing={needsExtraSpacing}
                      ref={(ref) => registerRef(element.id, ref)}
                    />
                  );
                })}
              </div>

              {/* Add element buttons */}
              <div className="border-t border-border p-4 flex flex-wrap gap-2">
                <span className="text-xs text-muted-foreground self-center mr-2">Add:</span>
                {(
                  [
                    "scene_heading",
                    "action",
                    "character",
                    "dialogue",
                    "parenthetical",
                    "transition",
                  ] as ScreenplayElementType[]
                ).map((type) => (
                  <Button
                    key={type}
                    variant="outline"
                    size="sm"
                    onClick={() => handleAddElement(type)}
                    className="text-xs"
                  >
                    <Plus className="h-3 w-3 mr-1" />
                    {ELEMENT_TYPE_LABELS[type]}
                  </Button>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Floating save indicator */}
      {hasChanges && (
        <div className="fixed bottom-4 right-4 bg-yellow-500/20 text-yellow-500 px-3 py-1.5 rounded-full text-sm font-medium">
          Unsaved changes
        </div>
      )}
    </div>
  );
}
