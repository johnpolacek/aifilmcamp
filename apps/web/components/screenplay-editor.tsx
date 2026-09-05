"use client";

import { ArrowLeft, Loader2, Save, Upload } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { updateScreenplayText, uploadProjectFile } from "@/lib/actions/projects";

interface ScreenplayEditorProps {
  projectId: string;
  initialScreenplayText?: string;
  projectTitle?: string;
  username?: string;
}

export function ScreenplayEditor({
  projectId,
  initialScreenplayText = "",
  projectTitle,
  username,
}: ScreenplayEditorProps) {
  const _router = useRouter();
  const [screenplayText, setScreenplayText] = useState(initialScreenplayText);
  const [isSaving, setIsSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const autoSaveTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const lastSavedTextRef = useRef<string>(initialScreenplayText);

  // Auto-save with debounce
  const autoSave = useCallback(async () => {
    if (!hasChanges || screenplayText === lastSavedTextRef.current) return;

    setIsSaving(true);
    try {
      const result = await updateScreenplayText(projectId, screenplayText);
      if (result.success) {
        lastSavedTextRef.current = screenplayText;
        setHasChanges(false);
      }
    } catch (error) {
      console.error("Auto-save error:", JSON.stringify(error, null, 2));
      // Don't show error toast for auto-save failures
    } finally {
      setIsSaving(false);
    }
  }, [screenplayText, hasChanges, projectId]);

  // Manual save
  const handleSave = async () => {
    if (screenplayText === lastSavedTextRef.current) {
      toast.info("No changes to save");
      return;
    }

    setIsSaving(true);
    const loadingToast = toast.loading("Saving screenplay...");

    try {
      const result = await updateScreenplayText(projectId, screenplayText);

      if (!result.success) {
        throw new Error(result.error || "Failed to save screenplay");
      }

      lastSavedTextRef.current = screenplayText;
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

  // Handle text changes
  const handleTextChange = (value: string) => {
    setScreenplayText(value);
    setHasChanges(value !== lastSavedTextRef.current);

    // Clear existing timeout
    if (autoSaveTimeoutRef.current) {
      clearTimeout(autoSaveTimeoutRef.current);
    }

    // Debounce auto-save: wait 2 seconds after last change
    autoSaveTimeoutRef.current = setTimeout(() => {
      autoSave();
    }, 2000);
  };

  // Handle PDF upload
  const handlePdfUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Validate file type (PDF only)
    if (file.type !== "application/pdf" && !file.name.toLowerCase().endsWith(".pdf")) {
      toast.error("Please upload a PDF file");
      return;
    }

    // Validate file size (max 50MB)
    const maxSize = 50 * 1024 * 1024; // 50MB
    if (file.size > maxSize) {
      toast.error("File must be less than 50MB");
      return;
    }

    const loadingToast = toast.loading("Uploading and extracting text from PDF...");

    try {
      const uploadFormData = new FormData();
      uploadFormData.append("file", file);

      const uploadResult = await uploadProjectFile(uploadFormData, true);

      if (!uploadResult.success) {
        throw new Error(uploadResult.error || "Failed to upload screenplay");
      }

      if (uploadResult.extractedText) {
        setScreenplayText(uploadResult.extractedText);

        // Save the screenplay text and PDF file reference using the server action
        const saveResult = await updateScreenplayText(projectId, uploadResult.extractedText, {
          name: uploadResult.originalName,
          filename: uploadResult.filename,
          size: uploadResult.size,
          type: uploadResult.type,
        });

        if (saveResult.success) {
          lastSavedTextRef.current = uploadResult.extractedText;
          setHasChanges(false);
          toast.success("PDF uploaded and text extracted successfully!", {
            id: loadingToast,
          });
        } else {
          setHasChanges(true);
          toast.warning(
            "PDF uploaded and text extracted, but auto-save failed. Please save manually.",
            { id: loadingToast, duration: 5000 }
          );
        }
      } else {
        const errorMessage = uploadResult.extractionError
          ? `Text extraction failed: ${uploadResult.extractionError}`
          : "Text extraction failed. The PDF may be image-based or corrupted.";
        toast.warning(`PDF uploaded. ${errorMessage}`, {
          id: loadingToast,
          duration: 8000,
        });
      }
    } catch (error) {
      console.error("Error uploading PDF:", JSON.stringify(error, null, 2));
      const errorMessage = error instanceof Error ? error.message : "Failed to upload PDF";
      toast.error(errorMessage, { id: loadingToast });
    } finally {
      // Reset file input
      if (e.target) {
        e.target.value = "";
      }
    }
  };

  // Calculate statistics
  const wordCount = screenplayText.trim()
    ? screenplayText
        .trim()
        .split(/\s+/)
        .filter((word) => word.length > 0).length
    : 0;
  const pageCount = Math.ceil(wordCount / 250); // Rough estimate: 250 words per page
  const sceneCount = (screenplayText.match(/^(INT\.|EXT\.)/gm) || []).length;

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (autoSaveTimeoutRef.current) {
        clearTimeout(autoSaveTimeoutRef.current);
      }
    };
  }, []);

  return (
    <div className="min-h-screen bg-background">
      <div className="sticky top-0 z-10 border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="container mx-auto px-4 lg:px-8 pb-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link
                href={`/dashboard/projects/${projectId}/edit`}
                className="inline-flex items-center gap-2 text-muted-foreground hover:text-foreground transition-colors"
              >
                <ArrowLeft className="h-4 w-4" />
                <span className="text-sm font-medium">Back to Project</span>
              </Link>
              <div className="h-6 w-px bg-border" />
              <div>
                <h1 className="text-lg font-bold pl-6">
                  {projectTitle ? `Screenplay: ${projectTitle}` : "Screenplay Editor"}
                </h1>
              </div>
            </div>
            <div className="flex items-center gap-3">
              {/* Statistics */}
              <div className="hidden md:flex items-center gap-4 text-sm text-muted-foreground">
                <span>{wordCount.toLocaleString()} words</span>
                <span>~{pageCount} pages</span>
                {sceneCount > 0 && <span>{sceneCount} scenes</span>}
              </div>

              {/* PDF Upload */}
              <div className="relative">
                <input
                  type="file"
                  accept=".pdf,application/pdf"
                  onChange={handlePdfUpload}
                  className="hidden"
                  id="pdf-upload-input"
                />
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    document.getElementById("pdf-upload-input")?.click();
                  }}
                  className="bg-transparent"
                >
                  <Upload className="h-4 w-4 mr-2" />
                  Upload PDF
                </Button>
              </div>

              {/* Save Button */}
              <Button
                type="button"
                onClick={handleSave}
                disabled={isSaving || !hasChanges}
                size="sm"
              >
                {isSaving ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Saving...
                  </>
                ) : (
                  <>
                    <Save className="h-4 w-4 mr-2" />
                    Save
                  </>
                )}
              </Button>
            </div>
          </div>
        </div>
      </div>

      <div className="container mx-auto px-4 lg:px-8 py-6">
        <Card className="bg-card border-border">
          <CardContent className="p-0">
            <Textarea
              ref={textareaRef}
              value={screenplayText}
              onChange={(e) => handleTextChange(e.target.value)}
              placeholder={`INT. COFFEE SHOP - DAY

A cozy corner cafe. SARAH (30s) sits alone at a table, staring at her phone...

SARAH
(to herself)
Where is he?

...`}
              className="min-h-[calc(100vh-250px)] w-full resize-none border-0 bg-background font-mono text-sm leading-relaxed p-6 focus-visible:ring-0 focus-visible:ring-offset-0"
              style={{
                fontFamily:
                  "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace",
              }}
            />
          </CardContent>
        </Card>

        {/* Mobile Statistics */}
        <div className="md:hidden mt-4 flex items-center justify-center gap-4 text-sm text-muted-foreground">
          <span>{wordCount.toLocaleString()} words</span>
          <span>~{pageCount} pages</span>
          {sceneCount > 0 && <span>{sceneCount} scenes</span>}
        </div>

        {/* Help Text */}
        <div className="mt-4 p-4 bg-muted/30 rounded-lg border border-border">
          <p className="text-sm text-muted-foreground">
            <strong>Tip:</strong> Use standard screenplay format with INT./EXT. scene headings to
            enable automatic scene extraction. Changes are automatically saved as you type.
          </p>
        </div>
      </div>
    </div>
  );
}
