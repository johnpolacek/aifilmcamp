"use client";

import {
  Camera,
  ChevronsDown,
  Clapperboard,
  Cloud,
  CloudOff,
  Edit,
  File,
  Film,
  LinkIcon,
  Loader2,
  Pencil,
  Plus,
  Trash,
  Upload,
  User,
  Wrench,
  X,
} from "lucide-react";
import { useRouter } from "next/navigation";
import type React from "react";
import { Suspense, useCallback, useEffect, useId, useRef, useState } from "react";
import { toast } from "sonner";
import { ExtractConfirmDialog } from "@/components/extract-confirm-dialog";
import { ProjectDevelopmentPhases } from "@/components/project-development-phases";
import { SceneList } from "@/components/scene-editor";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { ImagePreview } from "@/components/ui/image-preview";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { OptimizedImage } from "@/components/ui/optimized-image";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { getImageUrl } from "@/lib/image-utils";
import type { Scene } from "@/lib/scenes-client";
import { derivePhaseStatus, ensureProjectPhaseVisibility } from "@/lib/development";
import { extractAllCharacters, extractAllLocations } from "@/lib/screenplay-parser";
import type {
  FilmLengthOption,
  PhaseStatusMap,
  PhaseVisibilityMap,
  ProjectDevelopmentData,
} from "@/lib/types/development";
import {
  createDefaultPhaseStatus,
  createDefaultPhaseVisibility,
  FILM_LENGTH_OPTIONS,
} from "@/lib/types/development";

// Types
export interface ProjectLinks {
  links: Array<{ label: string; url: string }>;
}

export type ToolCategory = "image" | "video" | "sound" | "other";

export interface CategorizedTool {
  name: string;
  category: ToolCategory;
}

export interface Character {
  name: string;
  appearance: string;
  role?: string;
  motivation?: string;
  arc?: string;
  visualPrompt?: string;
  mainImage?: string; // Main character image filename
  images?: string[]; // Additional images for different angles/attire
}

export interface Location {
  name: string;
  description: string;
  storyPurpose?: string;
  visualPrompt?: string;
  image?: string; // Main location image filename
  images?: string[]; // Additional images for different angles/variations
}

export interface ProjectFile {
  name: string; // Display name (e.g., "Screenplay.pdf")
  filename: string; // S3 filename (e.g., "1761873619145-screenplay.pdf")
  size?: number; // File size in bytes
  type?: string; // MIME type (e.g., "application/pdf")
}

import type { ScreenplayElement } from "@/lib/types/screenplay";
import { cn } from "@/lib/utils";

export interface ProjectFormData {
  title: string;
  logline: string; // One-line description of the film
  duration: string;
  filmLength?: FilmLengthOption;
  genre: string;
  characters?: Character[];
  setting?: {
    locations?: Location[];
  };
  development?: ProjectDevelopmentData;
  phaseVisibility?: PhaseVisibilityMap;
  phaseStatus?: PhaseStatusMap;
  scenes?: Scene[]; // Film scenes with generated content
  screenplayText?: string; // Full screenplay text content (legacy/export)
  screenplayElements?: ScreenplayElement[]; // Structured screenplay elements (JSON format)
  thumbnail?: string;
  filmLink?: string; // YouTube or Vimeo link
  links: ProjectLinks;
  tools: CategorizedTool[];
  screenplay?: ProjectFile;
  username?: string;
  slug?: string;
  publishedAt?: string; // When the film was published
  isPublished?: boolean; // Whether the film is published/shared publicly
}

// Common tools by category
const COMMON_TOOLS = {
  image: [
    "Midjourney",
    "DALL-E",
    "Stable Diffusion",
    "Leonardo AI",
    "Ideogram",
    "Flux",
    "Adobe Firefly",
    "Nano Banana Pro",
    "Other",
  ],
  video: [
    "Runway Gen-3",
    "Google Veo",
    "Pika Labs",
    "Kling AI",
    "Midjourney",
    "Luma Dream Machine",
    "HaiperAI",
    "Sora",
    "Other",
  ],
  sound: ["ElevenLabs", "Suno", "Udio", "Mubert", "AIVA", "Soundraw", "Other"],
  other: [
    "Adobe After Effects",
    "Adobe Premiere Pro",
    "Adobe Photoshop",
    "Adobe Illustrator",
    "DaVinci Resolve",
    "Final Cut Pro",
    "Avid Media Composer",
    "Blender",
    "Cinema 4D",
    "Maya",
    "Adobe Audition",
    "Pro Tools",
    "Logic Pro",
    "Ableton Live",
    "Other",
  ],
} as const;

// Helper function to infer label from URL
function inferLabelFromUrl(url: string): string {
  const urlLower = url.toLowerCase();

  if (urlLower.includes("youtube.com") || urlLower.includes("youtu.be")) return "YouTube";
  if (urlLower.includes("vimeo.com")) return "Vimeo";
  if (urlLower.includes("x.com") || urlLower.includes("twitter.com")) return "X (Twitter)";
  if (urlLower.includes("instagram.com")) return "Instagram";
  if (urlLower.includes("tiktok.com")) return "TikTok";
  if (urlLower.includes("facebook.com")) return "Facebook";
  if (urlLower.includes("linkedin.com")) return "LinkedIn";

  // For other URLs, try to extract domain name
  try {
    const domain = new URL(url).hostname.replace("www.", "");
    return domain.charAt(0).toUpperCase() + domain.slice(1);
  } catch {
    return "Website";
  }
}

interface ProjectFormProps {
  initialData?: Partial<ProjectFormData>;
  projectId?: string;
  isEditing?: boolean;
  redirectPath?: string;
  useGridLayout?: boolean;
}

function createInitialProjectFormData(initialData?: Partial<ProjectFormData>): ProjectFormData {
  return {
    title: initialData?.title || "",
    logline: initialData?.logline || "",
    duration: initialData?.duration || "",
    filmLength: initialData?.filmLength || (initialData?.duration as FilmLengthOption | undefined),
    genre: initialData?.genre || "",
    characters: initialData?.characters || [],
    setting: initialData?.setting || { locations: [] },
    development: initialData?.development || {},
    phaseVisibility: {
      ...createDefaultPhaseVisibility(),
      ...initialData?.phaseVisibility,
    },
    phaseStatus: {
      ...createDefaultPhaseStatus(),
      ...initialData?.phaseStatus,
    },
    scenes: initialData?.scenes || [],
    screenplayText: initialData?.screenplayText || "",
    thumbnail: initialData?.thumbnail,
    filmLink: initialData?.filmLink || "",
    links: initialData?.links || { links: [] },
    tools: initialData?.tools || [],
    screenplay: initialData?.screenplay,
    username: initialData?.username,
    slug: initialData?.slug,
    publishedAt: initialData?.publishedAt,
    isPublished: initialData?.isPublished,
  };
}

function createEmptyProjectFormData(): ProjectFormData {
  return createInitialProjectFormData();
}

export default function ProjectForm({
  initialData,
  projectId,
  isEditing = false,
  redirectPath = "/dashboard",
  useGridLayout = false,
}: ProjectFormProps) {
  const router = useRouter();
  const genreSelectId = useId();
  const durationSelectId = useId();
  const toolSelectIds = {
    video: useId(),
    image: useId(),
    sound: useId(),
    other: useId(),
  };
  const [draftProjectId, setDraftProjectId] = useState(() => projectId || `project-draft-${Date.now()}`);
  const effectiveProjectId = projectId || draftProjectId;

  const [formData, setFormData] = useState<ProjectFormData>(() => createInitialProjectFormData(initialData));
  const [wizardResetKey, setWizardResetKey] = useState(0);

  const [newLinkUrl, setNewLinkUrl] = useState("");
  const [selectedTool, setSelectedTool] = useState<Record<ToolCategory, string>>({
    video: "",
    image: "",
    sound: "",
    other: "",
  });
  const [customToolInput, setCustomToolInput] = useState<Record<ToolCategory, string>>({
    video: "",
    image: "",
    sound: "",
    other: "",
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isUploadingImage, setIsUploadingImage] = useState(false);
  const [previewImage, setPreviewImage] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const characterFileInputRefs = useRef<Record<number, HTMLInputElement | null>>({});
  const characterAdditionalFileInputRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const characterAddImageInputRefs = useRef<Record<number, HTMLInputElement | null>>({});
  const [uploadingCharacterIndex, setUploadingCharacterIndex] = useState<number | null>(null);
  const [uploadingCharacterAdditionalIndex, setUploadingCharacterAdditionalIndex] = useState<{
    characterIndex: number;
    imageIndex: number;
  } | null>(null);
  const [characterPreviewImages, setCharacterPreviewImages] = useState<Record<number, string>>({});
  const [characterAdditionalPreviewImages, setCharacterAdditionalPreviewImages] = useState<
    Record<number, Record<number, string>>
  >({});
  const [hasVideoTool, setHasVideoTool] = useState(() => {
    const tools = initialData?.tools || [];
    return tools.some((tool) => tool.category === "video");
  });
  const projectFileInputRef = useRef<HTMLInputElement>(null);
  const [isUploadingFile, setIsUploadingFile] = useState(false);
  const [editingCharacterIndex, setEditingCharacterIndex] = useState<number | null>(null);
  const [confirmingCharacterDelete, setConfirmingCharacterDelete] = useState<number | null>(null);
  const [showAllCharacters, setShowAllCharacters] = useState(false);
  const [showExtractCharactersDialog, setShowExtractCharactersDialog] = useState(false);
  const [isExtractingCharacters, setIsExtractingCharacters] = useState(false);
  const [editingLocationIndex, setEditingLocationIndex] = useState<number | null>(null);
  const [confirmingLocationDelete, setConfirmingLocationDelete] = useState<number | null>(null);
  const [showAllLocations, setShowAllLocations] = useState(false);
  const [showExtractLocationsDialog, setShowExtractLocationsDialog] = useState(false);
  const [isExtractingLocations, setIsExtractingLocations] = useState(false);
  const [isEditingProjectInfo, setIsEditingProjectInfo] = useState(!isEditing); // Start expanded for new projects

  // Section refs for scrolling
  const charactersSectionRef = useRef<HTMLDivElement>(null);
  const locationsSectionRef = useRef<HTMLDivElement>(null);

  // Location management state
  const locationFileInputRefs = useRef<Record<number, HTMLInputElement | null>>({});
  const locationAddImageInputRefs = useRef<Record<number, HTMLInputElement | null>>({});
  const locationAdditionalFileInputRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const [uploadingLocationIndex, setUploadingLocationIndex] = useState<number | null>(null);
  const [uploadingLocationAdditionalIndex, setUploadingLocationAdditionalIndex] = useState<{
    locationIndex: number;
    imageIndex: number;
  } | null>(null);
  const [locationPreviewImages, setLocationPreviewImages] = useState<Record<number, string>>({});
  const [locationAdditionalPreviewImages, setLocationAdditionalPreviewImages] = useState<
    Record<number, Record<number, string>>
  >({});
  const [showRemoveScreenplayConfirm, setShowRemoveScreenplayConfirm] = useState(false);

  // Auto-save state
  const [autoSaveStatus, setAutoSaveStatus] = useState<"idle" | "saving" | "saved" | "error">(
    "idle"
  );
  const isInitialMount = useRef(true);
  const autoSaveTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const lastSavedDataRef = useRef<string>(JSON.stringify(formData));

  const buildPersistedFormData = useCallback(
    (currentData: ProjectFormData): ProjectFormData => ({
      ...currentData,
      duration: currentData.filmLength || currentData.duration,
      filmLength: currentData.filmLength || (currentData.duration as FilmLengthOption | undefined),
      phaseStatus: derivePhaseStatus(currentData),
      phaseVisibility: ensureProjectPhaseVisibility(currentData),
    }),
    []
  );

  // Auto-save function (only for editing existing projects)
  const autoSave = useCallback(async () => {
    if (!isEditing || !projectId) return;

    // Don't auto-save if currently submitting or uploading
    if (isSubmitting || isUploadingImage || uploadingCharacterIndex !== null) return;

    setAutoSaveStatus("saving");

    try {
      const { submitProjectForm } = await import("@/lib/actions/projects");
      const persistedData = buildPersistedFormData(formData);
      const result = await submitProjectForm(persistedData, projectId, undefined, true); // true = skipRedirect

      if (result && !result.success) {
        throw new Error(result.error || "Failed to auto-save");
      }

      lastSavedDataRef.current = JSON.stringify(persistedData);
      setAutoSaveStatus("saved");

      // Reset to idle after 3 seconds
      setTimeout(() => {
        setAutoSaveStatus("idle");
      }, 3000);
    } catch (error) {
      // Ignore redirect errors (shouldn't happen with skipRedirect)
      if (error && typeof error === "object" && "digest" in error) {
        const errorDigest = String((error as { digest?: string }).digest || "");
        if (errorDigest.includes("NEXT_REDIRECT")) {
          lastSavedDataRef.current = JSON.stringify(formData);
          setAutoSaveStatus("saved");
          return;
        }
      }

      console.error("Auto-save error:", error);
      setAutoSaveStatus("error");

      // Reset to idle after 5 seconds
      setTimeout(() => {
        setAutoSaveStatus("idle");
      }, 5000);
    }
  }, [
    buildPersistedFormData,
    formData,
    isEditing,
    projectId,
    isSubmitting,
    isUploadingImage,
    uploadingCharacterIndex,
  ]);

  // Auto-save effect with debounce
  useEffect(() => {
    // Skip auto-save on initial mount
    if (isInitialMount.current) {
      isInitialMount.current = false;
      return;
    }

    // Only auto-save when editing existing projects
    if (!isEditing || !projectId) return;

    // Check if data has actually changed
    const currentData = JSON.stringify(formData);
    if (currentData === lastSavedDataRef.current) return;

    // Clear existing timeout
    if (autoSaveTimeoutRef.current) {
      clearTimeout(autoSaveTimeoutRef.current);
    }

    // Debounce: wait 2 seconds after last change before saving
    autoSaveTimeoutRef.current = setTimeout(() => {
      autoSave();
    }, 2000);

    // Cleanup
    return () => {
      if (autoSaveTimeoutRef.current) {
        clearTimeout(autoSaveTimeoutRef.current);
      }
    };
  }, [formData, isEditing, projectId, autoSave]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    setIsSubmitting(true);

    // Show loading toast
    const loadingToast = toast.loading(isEditing ? "Updating project..." : "Creating project...");

    try {
      // Generate slug for new projects
      const persistedData = buildPersistedFormData({
        ...formData,
        slug:
          !isEditing && formData.title
            ? formData.title
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/(^-|-$)/g, "")
            : formData.slug,
      });

      // Import and call the Server Action
      const { submitProjectForm } = await import("@/lib/actions/projects");

      // This will handle both create and update, plus authentication
      const result = await submitProjectForm(
        persistedData,
        projectId,
        redirectPath,
        false,
        !isEditing ? effectiveProjectId : undefined
      );

      // If there's an error result (not a redirect), show it
      if (result && !result.success) {
        throw new Error(result.error || "Failed to save project");
      }

      // Dismiss loading and show success
      toast.success(isEditing ? "Project updated successfully!" : "Project created successfully!", {
        id: loadingToast,
      });

      // If we get here and didn't redirect, navigate manually
      // (though submitProjectForm should redirect on success)
      router.push(redirectPath);
    } catch (error) {
      // Check if this is a Next.js redirect error - if so, let it propagate
      if (error && typeof error === "object" && "digest" in error) {
        const errorDigest = String(error.digest || "");
        if (errorDigest.includes("NEXT_REDIRECT")) {
          // Re-throw redirect errors to let Next.js handle them
          // Don't reset submitting state here as redirect will navigate away
          throw error;
        }
      }

      console.error("Error submitting project:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Failed to save project. Please try again.";

      // Dismiss loading and show error
      toast.error(errorMessage, {
        id: loadingToast,
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleSyncScenesFromBreakdown = useCallback(() => {
    const scriptBreakdown = formData.development?.scriptBreakdown || [];

    if (scriptBreakdown.length === 0) {
      toast.error("No script breakdown available to sync.");
      return;
    }

    const existingScenes = new Map(
      (formData.scenes || []).map((scene) => [scene.title.trim().toLowerCase(), scene])
    );
    const now = new Date().toISOString();
    const nextScenes = scriptBreakdown.map((item, index) => {
      const existingScene = existingScenes.get(item.title.trim().toLowerCase());

      return {
        id:
          existingScene?.id || `scene-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
        projectId: existingScene?.projectId || effectiveProjectId,
        sceneNumber: index + 1,
        title: item.title,
        screenplay: existingScene?.screenplay || `${item.title}\n\n${item.summary}`,
        summary: item.summary,
        dramaticPurpose: item.dramaticPurpose,
        emotionalBeat: item.emotionalBeat,
        visualIntent: item.visualIntent,
        characters: item.characters,
        locationId: item.locationName || existingScene?.locationId,
        promptShots: existingScene?.promptShots || [],
        shots: existingScene?.shots || [],
        audioTracks: existingScene?.audioTracks || [],
        transitionOut: existingScene?.transitionOut || { type: "none", durationMs: 0 },
        generatedImages: existingScene?.generatedImages || [],
        generatedVideos: existingScene?.generatedVideos || [],
        createdAt: existingScene?.createdAt || now,
        updatedAt: now,
      };
    });

    setFormData((prev) => ({
      ...prev,
      scenes: nextScenes,
    }));
    toast.success("Scenes synced from the script breakdown");
  }, [formData.development?.scriptBreakdown, formData.scenes, projectId]);

  const handleCancel = () => {
    router.push(redirectPath);
  };

  const createProjectFromWizard = async (data: ProjectFormData) => {
    const loadingToast = toast.loading("Creating project...");
    setIsSubmitting(true);

    try {
      const persistedData = buildPersistedFormData({
        ...data,
        slug: data.title
          ? data.title
              .toLowerCase()
              .replace(/[^a-z0-9]+/g, "-")
              .replace(/(^-|-$)/g, "")
          : data.slug,
      });

      const { submitProjectForm } = await import("@/lib/actions/projects");
      const result = await submitProjectForm(
        persistedData,
        undefined,
        redirectPath,
        true,
        effectiveProjectId
      );

      if (!result?.success || !result.projectId) {
        throw new Error(result?.error || "Failed to create project");
      }

      toast.success("Project created successfully!", { id: loadingToast });
      router.push(`/dashboard/projects/${result.projectId}/edit`);
      return result.projectId;
    } catch (error) {
      console.error("Error creating project from wizard:", error);
      toast.error(error instanceof Error ? error.message : "Failed to create project", {
        id: loadingToast,
      });
      throw error;
    } finally {
      setIsSubmitting(false);
    }
  };

  const startOverWizard = async () => {
    if (isEditing) {
      return;
    }

    if (formData.development?.sourceDocument?.filename || formData.development?.sourceTextKey) {
      try {
        const { removeSourceDocument } = await import("@/lib/actions/projects");
        await removeSourceDocument(
          effectiveProjectId,
          formData.development?.sourceDocument?.filename,
          formData.development?.sourceTextKey
        );
      } catch (error) {
        console.error("Error removing source document during start over:", error);
      }
    }

    const emptyData = createEmptyProjectFormData();
    setFormData(emptyData);
    setDraftProjectId(`project-draft-${Date.now()}`);
    setWizardResetKey((current) => current + 1);
    setNewLinkUrl("");
    setSelectedTool({ video: "", image: "", sound: "", other: "" });
    setCustomToolInput({ video: "", image: "", sound: "", other: "" });
    setPreviewImage(null);
    setHasVideoTool(false);
    setEditingCharacterIndex(null);
    setConfirmingCharacterDelete(null);
    setShowAllCharacters(false);
    setShowExtractCharactersDialog(false);
    setIsExtractingCharacters(false);
    setEditingLocationIndex(null);
    setConfirmingLocationDelete(null);
    setShowAllLocations(false);
    setShowExtractLocationsDialog(false);
    setIsExtractingLocations(false);
    setShowRemoveScreenplayConfirm(false);
    setCharacterPreviewImages({});
    setCharacterAdditionalPreviewImages({});
    setLocationPreviewImages({});
    setLocationAdditionalPreviewImages({});
    setUploadingCharacterIndex(null);
    setUploadingCharacterAdditionalIndex(null);
    setUploadingLocationIndex(null);
    setUploadingLocationAdditionalIndex(null);
    setAutoSaveStatus("idle");
    setIsEditingProjectInfo(true);
    lastSavedDataRef.current = JSON.stringify(emptyData);

    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }

    if (projectFileInputRef.current) {
      projectFileInputRef.current.value = "";
    }
  };

  const addLink = () => {
    if (newLinkUrl.trim()) {
      const label = inferLabelFromUrl(newLinkUrl);
      setFormData({
        ...formData,
        links: {
          links: [...formData.links.links, { label, url: newLinkUrl.trim() }],
        },
      });
      setNewLinkUrl("");
    }
  };

  const removeLink = (index: number) => {
    setFormData({
      ...formData,
      links: {
        links: formData.links.links.filter((_, i) => i !== index),
      },
    });
  };

  const addTool = (category: ToolCategory, toolName?: string) => {
    const nameToAdd =
      toolName ||
      (selectedTool[category] === "Other"
        ? customToolInput[category].trim()
        : selectedTool[category]);

    if (nameToAdd) {
      const newTools = [...formData.tools, { name: nameToAdd, category }];
      setFormData({
        ...formData,
        tools: newTools,
      });

      // Reset the inputs
      if (selectedTool[category] === "Other") {
        setCustomToolInput({ ...customToolInput, [category]: "" });
      }
      setSelectedTool({ ...selectedTool, [category]: "" });

      // Update video tool tracker
      if (category === "video") {
        setHasVideoTool(true);
      }
    }
  };

  const removeTool = (index: number) => {
    const toolToRemove = formData.tools[index];
    const newTools = formData.tools.filter((_, i) => i !== index);

    setFormData({
      ...formData,
      tools: newTools,
    });

    // Update video tool tracker if we removed a video tool
    if (toolToRemove.category === "video") {
      setHasVideoTool(newTools.some((tool) => tool.category === "video"));
    }
  };

  const getToolsByCategory = (category: ToolCategory) => {
    return formData.tools.filter((tool) => tool.category === category);
  };

  const getCategoryLabel = (category: ToolCategory): string => {
    const labels = {
      image: "Image Generation",
      video: "Video Generation",
      sound: "Sound Generation",
      other: "Multimedia",
    };
    return labels[category];
  };

  const addCharacter = () => {
    const newCharacters = [
      ...(formData.characters || []),
      { name: "", appearance: "", role: "", motivation: "", arc: "", visualPrompt: "" },
    ];
    setFormData({
      ...formData,
      characters: newCharacters,
    });
    setEditingCharacterIndex(newCharacters.length - 1);
  };

  const removeCharacter = (index: number) => {
    const newCharacters = formData.characters?.filter((_, i) => i !== index) || [];
    setFormData({
      ...formData,
      characters: newCharacters,
    });
    // Clean up preview images and refs
    const newPreviews = { ...characterPreviewImages };
    delete newPreviews[index];
    setCharacterPreviewImages(newPreviews);

    const newAdditionalPreviews = { ...characterAdditionalPreviewImages };
    delete newAdditionalPreviews[index];
    setCharacterAdditionalPreviewImages(newAdditionalPreviews);
  };

  const updateCharacter = (index: number, field: keyof Character, value: string | string[]) => {
    const newCharacters = [...(formData.characters || [])];
    newCharacters[index] = { ...newCharacters[index], [field]: value };
    setFormData({
      ...formData,
      characters: newCharacters,
    });
  };

  // Extract characters from screenplay
  const handleExtractCharacters = () => {
    if (!formData.screenplayText?.trim()) {
      toast.error("No screenplay text to extract characters from. Please add a screenplay first.");
      return;
    }

    // If there are existing characters, show confirmation dialog
    if ((formData.characters?.length || 0) > 0) {
      setShowExtractCharactersDialog(true);
    } else {
      performCharacterExtraction();
    }
  };

  const performCharacterExtraction = () => {
    if (!formData.screenplayText?.trim()) return;

    setIsExtractingCharacters(true);
    const loadingToast = toast.loading("Extracting characters from screenplay...");

    try {
      const characterNames = extractAllCharacters(formData.screenplayText);

      if (characterNames.length === 0) {
        toast.error(
          "No characters found. Characters must have at least 3 dialogue cues (ALL CAPS names) to be extracted.",
          { id: loadingToast }
        );
        return;
      }

      // Convert to Character objects
      const newCharacters: Character[] = characterNames.map((name) => ({
        name,
        appearance: "",
        role: "",
        motivation: "",
        arc: "",
        visualPrompt: "",
      }));

      setFormData({
        ...formData,
        characters: newCharacters,
      });

      toast.success(
        `Extracted ${characterNames.length} character${characterNames.length !== 1 ? "s" : ""} from screenplay`,
        { id: loadingToast }
      );
    } catch (error) {
      console.error(
        "[ProjectForm] Error extracting characters:",
        JSON.stringify({ error }, null, 2)
      );
      toast.error("Failed to extract characters", { id: loadingToast });
    } finally {
      setIsExtractingCharacters(false);
      setShowExtractCharactersDialog(false);
    }
  };

  // Extract locations from screenplay
  const handleExtractLocations = () => {
    if (!formData.screenplayText?.trim()) {
      toast.error("No screenplay text to extract locations from. Please add a screenplay first.");
      return;
    }

    // If there are existing locations, show confirmation dialog
    if ((formData.setting?.locations?.length || 0) > 0) {
      setShowExtractLocationsDialog(true);
    } else {
      performLocationExtraction();
    }
  };

  const performLocationExtraction = () => {
    if (!formData.screenplayText?.trim()) return;

    setIsExtractingLocations(true);
    const loadingToast = toast.loading("Extracting locations from screenplay...");

    try {
      const locationNames = extractAllLocations(formData.screenplayText);

      if (locationNames.length === 0) {
        toast.error(
          "No locations found in the screenplay. Locations are detected from scene headings (INT./EXT.).",
          { id: loadingToast }
        );
        return;
      }

      // Convert to Location objects
      const newLocations: Location[] = locationNames.map((name) => ({
        name,
        description: "",
        storyPurpose: "",
        visualPrompt: "",
      }));

      setFormData({
        ...formData,
        setting: {
          ...formData.setting,
          locations: newLocations,
        },
      });

      toast.success(
        `Extracted ${locationNames.length} location${locationNames.length !== 1 ? "s" : ""} from screenplay`,
        { id: loadingToast }
      );
    } catch (error) {
      console.error(
        "[ProjectForm] Error extracting locations:",
        JSON.stringify({ error }, null, 2)
      );
      toast.error("Failed to extract locations", { id: loadingToast });
    } finally {
      setIsExtractingLocations(false);
      setShowExtractLocationsDialog(false);
    }
  };

  const handleCharacterMainImageClick = (index: number) => {
    characterFileInputRefs.current[index]?.click();
  };

  const handleCharacterMainImageChange = async (
    e: React.ChangeEvent<HTMLInputElement>,
    index: number
  ) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith("image/")) {
      toast.error("Please select an image file");
      return;
    }

    // Validate raw file size (max 20MB - we'll compress it)
    const maxRawSize = 20 * 1024 * 1024; // 20MB
    if (file.size > maxRawSize) {
      toast.error("Image must be less than 20MB");
      return;
    }

    // Create preview
    const reader = new FileReader();
    reader.onloadend = () => {
      setCharacterPreviewImages({
        ...characterPreviewImages,
        [index]: reader.result as string,
      });
    };
    reader.readAsDataURL(file);

    // Compress and upload image
    setUploadingCharacterIndex(index);
    const loadingToast = toast.loading("Compressing image...");

    try {
      // Compress image client-side (maintain original aspect ratio, max 3840x3840 to accommodate any orientation)
      const compressedFile = await compressImage(file, 3840, 3840, 0.85);

      // Validate compressed size (max 2MB)
      const maxCompressedSize = 2 * 1024 * 1024; // 2MB
      if (compressedFile.size > maxCompressedSize) {
        toast.error("Compressed image is still too large. Please try a smaller image.", {
          id: loadingToast,
        });
        setUploadingCharacterIndex(null);
        return;
      }

      toast.loading("Uploading character image...", { id: loadingToast });

      const { uploadCharacterImage } = await import("@/lib/actions/projects");
      const uploadFormData = new FormData();
      uploadFormData.append("image", compressedFile);

      const result = await uploadCharacterImage(uploadFormData);

      if (result.success && result.imageFilename) {
        const newCharacters = [...(formData.characters || [])];
        newCharacters[index] = { ...newCharacters[index], mainImage: result.imageFilename };
        setFormData({
          ...formData,
          characters: newCharacters,
        });
        setCharacterPreviewImages({
          ...characterPreviewImages,
          [index]: "",
        });
        toast.success("Character image uploaded successfully!", {
          id: loadingToast,
        });
      }
    } catch (error) {
      console.error("Error uploading character image:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Failed to upload character image";
      toast.error(errorMessage, {
        id: loadingToast,
      });
      setCharacterPreviewImages({
        ...characterPreviewImages,
        [index]: "",
      });
    } finally {
      setUploadingCharacterIndex(null);
      // Reset file input
      const fileInput = characterFileInputRefs.current[index];
      if (fileInput) {
        fileInput.value = "";
      }
    }
  };

  const handleCharacterAdditionalImageChange = async (
    e: React.ChangeEvent<HTMLInputElement>,
    characterIndex: number,
    imageIndex: number
  ) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith("image/")) {
      toast.error("Please select an image file");
      return;
    }

    // Validate raw file size (max 20MB - we'll compress it)
    const maxRawSize = 20 * 1024 * 1024; // 20MB
    if (file.size > maxRawSize) {
      toast.error("Image must be less than 20MB");
      return;
    }

    // Create preview
    const reader = new FileReader();
    reader.onloadend = () => {
      setCharacterAdditionalPreviewImages({
        ...characterAdditionalPreviewImages,
        [characterIndex]: {
          ...characterAdditionalPreviewImages[characterIndex],
          [imageIndex]: reader.result as string,
        },
      });
    };
    reader.readAsDataURL(file);

    // Compress and upload image
    setUploadingCharacterAdditionalIndex({ characterIndex, imageIndex });
    const loadingToast = toast.loading("Compressing image...");

    try {
      // Compress image client-side (maintain original aspect ratio, max 3840x3840 to accommodate any orientation)
      const compressedFile = await compressImage(file, 3840, 3840, 0.85);

      // Validate compressed size (max 2MB)
      const maxCompressedSize = 2 * 1024 * 1024; // 2MB
      if (compressedFile.size > maxCompressedSize) {
        toast.error("Compressed image is still too large. Please try a smaller image.", {
          id: loadingToast,
        });
        setUploadingCharacterAdditionalIndex(null);
        return;
      }

      toast.loading("Uploading character image...", { id: loadingToast });

      const { uploadCharacterImage } = await import("@/lib/actions/projects");
      const uploadFormData = new FormData();
      uploadFormData.append("image", compressedFile);

      const result = await uploadCharacterImage(uploadFormData);

      if (result.success && result.imageFilename) {
        const newCharacters = [...(formData.characters || [])];
        const currentImages = newCharacters[characterIndex].images || [];
        const newImages = [...currentImages];
        newImages[imageIndex] = result.imageFilename;
        newCharacters[characterIndex] = {
          ...newCharacters[characterIndex],
          images: newImages,
        };
        setFormData({
          ...formData,
          characters: newCharacters,
        });
        const newPreviews = { ...characterAdditionalPreviewImages };
        if (newPreviews[characterIndex]) {
          delete newPreviews[characterIndex][imageIndex];
        }
        setCharacterAdditionalPreviewImages(newPreviews);
        toast.success("Character image uploaded successfully!", {
          id: loadingToast,
        });
      }
    } catch (error) {
      console.error("Error uploading character image:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Failed to upload character image";
      toast.error(errorMessage, {
        id: loadingToast,
      });
      const newPreviews = { ...characterAdditionalPreviewImages };
      if (newPreviews[characterIndex]) {
        delete newPreviews[characterIndex][imageIndex];
      }
      setCharacterAdditionalPreviewImages(newPreviews);
    } finally {
      setUploadingCharacterAdditionalIndex(null);
      // Reset file input
      const fileInput = characterAdditionalFileInputRefs.current[`${characterIndex}-${imageIndex}`];
      if (fileInput) {
        fileInput.value = "";
      }
    }
  };

  const handleCharacterAdditionalImageClick = (characterIndex: number, imageIndex: number) => {
    characterAdditionalFileInputRefs.current[`${characterIndex}-${imageIndex}`]?.click();
  };

  const handleAddCharacterAdditionalImageClick = (characterIndex: number) => {
    characterAddImageInputRefs.current[characterIndex]?.click();
  };

  const handleAddCharacterAdditionalImageChange = async (
    e: React.ChangeEvent<HTMLInputElement>,
    characterIndex: number
  ) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;

    // Convert FileList to array
    const fileArray = Array.from(files);

    // Validate all files
    const maxRawSize = 20 * 1024 * 1024; // 20MB
    const validFiles: File[] = [];
    for (const file of fileArray) {
      if (!file.type.startsWith("image/")) {
        toast.error(`"${file.name}" is not an image file, skipping...`);
        continue;
      }
      if (file.size > maxRawSize) {
        toast.error(`"${file.name}" is too large (max 20MB), skipping...`);
        continue;
      }
      validFiles.push(file);
    }

    if (validFiles.length === 0) return;

    // Get starting image index
    const currentImages = formData.characters?.[characterIndex]?.images || [];
    const nextImageIndex = currentImages.length;

    // Show initial loading toast
    const loadingToast = toast.loading(
      `Uploading ${validFiles.length} image${validFiles.length > 1 ? "s" : ""}...`
    );
    setUploadingCharacterAdditionalIndex({ characterIndex, imageIndex: nextImageIndex });

    const uploadedFilenames: string[] = [];
    const newPreviews: Record<number, string> = {};

    try {
      const { uploadCharacterImage } = await import("@/lib/actions/projects");

      for (let i = 0; i < validFiles.length; i++) {
        const file = validFiles[i];
        const imageIndex = nextImageIndex + i;

        // Create preview for this image
        const reader = new FileReader();
        reader.onloadend = () => {
          newPreviews[imageIndex] = reader.result as string;
          setCharacterAdditionalPreviewImages((prev) => ({
            ...prev,
            [characterIndex]: {
              ...prev[characterIndex],
              [imageIndex]: reader.result as string,
            },
          }));
        };
        reader.readAsDataURL(file);

        toast.loading(`Uploading image ${i + 1} of ${validFiles.length}...`, { id: loadingToast });

        // Compress image client-side
        const compressedFile = await compressImage(file, 3840, 3840, 0.85);

        // Validate compressed size (max 2MB)
        const maxCompressedSize = 2 * 1024 * 1024; // 2MB
        if (compressedFile.size > maxCompressedSize) {
          toast.error(`"${file.name}" is still too large after compression, skipping...`);
          continue;
        }

        const uploadFormData = new FormData();
        uploadFormData.append("image", compressedFile);

        const result = await uploadCharacterImage(uploadFormData);

        if (result.success && result.imageFilename) {
          uploadedFilenames.push(result.imageFilename);
        } else {
          toast.error(`Failed to upload "${file.name}"`);
        }
      }

      if (uploadedFilenames.length > 0) {
        // Update form data with all uploaded images
        const newCharacters = [...(formData.characters || [])];
        const existingImages = newCharacters[characterIndex].images || [];
        newCharacters[characterIndex] = {
          ...newCharacters[characterIndex],
          images: [...existingImages, ...uploadedFilenames],
        };
        setFormData({
          ...formData,
          characters: newCharacters,
        });

        // Clear previews for uploaded images
        setCharacterAdditionalPreviewImages((prev) => {
          const updated = { ...prev };
          if (updated[characterIndex]) {
            for (let i = 0; i < uploadedFilenames.length; i++) {
              delete updated[characterIndex][nextImageIndex + i];
            }
          }
          return updated;
        });

        toast.success(
          `${uploadedFilenames.length} image${uploadedFilenames.length > 1 ? "s" : ""} uploaded successfully!`,
          { id: loadingToast }
        );
      } else {
        toast.error("No images were uploaded", { id: loadingToast });
      }
    } catch (error) {
      console.error("Error uploading character images:", JSON.stringify({ error }, null, 2));
      const errorMessage =
        error instanceof Error ? error.message : "Failed to upload character images";
      toast.error(errorMessage, { id: loadingToast });

      // Clear all previews on error
      setCharacterAdditionalPreviewImages((prev) => {
        const updated = { ...prev };
        if (updated[characterIndex]) {
          for (const key of Object.keys(newPreviews)) {
            delete updated[characterIndex][Number(key)];
          }
        }
        return updated;
      });
    } finally {
      setUploadingCharacterAdditionalIndex(null);
      // Reset file input
      const fileInput = characterAddImageInputRefs.current[characterIndex];
      if (fileInput) {
        fileInput.value = "";
      }
    }
  };

  const removeCharacterAdditionalImage = (characterIndex: number, imageIndex: number) => {
    const newCharacters = [...(formData.characters || [])];
    const currentImages = newCharacters[characterIndex].images || [];
    newCharacters[characterIndex] = {
      ...newCharacters[characterIndex],
      images: currentImages.filter((_, i) => i !== imageIndex),
    };
    setFormData({
      ...formData,
      characters: newCharacters,
    });
    // Clean up preview
    const newPreviews = { ...characterAdditionalPreviewImages };
    if (newPreviews[characterIndex]) {
      const currentPreviews = { ...newPreviews[characterIndex] };
      delete currentPreviews[imageIndex];
      // Reindex remaining previews
      const reindexed: Record<number, string> = {};
      Object.keys(currentPreviews).forEach((key) => {
        const oldIndex = Number(key);
        if (oldIndex < imageIndex) {
          reindexed[oldIndex] = currentPreviews[oldIndex];
        } else if (oldIndex > imageIndex) {
          reindexed[oldIndex - 1] = currentPreviews[oldIndex];
        }
      });
      newPreviews[characterIndex] = reindexed;
    }
    setCharacterAdditionalPreviewImages(newPreviews);
  };

  // ============================================================================
  // LOCATION HANDLERS
  // ============================================================================

  /**
   * Extract unique locations from screenplay text by parsing scene headings (INT./EXT. lines)
   * Returns just the core location name (no INT/EXT prefix, no DAY/NIGHT suffix)
   * Preserves order as they appear in the screenplay
   */
  const extractLocationsFromScreenplay = (screenplayText: string): string[] => {
    if (!screenplayText) return [];

    // Split by lines and process each line
    const lines = screenplayText.split(/\r?\n/);
    const timeSuffixPattern =
      /\s*[-–—]\s*(?:DAY|NIGHT|MORNING|EVENING|LATER|CONTINUOUS|SAME|DUSK|DAWN)$/i;

    // Use Map to preserve order and track unique locations (case-insensitive)
    const locationsMap = new Map<string, string>();

    for (const line of lines) {
      const trimmedLine = line.trim();

      // Check if line starts with INT. or EXT. and capture the location name
      const sceneMatch = trimmedLine.match(/^(?:INT\.|EXT\.|INT\.\/EXT\.|I\/E\.)\s*(.+)$/i);
      if (!sceneMatch) continue;

      let locationName = sceneMatch[1].trim();

      // Remove time suffix if present
      locationName = locationName.replace(timeSuffixPattern, "").trim();

      if (!locationName) continue;

      // Normalize key for deduplication (uppercase, just the core name)
      const normalizedKey = locationName.toUpperCase();

      // Only add if we haven't seen this location before
      if (!locationsMap.has(normalizedKey)) {
        // Store with original casing
        locationsMap.set(normalizedKey, locationName);
      }
    }

    // Return in order of appearance (Map preserves insertion order)
    return Array.from(locationsMap.values());
  };

  // Auto-sync locations from screenplay when screenplay text changes (non-destructive)
  useEffect(() => {
    if (!formData.screenplayText) return;

    const extractedNames = extractLocationsFromScreenplay(formData.screenplayText);
    if (extractedNames.length === 0) return;

    // Get existing locations
    const existingLocations = formData.setting?.locations || [];
    const existingNames = new Set(existingLocations.map((loc) => loc.name.toUpperCase()));

    // Check if there are new locations to add
    const newLocationNames = extractedNames.filter(
      (name) => !existingNames.has(name.toUpperCase())
    );

    // Only update if there are new locations to add
    if (newLocationNames.length === 0) return;

    // Add new locations while preserving existing ones with images
    const newLocations: Location[] = [
      ...existingLocations,
      ...newLocationNames.map((name) => ({
        name,
        description: "",
        storyPurpose: "",
        visualPrompt: "",
      })),
    ];

    setFormData((prev) => ({
      ...prev,
      setting: { ...prev.setting, locations: newLocations },
    }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [formData.screenplayText, formData.setting?.locations, extractLocationsFromScreenplay]);

  const addLocation = () => {
    const newLocations = [
      ...(formData.setting?.locations || []),
      { name: "", description: "", storyPurpose: "", visualPrompt: "" },
    ];
    setFormData({
      ...formData,
      setting: { ...formData.setting, locations: newLocations },
    });
    setEditingLocationIndex(newLocations.length - 1);
  };

  const removeLocation = (index: number) => {
    const newLocations = formData.setting?.locations?.filter((_, i) => i !== index) || [];
    setFormData({
      ...formData,
      setting: { ...formData.setting, locations: newLocations },
    });
    // Clean up preview images and refs
    const newPreviews = { ...locationPreviewImages };
    delete newPreviews[index];
    setLocationPreviewImages(newPreviews);

    const newAdditionalPreviews = { ...locationAdditionalPreviewImages };
    delete newAdditionalPreviews[index];
    setLocationAdditionalPreviewImages(newAdditionalPreviews);
  };

  const updateLocation = (index: number, field: keyof Location, value: string | string[]) => {
    const newLocations = [...(formData.setting?.locations || [])];
    newLocations[index] = { ...newLocations[index], [field]: value };
    setFormData({
      ...formData,
      setting: { ...formData.setting, locations: newLocations },
    });
  };

  const handleLocationMainImageClick = (index: number) => {
    locationFileInputRefs.current[index]?.click();
  };

  const _handleLocationDescriptionChange = (index: number, description: string) => {
    const newLocations = [...(formData.setting?.locations || [])];
    newLocations[index] = { ...newLocations[index], description };
    setFormData({
      ...formData,
      setting: { ...formData.setting, locations: newLocations },
    });
  };

  const handleLocationMainImageChange = async (
    e: React.ChangeEvent<HTMLInputElement>,
    index: number
  ) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith("image/")) {
      toast.error("Please select an image file");
      return;
    }

    // Validate raw file size (max 20MB - we'll compress it)
    const maxRawSize = 20 * 1024 * 1024; // 20MB
    if (file.size > maxRawSize) {
      toast.error("Image must be less than 20MB");
      return;
    }

    // Create preview
    const reader = new FileReader();
    reader.onloadend = () => {
      setLocationPreviewImages({
        ...locationPreviewImages,
        [index]: reader.result as string,
      });
    };
    reader.readAsDataURL(file);

    // Compress and upload image
    setUploadingLocationIndex(index);
    const loadingToast = toast.loading("Compressing image...");

    try {
      // Compress image client-side
      const compressedFile = await compressImage(file, 3840, 3840, 0.85);

      // Validate compressed size (max 2MB)
      const maxCompressedSize = 2 * 1024 * 1024; // 2MB
      if (compressedFile.size > maxCompressedSize) {
        toast.error("Compressed image is still too large. Please try a smaller image.", {
          id: loadingToast,
        });
        const newPreviews = { ...locationPreviewImages };
        delete newPreviews[index];
        setLocationPreviewImages(newPreviews);
        return;
      }

      toast.loading("Uploading image...", { id: loadingToast });

      const { uploadLocationImage } = await import("@/lib/actions/projects");
      const uploadFormData = new FormData();
      uploadFormData.append("image", compressedFile);

      const result = await uploadLocationImage(uploadFormData);

      if (result.imageFilename) {
        // Update formData with the uploaded filename
        const newLocations = [...(formData.setting?.locations || [])];
        newLocations[index] = { ...newLocations[index], image: result.imageFilename };
        setFormData({
          ...formData,
          setting: { ...formData.setting, locations: newLocations },
        });
        // Clear preview since we now have the uploaded image
        const newPreviews = { ...locationPreviewImages };
        delete newPreviews[index];
        setLocationPreviewImages(newPreviews);
        toast.success("Location image uploaded successfully!", { id: loadingToast });
      }
    } catch (error) {
      console.error("Error uploading location image:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Failed to upload location image";
      toast.error(errorMessage, { id: loadingToast });
      // Clear preview on error
      const newPreviews = { ...locationPreviewImages };
      delete newPreviews[index];
      setLocationPreviewImages(newPreviews);
    } finally {
      setUploadingLocationIndex(null);
      // Reset file input
      const fileInput = locationFileInputRefs.current[index];
      if (fileInput) {
        fileInput.value = "";
      }
    }
  };

  const handleLocationAdditionalImageClick = (locationIndex: number, imageIndex: number) => {
    locationAdditionalFileInputRefs.current[`${locationIndex}-${imageIndex}`]?.click();
  };

  const handleLocationAdditionalImageChange = async (
    e: React.ChangeEvent<HTMLInputElement>,
    locationIndex: number,
    imageIndex: number
  ) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith("image/")) {
      toast.error("Please select an image file");
      return;
    }

    // Validate raw file size (max 20MB - we'll compress it)
    const maxRawSize = 20 * 1024 * 1024; // 20MB
    if (file.size > maxRawSize) {
      toast.error("Image must be less than 20MB");
      return;
    }

    // Create preview
    const reader = new FileReader();
    reader.onloadend = () => {
      setLocationAdditionalPreviewImages({
        ...locationAdditionalPreviewImages,
        [locationIndex]: {
          ...locationAdditionalPreviewImages[locationIndex],
          [imageIndex]: reader.result as string,
        },
      });
    };
    reader.readAsDataURL(file);

    // Compress and upload image
    setUploadingLocationAdditionalIndex({ locationIndex, imageIndex });
    const loadingToast = toast.loading("Compressing image...");

    try {
      // Compress image client-side
      const compressedFile = await compressImage(file, 3840, 3840, 0.85);

      // Validate compressed size (max 2MB)
      const maxCompressedSize = 2 * 1024 * 1024; // 2MB
      if (compressedFile.size > maxCompressedSize) {
        toast.error("Compressed image is still too large. Please try a smaller image.", {
          id: loadingToast,
        });
        setUploadingLocationAdditionalIndex(null);
        return;
      }

      toast.loading("Uploading location image...", { id: loadingToast });

      const { uploadLocationImage } = await import("@/lib/actions/projects");
      const uploadFormData = new FormData();
      uploadFormData.append("image", compressedFile);

      const result = await uploadLocationImage(uploadFormData);

      if (result.imageFilename) {
        const newLocations = [...(formData.setting?.locations || [])];
        const currentImages = newLocations[locationIndex].images || [];
        // Replace the existing image at this index
        const newImages = [...currentImages];
        newImages[imageIndex] = result.imageFilename;
        newLocations[locationIndex] = {
          ...newLocations[locationIndex],
          images: newImages,
        };
        setFormData({
          ...formData,
          setting: { ...formData.setting, locations: newLocations },
        });
        const newPreviews = { ...locationAdditionalPreviewImages };
        if (newPreviews[locationIndex]) {
          delete newPreviews[locationIndex][imageIndex];
        }
        setLocationAdditionalPreviewImages(newPreviews);
        toast.success("Location image uploaded successfully!", {
          id: loadingToast,
        });
      }
    } catch (error) {
      console.error("Error uploading location image:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Failed to upload location image";
      toast.error(errorMessage, {
        id: loadingToast,
      });
      const newPreviews = { ...locationAdditionalPreviewImages };
      if (newPreviews[locationIndex]) {
        delete newPreviews[locationIndex][imageIndex];
      }
      setLocationAdditionalPreviewImages(newPreviews);
    } finally {
      setUploadingLocationAdditionalIndex(null);
      // Reset file input
      const fileInput = locationAdditionalFileInputRefs.current[`${locationIndex}-${imageIndex}`];
      if (fileInput) {
        fileInput.value = "";
      }
    }
  };

  const handleAddLocationAdditionalImageClick = (locationIndex: number) => {
    locationAddImageInputRefs.current[locationIndex]?.click();
  };

  const handleAddLocationAdditionalImageChange = async (
    e: React.ChangeEvent<HTMLInputElement>,
    locationIndex: number
  ) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith("image/")) {
      toast.error("Please select an image file");
      return;
    }

    // Validate raw file size (max 20MB - we'll compress it)
    const maxRawSize = 20 * 1024 * 1024; // 20MB
    if (file.size > maxRawSize) {
      toast.error("Image must be less than 20MB");
      return;
    }

    // Get the next image index
    const currentImages = formData.setting?.locations?.[locationIndex]?.images || [];
    const imageIndex = currentImages.length;

    // Create preview
    const reader = new FileReader();
    reader.onloadend = () => {
      setLocationAdditionalPreviewImages({
        ...locationAdditionalPreviewImages,
        [locationIndex]: {
          ...locationAdditionalPreviewImages[locationIndex],
          [imageIndex]: reader.result as string,
        },
      });
    };
    reader.readAsDataURL(file);

    // Compress and upload image
    setUploadingLocationAdditionalIndex({ locationIndex, imageIndex });
    const loadingToast = toast.loading("Compressing image...");

    try {
      // Compress image client-side
      const compressedFile = await compressImage(file, 3840, 3840, 0.85);

      // Validate compressed size (max 2MB)
      const maxCompressedSize = 2 * 1024 * 1024; // 2MB
      if (compressedFile.size > maxCompressedSize) {
        toast.error("Compressed image is still too large. Please try a smaller image.", {
          id: loadingToast,
        });
        const newPreviews = { ...locationAdditionalPreviewImages };
        if (newPreviews[locationIndex]) {
          delete newPreviews[locationIndex][imageIndex];
        }
        setLocationAdditionalPreviewImages(newPreviews);
        return;
      }

      toast.loading("Uploading image...", { id: loadingToast });

      const { uploadLocationImage } = await import("@/lib/actions/projects");
      const uploadFormData = new FormData();
      uploadFormData.append("image", compressedFile);

      const result = await uploadLocationImage(uploadFormData);

      if (result.imageFilename) {
        // Update formData with the uploaded filename
        const newLocations = [...(formData.setting?.locations || [])];
        const currentLocationImages = newLocations[locationIndex].images || [];
        newLocations[locationIndex] = {
          ...newLocations[locationIndex],
          images: [...currentLocationImages, result.imageFilename],
        };
        setFormData({
          ...formData,
          setting: { ...formData.setting, locations: newLocations },
        });
        const newPreviews = { ...locationAdditionalPreviewImages };
        if (newPreviews[locationIndex]) {
          delete newPreviews[locationIndex][imageIndex];
        }
        setLocationAdditionalPreviewImages(newPreviews);
        toast.success("Location image uploaded successfully!", { id: loadingToast });
      }
    } catch (error) {
      console.error("Error uploading location image:", error);
      const errorMessage =
        error instanceof Error ? error.message : "Failed to upload location image";
      toast.error(errorMessage, { id: loadingToast });
      const newPreviews = { ...locationAdditionalPreviewImages };
      if (newPreviews[locationIndex]) {
        delete newPreviews[locationIndex][imageIndex];
      }
      setLocationAdditionalPreviewImages(newPreviews);
    } finally {
      setUploadingLocationAdditionalIndex(null);
      // Reset file input
      const fileInput = locationAddImageInputRefs.current[locationIndex];
      if (fileInput) {
        fileInput.value = "";
      }
    }
  };

  const removeLocationAdditionalImage = (locationIndex: number, imageIndex: number) => {
    const newLocations = [...(formData.setting?.locations || [])];
    const currentImages = newLocations[locationIndex].images || [];
    newLocations[locationIndex] = {
      ...newLocations[locationIndex],
      images: currentImages.filter((_, i) => i !== imageIndex),
    };
    setFormData({
      ...formData,
      setting: { ...formData.setting, locations: newLocations },
    });
    // Clean up preview
    const newPreviews = { ...locationAdditionalPreviewImages };
    if (newPreviews[locationIndex]) {
      const currentPreviews = { ...newPreviews[locationIndex] };
      delete currentPreviews[imageIndex];
      // Reindex remaining previews
      const reindexed: Record<number, string> = {};
      Object.keys(currentPreviews).forEach((key) => {
        const oldIndex = parseInt(key, 10);
        if (oldIndex < imageIndex) {
          reindexed[oldIndex] = currentPreviews[oldIndex];
        } else if (oldIndex > imageIndex) {
          reindexed[oldIndex - 1] = currentPreviews[oldIndex];
        }
      });
      newPreviews[locationIndex] = reindexed;
    }
    setLocationAdditionalPreviewImages(newPreviews);
  };

  const handleProjectFileClick = (e: React.MouseEvent<HTMLButtonElement>) => {
    e.preventDefault();
    projectFileInputRef.current?.click();
  };

  const handleProjectFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
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

    setIsUploadingFile(true);
    const loadingToast = toast.loading("Uploading screenplay...");

    try {
      const { uploadProjectFile } = await import("@/lib/actions/projects");
      const uploadFormData = new FormData();
      uploadFormData.append("file", file);

      // Upload the PDF and extract text in one step
      const uploadResult = await uploadProjectFile(uploadFormData, true);

      if (!uploadResult.success) {
        throw new Error(uploadResult.error || "Failed to upload screenplay");
      }

      // Parse extracted text into structured elements
      let screenplayElements: ScreenplayElement[] | undefined;
      if (uploadResult.extractedText) {
        const { parseScreenplayToElements } = await import("@/lib/screenplay-parser");
        screenplayElements = parseScreenplayToElements(uploadResult.extractedText);
      }

      // Update form with uploaded file info, extracted text, and parsed elements
      // Clear locations when extracting from a new screenplay (they'll be re-extracted automatically)
      setFormData((prev) => ({
        ...prev,
        screenplay: {
          name: uploadResult.originalName,
          filename: uploadResult.filename,
          size: uploadResult.size,
          type: uploadResult.type,
        },
        ...(uploadResult.extractedText && { screenplayText: uploadResult.extractedText }),
        ...(screenplayElements && screenplayElements.length > 0 && { screenplayElements }),
        // Clear locations when extracting from screenplay - they'll be auto-extracted fresh
        ...(uploadResult.extractedText && {
          setting: { ...prev.setting, locations: [] },
        }),
      }));

      if (uploadResult.extractedText) {
        toast.success("Screenplay uploaded and text extracted successfully!", {
          id: loadingToast,
        });
      } else {
        // PDF uploaded but text extraction failed - still show success for upload
        const errorMessage = uploadResult.extractionError
          ? `Text extraction failed: ${uploadResult.extractionError}`
          : "Text extraction failed. The PDF may be image-based or corrupted.";
        toast.warning(
          `Screenplay uploaded successfully! ${errorMessage} You can manually paste the screenplay text or use the screenplay editor.`,
          {
            id: loadingToast,
            duration: 10000,
          }
        );
      }
    } catch (error) {
      console.error("Error uploading screenplay:", JSON.stringify(error, null, 2));
      const errorMessage = error instanceof Error ? error.message : "Failed to upload screenplay";
      toast.error(errorMessage, {
        id: loadingToast,
      });
    } finally {
      setIsUploadingFile(false);
      // Reset file input
      if (projectFileInputRef.current) {
        projectFileInputRef.current.value = "";
      }
    }
  };

  // Compress image client-side before upload
  const compressImage = (
    file: File,
    maxWidth: number = 1920,
    maxHeight: number = 1080,
    quality: number = 0.85,
    targetAspect?: number
  ): Promise<File> => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = (e) => {
        const img = document.createElement("img");
        img.onload = () => {
          // Calculate new dimensions maintaining aspect ratio
          let width = img.width;
          let height = img.height;

          // Resize if needed
          if (width > maxWidth || height > maxHeight) {
            const aspectRatio = width / height;
            if (width > height) {
              width = Math.min(width, maxWidth);
              height = width / aspectRatio;
            } else {
              height = Math.min(height, maxHeight);
              width = height * aspectRatio;
            }
          }

          // Crop to target aspect ratio if provided
          if (targetAspect !== undefined) {
            const currentAspect = width / height;

            if (Math.abs(currentAspect - targetAspect) > 0.01) {
              if (currentAspect > targetAspect) {
                // Image is wider, crop horizontally
                width = height * targetAspect;
              } else {
                // Image is taller, crop vertically
                height = width / targetAspect;
              }
            }
          }

          // Create canvas and draw resized image
          const canvas = document.createElement("canvas");
          canvas.width = width;
          canvas.height = height;
          const ctx = canvas.getContext("2d");

          if (!ctx) {
            reject(new Error("Could not get canvas context"));
            return;
          }

          ctx.drawImage(img, 0, 0, width, height);

          // Convert to blob and then to File
          canvas.toBlob(
            (blob) => {
              if (!blob) {
                reject(new Error("Failed to compress image"));
                return;
              }

              // Create a new File with compressed data
              const compressedFile = new globalThis.File([blob], file.name, {
                type: "image/jpeg",
                lastModified: Date.now(),
              });

              resolve(compressedFile);
            },
            "image/jpeg",
            quality
          );
        };
        img.onerror = () => reject(new Error("Failed to load image"));
        img.src = e.target?.result as string;
      };
      reader.onerror = () => reject(new Error("Failed to read file"));
      reader.readAsDataURL(file);
    });
  };

  const handleImageClick = () => {
    fileInputRef.current?.click();
  };

  const handleImageChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith("image/")) {
      toast.error("Please select an image file");
      return;
    }

    // Validate raw file size (max 20MB - we'll compress it)
    const maxRawSize = 20 * 1024 * 1024; // 20MB
    if (file.size > maxRawSize) {
      toast.error("Image must be less than 20MB");
      return;
    }

    // Create preview
    const reader = new FileReader();
    reader.onloadend = () => {
      setPreviewImage(reader.result as string);
    };
    reader.readAsDataURL(file);

    // Compress and upload image
    setIsUploadingImage(true);
    const loadingToast = toast.loading("Compressing image...");

    try {
      // Compress image client-side (16:9 aspect ratio, max 1920x1080)
      const compressedFile = await compressImage(file, 1920, 1080, 0.85, 16 / 9);

      // Validate compressed size (max 2MB - should be well under this after compression)
      const maxCompressedSize = 2 * 1024 * 1024; // 2MB
      if (compressedFile.size > maxCompressedSize) {
        toast.error("Compressed image is still too large. Please try a smaller image.", {
          id: loadingToast,
        });
        setIsUploadingImage(false);
        return;
      }

      toast.loading("Uploading thumbnail...", { id: loadingToast });

      const { uploadProjectThumbnail } = await import("@/lib/actions/projects");
      const uploadFormData = new FormData();
      uploadFormData.append("image", compressedFile);

      const result = await uploadProjectThumbnail(uploadFormData);

      if (result.success && result.thumbnailFilename) {
        setFormData({
          ...formData,
          thumbnail: result.thumbnailFilename,
        });
        setPreviewImage(null);
        toast.success("Thumbnail uploaded successfully!", {
          id: loadingToast,
        });
      }
    } catch (error) {
      console.error("Error uploading thumbnail:", error);
      const errorMessage = error instanceof Error ? error.message : "Failed to upload thumbnail";
      toast.error(errorMessage, {
        id: loadingToast,
      });
      setPreviewImage(null);
    } finally {
      setIsUploadingImage(false);
      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = "";
      }
    }
  };

  const characterWizardContent = (
    <div ref={charactersSectionRef} className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <Button type="button" variant="outline" onClick={addCharacter} className="bg-transparent">
          <Plus className="mr-2 h-4 w-4" />
          Add Character
        </Button>
        {formData.screenplayText?.trim() && (
          <Button
            type="button"
            variant="outline"
            onClick={handleExtractCharacters}
            disabled={isExtractingCharacters}
            className="bg-transparent"
          >
            {isExtractingCharacters ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Extracting...
              </>
            ) : (
              <>
                <Film className="mr-2 h-4 w-4" />
                Extract from Screenplay
              </>
            )}
          </Button>
        )}
      </div>

      {(formData.characters || []).length === 0 && (
        <div className="rounded-lg border border-dashed border-border bg-muted/20 p-6 text-sm text-muted-foreground">
          Add characters to define roles, motivations, arcs, and reference imagery before moving
          into prompts.
        </div>
      )}

      {(formData.characters || []).map((character, index) => {
        const isEditingCharacter = editingCharacterIndex === index;

        return (
          <Card key={`wizard-character-${index}`} className="border-border bg-background">
            <CardContent className="space-y-4 p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex min-w-0 items-center gap-3">
                  <div className="relative h-16 w-16 overflow-hidden rounded-lg border border-border bg-muted">
                    {characterPreviewImages[index] ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={characterPreviewImages[index]}
                        alt={character.name || "Character"}
                        className="h-full w-full object-cover"
                      />
                    ) : character.mainImage && formData.username ? (
                      <OptimizedImage
                        type="character"
                        filename={character.mainImage}
                        username={formData.username}
                        alt={character.name || "Character"}
                        fill
                        objectFit="cover"
                      />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center">
                        <User className="h-6 w-6 text-muted-foreground" />
                      </div>
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="truncate font-medium">{character.name || `Character ${index + 1}`}</p>
                    <p className="truncate text-sm text-muted-foreground">
                      {character.role || "No role yet"}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() =>
                      setEditingCharacterIndex((current) => (current === index ? null : index))
                    }
                    className="bg-transparent"
                  >
                    {isEditingCharacter ? "Done" : "Edit"}
                  </Button>
                </div>
              </div>

              {isEditingCharacter && (
                <div className="space-y-4 border-t border-border pt-4">
                  <div className="grid gap-4 md:grid-cols-2">
                    <div className="space-y-2">
                      <Label htmlFor={`wizard-character-name-${index}`}>Name</Label>
                      <Input
                        id={`wizard-character-name-${index}`}
                        value={character.name}
                        onChange={(e) => updateCharacter(index, "name", e.target.value)}
                        placeholder="Character name"
                        className="bg-background"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor={`wizard-character-role-${index}`}>Role</Label>
                      <Input
                        id={`wizard-character-role-${index}`}
                        value={character.role || ""}
                        onChange={(e) => updateCharacter(index, "role", e.target.value)}
                        placeholder="Protagonist, antagonist, mentor..."
                        className="bg-background"
                      />
                    </div>
                  </div>

                  <div className="grid gap-4 md:grid-cols-2">
                    <div className="space-y-2">
                      <Label htmlFor={`wizard-character-motivation-${index}`}>Motivation</Label>
                      <Input
                        id={`wizard-character-motivation-${index}`}
                        value={character.motivation || ""}
                        onChange={(e) => updateCharacter(index, "motivation", e.target.value)}
                        placeholder="What do they want?"
                        className="bg-background"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor={`wizard-character-arc-${index}`}>Arc</Label>
                      <Textarea
                        id={`wizard-character-arc-${index}`}
                        value={character.arc || ""}
                        onChange={(e) => updateCharacter(index, "arc", e.target.value)}
                        placeholder="How do they change?"
                        rows={2}
                        className="bg-background"
                      />
                    </div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor={`wizard-character-appearance-${index}`}>Appearance</Label>
                    <Textarea
                      id={`wizard-character-appearance-${index}`}
                      value={character.appearance}
                      onChange={(e) => updateCharacter(index, "appearance", e.target.value)}
                      placeholder="Describe the character's look..."
                      rows={3}
                      className="bg-background"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor={`wizard-character-visual-${index}`}>Visual Prompt Notes</Label>
                    <Textarea
                      id={`wizard-character-visual-${index}`}
                      value={character.visualPrompt || ""}
                      onChange={(e) => updateCharacter(index, "visualPrompt", e.target.value)}
                      placeholder="Notes for consistent image generation..."
                      rows={3}
                      className="bg-background"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label>Main Image</Label>
                    <div className="flex flex-wrap items-center gap-3">
                      <Button
                        type="button"
                        variant="outline"
                        onClick={() => handleCharacterMainImageClick(index)}
                        disabled={uploadingCharacterIndex === index}
                        className="bg-transparent"
                      >
                        <Upload className="mr-2 h-4 w-4" />
                        {uploadingCharacterIndex === index
                          ? "Uploading..."
                          : character.mainImage
                            ? "Change Main Image"
                            : "Upload Main Image"}
                      </Button>
                      <span className="text-sm text-muted-foreground">
                        {character.mainImage ? "Reference image attached" : "No main image yet"}
                      </span>
                    </div>
                    <input
                      ref={(el) => {
                        characterFileInputRefs.current[index] = el;
                      }}
                      type="file"
                      accept="image/*"
                      onChange={(e) => handleCharacterMainImageChange(e, index)}
                      className="hidden"
                      disabled={uploadingCharacterIndex === index}
                    />
                  </div>

                  <div className="space-y-2">
                    <div className="flex items-center justify-between gap-2">
                      <Label>Additional Reference Images</Label>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => handleAddCharacterAdditionalImageClick(index)}
                        disabled={uploadingCharacterAdditionalIndex?.characterIndex === index}
                        className="bg-transparent"
                      >
                        <Plus className="mr-2 h-4 w-4" />
                        Add Image
                      </Button>
                    </div>
                    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                      {(character.images || []).map((image, imageIndex) => (
                        <div
                          key={`wizard-character-image-${index}-${imageIndex}`}
                          className="space-y-2 rounded-lg border border-border bg-muted/20 p-3"
                        >
                          <div className="relative aspect-square overflow-hidden rounded-md border border-border bg-muted">
                            {characterAdditionalPreviewImages[index]?.[imageIndex] ? (
                              // eslint-disable-next-line @next/next/no-img-element
                              <img
                                src={characterAdditionalPreviewImages[index][imageIndex]}
                                alt={`${character.name || "Character"} ${imageIndex + 1}`}
                                className="h-full w-full object-cover"
                              />
                            ) : image && formData.username ? (
                              <OptimizedImage
                                type="character"
                                filename={image}
                                username={formData.username}
                                alt={`${character.name || "Character"} ${imageIndex + 1}`}
                                fill
                                objectFit="cover"
                              />
                            ) : (
                              <div className="flex h-full w-full items-center justify-center">
                                <Camera className="h-5 w-5 text-muted-foreground" />
                              </div>
                            )}
                          </div>
                          <div className="flex gap-2">
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              onClick={() => handleCharacterAdditionalImageClick(index, imageIndex)}
                              disabled={
                                uploadingCharacterAdditionalIndex?.characterIndex === index &&
                                uploadingCharacterAdditionalIndex?.imageIndex === imageIndex
                              }
                              className="flex-1 bg-transparent"
                            >
                              Replace
                            </Button>
                            <Button
                              type="button"
                              variant="ghost"
                              size="sm"
                              onClick={() => removeCharacterAdditionalImage(index, imageIndex)}
                              className="text-destructive hover:text-destructive"
                            >
                              <Trash className="h-4 w-4" />
                            </Button>
                          </div>
                          <input
                            ref={(el) => {
                              characterAdditionalFileInputRefs.current[`${index}-${imageIndex}`] =
                                el;
                            }}
                            type="file"
                            accept="image/*"
                            onChange={(e) =>
                              handleCharacterAdditionalImageChange(e, index, imageIndex)
                            }
                            className="hidden"
                          />
                        </div>
                      ))}
                    </div>
                    <input
                      ref={(el) => {
                        characterAddImageInputRefs.current[index] = el;
                      }}
                      type="file"
                      accept="image/*"
                      multiple
                      onChange={(e) => handleAddCharacterAdditionalImageChange(e, index)}
                      className="hidden"
                    />
                  </div>

                  <div className="flex justify-end border-t border-border pt-4">
                    {confirmingCharacterDelete === index ? (
                      <div className="space-y-3 text-right">
                        <p className="text-sm text-muted-foreground">
                          Delete this character and its references?
                        </p>
                        <div className="flex justify-end gap-2">
                          <Button
                            type="button"
                            variant="destructive"
                            size="sm"
                            onClick={() => {
                              removeCharacter(index);
                              setEditingCharacterIndex(null);
                              setConfirmingCharacterDelete(null);
                            }}
                          >
                            Delete Character
                          </Button>
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            onClick={() => setConfirmingCharacterDelete(null)}
                            className="bg-transparent"
                          >
                            Cancel
                          </Button>
                        </div>
                      </div>
                    ) : (
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={() => setConfirmingCharacterDelete(index)}
                        className="text-destructive hover:bg-destructive/10 hover:text-destructive"
                      >
                        <Trash className="mr-2 h-4 w-4" />
                        Delete Character
                      </Button>
                    )}
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        );
      })}

      <ExtractConfirmDialog
        open={showExtractCharactersDialog}
        onOpenChange={setShowExtractCharactersDialog}
        title="Replace All Characters?"
        description={`This will replace all ${formData.characters?.length || 0} existing character${(formData.characters?.length || 0) !== 1 ? "s" : ""} with characters extracted from the screenplay. This action cannot be undone.`}
        confirmLabel="Replace All Characters"
        isLoading={isExtractingCharacters}
        onConfirm={performCharacterExtraction}
      />
    </div>
  );

  const assetWizardContent = (
    <div className="space-y-6">
      <div className="space-y-3 rounded-lg border border-border bg-muted/20 p-4">
        <div className="flex items-center gap-2">
          <User className="h-5 w-5 text-primary" />
          <h3 className="text-base font-semibold">Character Reference Assets</h3>
        </div>
        <p className="text-sm text-muted-foreground">
          Review the continuity assets attached to each character before building scene prompts.
        </p>
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {(formData.characters || []).map((character, index) => (
            <div
              key={`asset-character-${index}`}
              className="flex items-center gap-3 rounded-lg border border-border bg-background p-3"
            >
              <div className="relative h-12 w-12 overflow-hidden rounded-md border border-border bg-muted">
                {character.mainImage && formData.username ? (
                  <OptimizedImage
                    type="character"
                    filename={character.mainImage}
                    username={formData.username}
                    alt={character.name || "Character"}
                    fill
                    objectFit="cover"
                  />
                ) : (
                  <div className="flex h-full w-full items-center justify-center">
                    <User className="h-5 w-5 text-muted-foreground" />
                  </div>
                )}
              </div>
              <div className="min-w-0">
                <p className="truncate text-sm font-medium">
                  {character.name || `Character ${index + 1}`}
                </p>
                <p className="text-xs text-muted-foreground">
                  {(character.images?.length || 0) + (character.mainImage ? 1 : 0)} references
                </p>
              </div>
            </div>
          ))}
          {(formData.characters || []).length === 0 && (
            <div className="rounded-lg border border-dashed border-border bg-background p-4 text-sm text-muted-foreground">
              Add characters in the previous step to attach reference assets here.
            </div>
          )}
        </div>
      </div>

      <div ref={locationsSectionRef} className="space-y-4">
        <div className="flex flex-wrap items-center gap-2">
          <Button type="button" variant="outline" onClick={addLocation} className="bg-transparent">
            <Plus className="mr-2 h-4 w-4" />
            Add Location
          </Button>
          {formData.screenplayText?.trim() && (
            <Button
              type="button"
              variant="outline"
              onClick={handleExtractLocations}
              disabled={isExtractingLocations}
              className="bg-transparent"
            >
              {isExtractingLocations ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Extracting...
                </>
              ) : (
                <>
                  <Film className="mr-2 h-4 w-4" />
                  Extract from Screenplay
                </>
              )}
            </Button>
          )}
        </div>

        {(formData.setting?.locations || []).length === 0 && (
          <div className="rounded-lg border border-dashed border-border bg-muted/20 p-6 text-sm text-muted-foreground">
            Add locations and reference imagery for the spaces that define the film's visual world.
          </div>
        )}

        {(formData.setting?.locations || []).map((location, index) => {
          const isEditingLocation = editingLocationIndex === index;

          return (
            <Card key={`wizard-location-${index}`} className="border-border bg-background">
              <CardContent className="space-y-4 p-4">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="flex min-w-0 items-center gap-3">
                    <div className="relative h-16 w-16 overflow-hidden rounded-lg border border-border bg-muted">
                      {locationPreviewImages[index] ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={locationPreviewImages[index]}
                          alt={location.name || "Location"}
                          className="h-full w-full object-cover"
                        />
                      ) : location.image && formData.username ? (
                        <OptimizedImage
                          type="location"
                          filename={location.image}
                          username={formData.username}
                          alt={location.name || "Location"}
                          fill
                          objectFit="cover"
                        />
                      ) : (
                        <div className="flex h-full w-full items-center justify-center">
                          <Camera className="h-6 w-6 text-muted-foreground" />
                        </div>
                      )}
                    </div>
                    <div className="min-w-0">
                      <p className="truncate font-medium">{location.name || `Location ${index + 1}`}</p>
                      <p className="truncate text-sm text-muted-foreground">
                        {location.storyPurpose || "No story purpose yet"}
                      </p>
                    </div>
                  </div>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() =>
                      setEditingLocationIndex((current) => (current === index ? null : index))
                    }
                    className="bg-transparent"
                  >
                    {isEditingLocation ? "Done" : "Edit"}
                  </Button>
                </div>

                {isEditingLocation && (
                  <div className="space-y-4 border-t border-border pt-4">
                    <div className="grid gap-4 md:grid-cols-2">
                      <div className="space-y-2">
                        <Label htmlFor={`wizard-location-name-${index}`}>Name</Label>
                        <Input
                          id={`wizard-location-name-${index}`}
                          value={location.name}
                          onChange={(e) => updateLocation(index, "name", e.target.value)}
                          placeholder="Location name"
                          className="bg-background"
                        />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor={`wizard-location-purpose-${index}`}>Story Purpose</Label>
                        <Input
                          id={`wizard-location-purpose-${index}`}
                          value={location.storyPurpose || ""}
                          onChange={(e) => updateLocation(index, "storyPurpose", e.target.value)}
                          placeholder="Why this location matters"
                          className="bg-background"
                        />
                      </div>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor={`wizard-location-description-${index}`}>Description</Label>
                      <Textarea
                        id={`wizard-location-description-${index}`}
                        value={location.description}
                        onChange={(e) => updateLocation(index, "description", e.target.value)}
                        placeholder="Describe the space..."
                        rows={3}
                        className="bg-background"
                      />
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor={`wizard-location-visual-${index}`}>Visual Prompt Notes</Label>
                      <Textarea
                        id={`wizard-location-visual-${index}`}
                        value={location.visualPrompt || ""}
                        onChange={(e) => updateLocation(index, "visualPrompt", e.target.value)}
                        placeholder="Notes for prompt consistency..."
                        rows={3}
                        className="bg-background"
                      />
                    </div>

                    <div className="space-y-2">
                      <Label>Main Image</Label>
                      <div className="flex flex-wrap items-center gap-3">
                        <Button
                          type="button"
                          variant="outline"
                          onClick={() => handleLocationMainImageClick(index)}
                          disabled={uploadingLocationIndex === index}
                          className="bg-transparent"
                        >
                          <Upload className="mr-2 h-4 w-4" />
                          {uploadingLocationIndex === index
                            ? "Uploading..."
                            : location.image
                              ? "Change Main Image"
                              : "Upload Main Image"}
                        </Button>
                        <span className="text-sm text-muted-foreground">
                          {location.image ? "Reference image attached" : "No main image yet"}
                        </span>
                      </div>
                      <input
                        ref={(el) => {
                          locationFileInputRefs.current[index] = el;
                        }}
                        type="file"
                        accept="image/*"
                        onChange={(e) => handleLocationMainImageChange(e, index)}
                        className="hidden"
                        disabled={uploadingLocationIndex === index}
                      />
                    </div>

                    <div className="space-y-2">
                      <div className="flex items-center justify-between gap-2">
                        <Label>Additional Reference Images</Label>
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          onClick={() => handleAddLocationAdditionalImageClick(index)}
                          disabled={uploadingLocationAdditionalIndex?.locationIndex === index}
                          className="bg-transparent"
                        >
                          <Plus className="mr-2 h-4 w-4" />
                          Add Image
                        </Button>
                      </div>
                      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                        {(location.images || []).map((image, imageIndex) => (
                          <div
                            key={`wizard-location-image-${index}-${imageIndex}`}
                            className="space-y-2 rounded-lg border border-border bg-muted/20 p-3"
                          >
                            <div className="relative aspect-square overflow-hidden rounded-md border border-border bg-muted">
                              {locationAdditionalPreviewImages[index]?.[imageIndex] ? (
                                // eslint-disable-next-line @next/next/no-img-element
                                <img
                                  src={locationAdditionalPreviewImages[index][imageIndex]}
                                  alt={`${location.name || "Location"} ${imageIndex + 1}`}
                                  className="h-full w-full object-cover"
                                />
                              ) : image && formData.username ? (
                                <OptimizedImage
                                  type="location"
                                  filename={image}
                                  username={formData.username}
                                  alt={`${location.name || "Location"} ${imageIndex + 1}`}
                                  fill
                                  objectFit="cover"
                                />
                              ) : (
                                <div className="flex h-full w-full items-center justify-center">
                                  <Camera className="h-5 w-5 text-muted-foreground" />
                                </div>
                              )}
                            </div>
                            <div className="flex gap-2">
                              <Button
                                type="button"
                                variant="outline"
                                size="sm"
                                onClick={() => handleLocationAdditionalImageClick(index, imageIndex)}
                                disabled={
                                  uploadingLocationAdditionalIndex?.locationIndex === index &&
                                  uploadingLocationAdditionalIndex?.imageIndex === imageIndex
                                }
                                className="flex-1 bg-transparent"
                              >
                                Replace
                              </Button>
                              <Button
                                type="button"
                                variant="ghost"
                                size="sm"
                                onClick={() => removeLocationAdditionalImage(index, imageIndex)}
                                className="text-destructive hover:text-destructive"
                              >
                                <Trash className="h-4 w-4" />
                              </Button>
                            </div>
                            <input
                              ref={(el) => {
                                locationAdditionalFileInputRefs.current[`${index}-${imageIndex}`] =
                                  el;
                              }}
                              type="file"
                              accept="image/*"
                              onChange={(e) => handleLocationAdditionalImageChange(e, index, imageIndex)}
                              className="hidden"
                            />
                          </div>
                        ))}
                      </div>
                      <input
                        ref={(el) => {
                          locationAddImageInputRefs.current[index] = el;
                        }}
                        type="file"
                        accept="image/*"
                        onChange={(e) => handleAddLocationAdditionalImageChange(e, index)}
                        className="hidden"
                      />
                    </div>

                    <div className="flex justify-end border-t border-border pt-4">
                      {confirmingLocationDelete === index ? (
                        <div className="space-y-3 text-right">
                          <p className="text-sm text-muted-foreground">
                            Delete this location and its references?
                          </p>
                          <div className="flex justify-end gap-2">
                            <Button
                              type="button"
                              variant="destructive"
                              size="sm"
                              onClick={() => {
                                removeLocation(index);
                                setEditingLocationIndex(null);
                                setConfirmingLocationDelete(null);
                              }}
                            >
                              Delete Location
                            </Button>
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              onClick={() => setConfirmingLocationDelete(null)}
                              className="bg-transparent"
                            >
                              Cancel
                            </Button>
                          </div>
                        </div>
                      ) : (
                        <Button
                          type="button"
                          variant="ghost"
                          size="sm"
                          onClick={() => setConfirmingLocationDelete(index)}
                          className="text-destructive hover:bg-destructive/10 hover:text-destructive"
                        >
                          <Trash className="mr-2 h-4 w-4" />
                          Delete Location
                        </Button>
                      )}
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          );
        })}

        <ExtractConfirmDialog
          open={showExtractLocationsDialog}
          onOpenChange={setShowExtractLocationsDialog}
          title="Replace All Locations?"
          description={`This will replace all ${formData.setting?.locations?.length || 0} existing location${(formData.setting?.locations?.length || 0) !== 1 ? "s" : ""} with locations extracted from the screenplay. This action cannot be undone.`}
          confirmLabel="Replace All Locations"
          isLoading={isExtractingLocations}
          onConfirm={performLocationExtraction}
        />
      </div>
    </div>
  );

  const shotPromptWizardContent = (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        Build the prompt-ready scene package here. Each scene can carry screenplay context,
        characters, locations, and shot breakdowns.
      </p>
      <SceneList
        projectId={effectiveProjectId}
        scenes={formData.scenes || []}
        characters={formData.characters || []}
        locations={formData.setting?.locations || []}
        screenplayText={formData.screenplayText}
        onScenesChange={(scenes) => setFormData({ ...formData, scenes })}
      />
    </div>
  );

  const showLegacyAdvancedDetails = false;

  return (
    <form onSubmit={handleSubmit}>
      <div>
        <div>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 pb-4">
              <Film className="h-5 w-5 text-primary" />
              {isEditing ? "Edit Project" : "Create New Project"}
            </div>
            {isEditing && (
              <div className="flex items-center gap-2 text-sm">
                {autoSaveStatus === "saving" && (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
                    <span className="text-muted-foreground">Saving...</span>
                  </>
                )}
                {autoSaveStatus === "saved" && (
                  <>
                    <Cloud className="h-4 w-4 text-green-500" />
                    <span className="text-green-500">Saved</span>
                  </>
                )}
                {autoSaveStatus === "error" && (
                  <>
                    <CloudOff className="h-4 w-4 text-destructive" />
                    <span className="text-destructive">Save failed</span>
                  </>
                )}
              </div>
            )}
          </div>
        </div>
        <Suspense fallback={<div className="h-px" />}>
          <ProjectDevelopmentPhases
            key={wizardResetKey}
            data={formData}
            projectId={effectiveProjectId}
            onChange={setFormData}
            onSyncScenesFromBreakdown={handleSyncScenesFromBreakdown}
            onCreateProject={!isEditing ? createProjectFromWizard : undefined}
            onStartOver={!isEditing ? startOverWizard : undefined}
            stepContent={{
              characters: characterWizardContent,
              assets: assetWizardContent,
              "shot-prompts": shotPromptWizardContent,
            }}
          />
        </Suspense>
        {showLegacyAdvancedDetails && (
        <details className="mt-6 rounded-xl border border-border bg-muted/20" open={!isEditing}>
          <summary className="cursor-pointer list-none px-4 py-3 text-sm font-medium text-muted-foreground">
            Advanced project details
          </summary>
          <div className={cn("px-4 pb-4", useGridLayout ? "grid grid-cols-3 gap-6" : "space-y-6")}>
          {/* Left Column - Project Info, Screenplay, Links, Tools */}
          {useGridLayout && (
            <div className="space-y-6 pr-8 border-r border-border">
              {/* Project Info Section */}
              {!isEditingProjectInfo ? (
                /* Compact Project Info View */
                <div className="flex flex-col gap-4">
                  {/* Thumbnail */}
                  <div className="w-full">
                    <div className="relative aspect-video rounded-lg overflow-hidden border border-border bg-muted">
                      {formData.thumbnail && formData.username ? (
                        <OptimizedImage
                          type="thumbnail"
                          filename={formData.thumbnail}
                          username={formData.username}
                          alt="Project image"
                          fill
                          objectFit="cover"
                          sizes="256px"
                        />
                      ) : (
                        <div className="absolute inset-0 flex items-center justify-center">
                          <Film className="h-8 w-8 text-muted-foreground" />
                        </div>
                      )}
                    </div>
                  </div>
                  {/* Info */}
                  <div className="w-full space-y-2">
                    <div className="flex items-start justify-between gap-4">
                      <div className="min-w-0">
                        <h3 className="text-2xl font-semibold truncate">
                          {formData.title || "Untitled Project"}
                        </h3>
                        {formData.logline && (
                          <p className="text-muted-foreground line-clamp-2">{formData.logline}</p>
                        )}
                      </div>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => setIsEditingProjectInfo(true)}
                        className="shrink-0 bg-transparent"
                      >
                        <Pencil className="h-4 w-4 mr-2" />
                        Edit
                      </Button>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {formData.genre && (
                        <span className="px-2 py-1 text-xs font-medium rounded-full bg-primary/10 text-primary">
                          {formData.genre}
                        </span>
                      )}
                      {(formData.filmLength || formData.duration) && (
                        <span className="px-2 py-1 text-xs font-medium rounded-full bg-muted text-muted-foreground">
                          {formData.filmLength || formData.duration}
                        </span>
                      )}
                    </div>
                    {formData.filmLink && (
                      <p className="text-xs text-muted-foreground truncate">
                        <LinkIcon className="h-3 w-3 inline mr-1" />
                        {formData.filmLink}
                      </p>
                    )}
                  </div>
                </div>
              ) : (
                /* Expanded Project Info Edit Form */
                <div className="space-y-6 p-4 rounded-lg border border-border bg-muted/10">
                  <div className="flex items-center justify-between">
                    <h3 className="font-medium">Project Info</h3>
                    {isEditing && (
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => setIsEditingProjectInfo(false)}
                        className="bg-transparent"
                      >
                        Done
                      </Button>
                    )}
                  </div>

                  <div className="space-y-6">
                    <div className="space-y-2">
                      <Label htmlFor="title">Project Title *</Label>
                      <Input
                        id="title"
                        placeholder="Enter your project title"
                        value={formData.title}
                        onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                        className="bg-background"
                        required
                      />
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="logline">Logline</Label>
                      <Input
                        id="logline"
                        placeholder="A one-sentence summary of your film's story"
                        value={formData.logline || ""}
                        onChange={(e) => setFormData({ ...formData, logline: e.target.value })}
                        className="bg-background"
                      />
                      <p className="text-xs text-muted-foreground">
                        A brief, compelling description of your film in 1-2 sentences
                      </p>
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                      <div className="space-y-2">
                        <Label htmlFor="genre">Genre</Label>
                        <Select
                          value={formData.genre}
                          onValueChange={(value) => setFormData({ ...formData, genre: value })}
                        >
                          <SelectTrigger id={genreSelectId} className="w-full bg-background">
                            <SelectValue placeholder="Select genre..." />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="Action">Action</SelectItem>
                            <SelectItem value="Animation">Animation</SelectItem>
                            <SelectItem value="Comedy">Comedy</SelectItem>
                            <SelectItem value="Documentary">Documentary</SelectItem>
                            <SelectItem value="Drama">Drama</SelectItem>
                            <SelectItem value="Fantasy">Fantasy</SelectItem>
                            <SelectItem value="Horror">Horror</SelectItem>
                            <SelectItem value="Romance">Romance</SelectItem>
                            <SelectItem value="Sci-Fi">Sci-Fi</SelectItem>
                            <SelectItem value="Thriller">Thriller</SelectItem>
                            <SelectItem value="Experimental">Experimental</SelectItem>
                            <SelectItem value="Other">Other</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>

                      <div className="space-y-2">
                        <Label htmlFor="duration">Film Length</Label>
                        <Select
                          value={formData.filmLength || formData.duration}
                          onValueChange={(value) =>
                            setFormData({ ...formData, filmLength: value as FilmLengthOption, duration: value })
                          }
                        >
                          <SelectTrigger id={durationSelectId} className="w-full bg-background">
                            <SelectValue placeholder="Select film length..." />
                          </SelectTrigger>
                          <SelectContent>
                            {FILM_LENGTH_OPTIONS.map((option) => (
                              <SelectItem key={option} value={option}>
                                {option}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="filmLink">Film Link</Label>
                      <Input
                        id="filmLink"
                        placeholder="YouTube or Vimeo URL (e.g., https://youtube.com/watch?v=...)"
                        value={formData.filmLink || ""}
                        onChange={(e) => setFormData({ ...formData, filmLink: e.target.value })}
                        className="bg-background"
                      />
                      <p className="text-xs text-muted-foreground">
                        Add a link to your film on YouTube or Vimeo
                      </p>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="thumbnail">Project Image</Label>
                      <div className="space-y-4">
                        {/* Thumbnail Preview */}
                        <div className="relative w-full aspect-video rounded-lg overflow-hidden border border-border bg-muted/30">
                          {previewImage ? (
                            <ImagePreview
                              src={previewImage}
                              isUploading={isUploadingImage}
                              isUploaded={!!formData.thumbnail}
                              alt="Project image"
                              aspectRatio="video"
                              objectFit="cover"
                            />
                          ) : formData.thumbnail && formData.username ? (
                            <OptimizedImage
                              type="thumbnail"
                              filename={formData.thumbnail}
                              username={formData.username}
                              alt="Project image"
                              fill
                              objectFit="cover"
                              sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
                            />
                          ) : null}
                          {/* Upload overlay */}
                          <button
                            type="button"
                            onClick={handleImageClick}
                            disabled={isUploadingImage}
                            className="group absolute inset-0 flex items-center justify-center bg-black/60 opacity-50 hover:opacity-100 transition-all duration-300 cursor-pointer disabled:cursor-not-allowed"
                            aria-label="Upload project image"
                          >
                            {isUploadingImage ? (
                              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                            ) : (
                              <div className="flex flex-col items-center gap-2">
                                <Camera className="h-8 w-8 text-white" />
                                <span className="text-sm text-white font-medium">
                                  {formData.thumbnail ? "Change Image" : "Upload Image"}
                                </span>
                              </div>
                            )}
                          </button>
                        </div>

                        {/* Upload Button */}
                        <div className="flex items-center gap-4">
                          <Button
                            type="button"
                            variant="outline"
                            onClick={handleImageClick}
                            disabled={isUploadingImage}
                            className="bg-transparent"
                          >
                            <Upload className="h-4 w-4 mr-2" />
                            {isUploadingImage
                              ? "Uploading..."
                              : formData.thumbnail
                                ? "Change Image"
                                : "Upload Image"}
                          </Button>
                          <span className="text-sm text-muted-foreground">
                            {formData.thumbnail ? "Image uploaded" : "No image selected"}
                          </span>
                        </div>

                        {/* Hidden file input */}
                        <input
                          ref={fileInputRef}
                          type="file"
                          accept="image/*"
                          onChange={handleImageChange}
                          className="hidden"
                          disabled={isUploadingImage}
                        />
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* Screenplay Section */}
              <div className="space-y-4 pt-4 border-t border-border" suppressHydrationWarning>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <File className="h-5 w-5 text-primary" />
                    <h3 className="text-lg font-semibold">Screenplay / Script</h3>
                  </div>
                  {isEditing && projectId && (formData.screenplayText || formData.screenplay) && (
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => router.push(`/dashboard/projects/${projectId}/screenplay`)}
                      className="bg-transparent"
                    >
                      <Pencil className="h-4 w-4 mr-2" />
                      Edit Screenplay
                    </Button>
                  )}
                </div>
                {!formData.screenplayText && (
                  <p className="text-sm text-muted-foreground">
                    Upload a PDF screenplay or use the editor to write your screenplay. The text
                    will be automatically extracted from PDFs.
                  </p>
                )}

                {/* Screenplay Status - One Line */}
                {formData.screenplayText ? (
                  <div className="flex items-center justify-between gap-3 px-3 py-2 bg-muted/30 rounded-lg border border-border">
                    <span className="text-sm text-muted-foreground">
                      {formData.screenplayText.split(/\s+/).filter((w) => w.length > 0).length}{" "}
                      words • {formData.screenplayText.match(/^(INT\.|EXT\.)/gm)?.length || 0}{" "}
                      scenes
                    </span>
                    <div className="flex items-center gap-3">
                      {showRemoveScreenplayConfirm ? (
                        <>
                          <span className="text-xs text-muted-foreground">Replace screenplay?</span>
                          <button
                            onClick={() => {
                              setShowRemoveScreenplayConfirm(false);
                              projectFileInputRef.current?.click();
                            }}
                            type="button"
                            className="text-primary hover:text-primary/80 font-medium text-xs"
                          >
                            Yes
                          </button>
                          <button
                            onClick={() => setShowRemoveScreenplayConfirm(false)}
                            type="button"
                            className="text-muted-foreground hover:text-foreground text-xs"
                          >
                            Cancel
                          </button>
                        </>
                      ) : (
                        <button
                          onClick={() => setShowRemoveScreenplayConfirm(true)}
                          type="button"
                          className="text-xs text-muted-foreground hover:text-foreground"
                        >
                          Replace
                        </button>
                      )}
                    </div>
                  </div>
                ) : (
                  <Button
                    type="button"
                    variant="outline"
                    onClick={handleProjectFileClick}
                    disabled={isUploadingFile}
                    className="bg-transparent"
                  >
                    <Upload className="h-4 w-4 mr-2" />
                    {isUploadingFile ? "Uploading..." : "Upload PDF"}
                  </Button>
                )}

                {/* Hidden file input - Always rendered so ref is always available */}
                <input
                  ref={projectFileInputRef}
                  type="file"
                  onChange={handleProjectFileChange}
                  className="hidden"
                  disabled={isUploadingFile}
                  accept=".pdf,application/pdf"
                />
              </div>

              {/* Project Links Section */}
              <div className="space-y-4 pt-4 border-t border-border">
                <div className="flex items-center gap-2">
                  <LinkIcon className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Project Links</h3>
                </div>
                <p className="text-sm text-muted-foreground">
                  Add links to your project (YouTube, Vimeo, Instagram, etc.)
                </p>

                <div className="space-y-3">
                  {formData.links.links.map((link, index) => (
                    <div
                      key={`${link.label}-${link.url}-${index}`}
                      className="flex items-center gap-2 p-3 bg-muted/30 rounded-md"
                    >
                      <div className="flex-1">
                        <p className="text-sm font-medium">{link.label}</p>
                        <p className="text-xs text-muted-foreground truncate">{link.url}</p>
                      </div>
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={() => removeLink(index)}
                        className="text-destructive hover:text-destructive"
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}

                  <div className="flex gap-2">
                    <Input
                      placeholder="Enter URL (e.g., https://youtube.com/watch?v=...)"
                      value={newLinkUrl}
                      onChange={(e) => setNewLinkUrl(e.target.value)}
                      onKeyPress={(e) => {
                        if (e.key === "Enter") {
                          e.preventDefault();
                          addLink();
                        }
                      }}
                      className="bg-background"
                    />
                    <Button
                      type="button"
                      variant="outline"
                      onClick={addLink}
                      className="bg-transparent"
                    >
                      <Plus className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </div>

              {/* Tools Section */}
              <div className="space-y-4 pt-4 border-t border-border">
                <div className="flex items-center gap-2">
                  <Wrench className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Tools</h3>
                </div>
                <p className="text-sm text-muted-foreground">
                  Add the tools you used, organized by category
                </p>

                {/* Add tools by category */}
                <div className="space-y-4">
                  {(["video", "image", "sound", "other"] as ToolCategory[]).map((category) => {
                    const toolsInCategory = getToolsByCategory(category);
                    return (
                      <div key={category} className="space-y-2">
                        <Label htmlFor={`tool-${category}`}>
                          {getCategoryLabel(category)}
                        </Label>
                        {/* Display added tools for this category */}
                        {toolsInCategory.length > 0 && (
                          <div className="flex flex-wrap gap-2">
                            {toolsInCategory.map((tool, _index) => {
                              const globalIndex = formData.tools.indexOf(tool);
                              return (
                                <div
                                  key={`${category}-${tool.name}-${globalIndex}`}
                                  className="flex items-center gap-2 px-3 py-1.5 bg-primary/10 text-primary rounded-full text-sm"
                                >
                                  <span>{tool.name}</span>
                                  <button
                                    type="button"
                                    onClick={() => removeTool(globalIndex)}
                                    className="hover:text-primary/70 transition-colors"
                                  >
                                    <X className="h-3 w-3" />
                                  </button>
                                </div>
                              );
                            })}
                          </div>
                        )}
                        <div className="space-y-2">
                          <Select
                            value={selectedTool[category]}
                            onValueChange={(value) => {
                              setSelectedTool({ ...selectedTool, [category]: value });
                              if (value !== "Other") {
                                // Auto-add tool when selected (not "Other")
                                addTool(category, value);
                              } else {
                                setCustomToolInput({ ...customToolInput, [category]: "" });
                              }
                            }}
                            key={`tool-select-${category}`}
                          >
                            <SelectTrigger id={toolSelectIds[category]} className="w-full bg-background">
                              <SelectValue
                                placeholder={`Add ${getCategoryLabel(category).toLowerCase()} tool...`}
                              />
                            </SelectTrigger>
                            <SelectContent>
                              {COMMON_TOOLS[category].map((tool) => (
                                <SelectItem key={tool} value={tool}>
                                  {tool}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                          {selectedTool[category] === "Other" && (
                            <div className="flex gap-2">
                              <Input
                                placeholder="Enter custom tool"
                                value={customToolInput[category]}
                                onChange={(e) =>
                                  setCustomToolInput({
                                    ...customToolInput,
                                    [category]: e.target.value,
                                  })
                                }
                                onKeyPress={(e) => {
                                  if (e.key === "Enter") {
                                    e.preventDefault();
                                    addTool(category);
                                  }
                                }}
                                className="flex-1 bg-background"
                              />
                              <Button
                                type="button"
                                variant="outline"
                                onClick={() => addTool(category)}
                                disabled={!customToolInput[category].trim()}
                                className="bg-transparent"
                              >
                                <Plus className="h-4 w-4" />
                              </Button>
                            </div>
                          )}
                        </div>
                        {category === "video" && !hasVideoTool && (
                          <p className="text-xs text-muted-foreground pb-2">
                            Optional. Add legacy video tools only if they are part of your broader workflow.
                          </p>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          )}

          {/* Right Column - Characters, Locations, Scenes (col-span-2) */}
          {useGridLayout && (
            <div className="col-span-2 space-y-6">
              {/* Characters Section */}
              <div ref={charactersSectionRef} className="space-y-3">
                <div className="flex items-center gap-2">
                  <User className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Characters</h3>
                </div>

                <div className="space-y-2">
                  {/* Character List - Compact One-Liner View */}
                  {(formData.characters || []).length > 0 && editingCharacterIndex === null && (
                    <div className="space-y-1.5">
                      {(() => {
                        const characters = formData.characters || [];
                        const shouldShowAll = characters.length <= 10 || showAllCharacters;
                        const charactersToShow = shouldShowAll
                          ? characters
                          : characters.slice(0, 5);

                        return (
                          <>
                            {charactersToShow.map((character, index) => (
                              <div key={`character-compact-${index}`} className="relative">
                                <button
                                  type="button"
                                  className="flex items-center gap-2 p-1.5 bg-muted/30 rounded-lg border border-border group hover:bg-muted/50 cursor-pointer transition-colors w-full text-left"
                                  onClick={() => setEditingCharacterIndex(index)}
                                >
                                  {/* Edit indicator */}
                                  <div className="pt-0.5 shrink-0">
                                    <Edit className="h-4 w-4 text-primary opacity-0 group-hover:opacity-100 transition-all duration-500" />
                                  </div>

                                  {/* Character Image - Super Small - Clickable for upload */}
                                  <div
                                    className="relative w-8 h-8 rounded overflow-hidden border border-border shrink-0 group/img cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all"
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      handleCharacterMainImageClick(index);
                                    }}
                                    title={
                                      character.mainImage
                                        ? "Click to replace image"
                                        : "Click to add image"
                                    }
                                  >
                                    {uploadingCharacterIndex === index ? (
                                      <div className="w-full h-full flex items-center justify-center bg-muted">
                                        <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-primary" />
                                      </div>
                                    ) : character.mainImage && formData.username ? (
                                      <>
                                        <OptimizedImage
                                          type="character"
                                          filename={character.mainImage}
                                          username={formData.username}
                                          alt={character.name || "Character"}
                                          fill
                                          objectFit="cover"
                                        />
                                        <div className="absolute inset-0 bg-black/50 opacity-0 group-hover/img:opacity-100 transition-opacity flex items-center justify-center">
                                          <Camera className="h-3 w-3 text-white" />
                                        </div>
                                      </>
                                    ) : (
                                      <div className="w-full h-full flex items-center justify-center bg-muted group-hover/img:bg-primary/10 transition-colors">
                                        <Camera className="h-4 w-4 text-muted-foreground group-hover/img:text-primary transition-colors" />
                                      </div>
                                    )}
                                  </div>

                                  {/* Character Name */}
                                  <span className="font-medium text-sm shrink-0">
                                    {character.name || "Unnamed"}
                                  </span>

                                  {/* Character Appearance - Truncated */}
                                  <span className="text-xs text-muted-foreground truncate flex-1">
                                    {character.appearance || "No appearance description"}
                                  </span>

                                  {/* Additional Images Count */}
                                  {(character.images?.length || 0) > 0 && (
                                    <span className="text-xs text-muted-foreground shrink-0">
                                      +{character.images?.length} img
                                    </span>
                                  )}
                                </button>
                                {/* Hidden file input for compact view upload */}
                                <input
                                  ref={(el) => {
                                    characterFileInputRefs.current[index] = el;
                                  }}
                                  type="file"
                                  accept="image/*"
                                  onChange={(e) =>
                                    handleCharacterMainImageChange(e, index)
                                  }
                                  className="hidden"
                                  disabled={uploadingCharacterIndex === index}
                                />
                              </div>
                            ))}
                          </>
                        );
                      })()}
                    </div>
                  )}

                  {/* Character Edit Form - Expanded View */}
                  {editingCharacterIndex !== null &&
                    formData.characters?.[editingCharacterIndex] && (
                      <Card className="bg-muted/30 border-border">
                        <CardContent className="space-y-4">
                          <div className="flex items-center justify-between">
                            <h4 className="font-medium">Edit Character</h4>
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              onClick={() => {
                                setEditingCharacterIndex(null);
                                setConfirmingCharacterDelete(null);
                              }}
                              className="bg-transparent"
                            >
                              Done
                            </Button>
                          </div>

                          {/* Character Name */}
                          <div className="space-y-2">
                            <Label htmlFor={`character-name-${editingCharacterIndex}`}>Name</Label>
                            <Input
                              id={`character-name-${editingCharacterIndex}`}
                              placeholder="Enter character name"
                              value={formData.characters[editingCharacterIndex].name}
                              onChange={(e) =>
                                updateCharacter(editingCharacterIndex, "name", e.target.value)
                              }
                              className="bg-background"
                            />
                          </div>

                          {/* Character Main Image */}
                          <div className="space-y-2">
                            <Label>Main Image</Label>
                            <div className="relative w-full rounded-lg overflow-hidden border border-border bg-muted/30">
                              {characterPreviewImages[editingCharacterIndex] ? (
                                <div className="relative group">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img
                                    src={characterPreviewImages[editingCharacterIndex]}
                                    alt={
                                      formData.characters[editingCharacterIndex].name || "Character"
                                    }
                                    className="w-full h-auto"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleCharacterMainImageClick(editingCharacterIndex)
                                    }
                                    disabled={uploadingCharacterIndex === editingCharacterIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload character main image"
                                  >
                                    {uploadingCharacterIndex === editingCharacterIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              ) : formData.characters[editingCharacterIndex].mainImage &&
                                formData.username ? (
                                <div className="relative group">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img
                                    src={getImageUrl({
                                      type: "character",
                                      filename:
                                        formData.characters[editingCharacterIndex].mainImage!,
                                      username: formData.username,
                                    })}
                                    alt={
                                      formData.characters[editingCharacterIndex].name || "Character"
                                    }
                                    className="w-full h-auto"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleCharacterMainImageClick(editingCharacterIndex)
                                    }
                                    disabled={uploadingCharacterIndex === editingCharacterIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload character main image"
                                  >
                                    {uploadingCharacterIndex === editingCharacterIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              ) : (
                                <div className="w-full min-h-[200px] flex items-center justify-center relative group">
                                  <User className="h-12 w-12 text-muted-foreground" />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleCharacterMainImageClick(editingCharacterIndex)
                                    }
                                    disabled={uploadingCharacterIndex === editingCharacterIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload character main image"
                                  >
                                    {uploadingCharacterIndex === editingCharacterIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              )}
                            </div>
                            <input
                              ref={(el) => {
                                characterFileInputRefs.current[editingCharacterIndex] = el;
                              }}
                              type="file"
                              accept="image/*"
                              onChange={(e) =>
                                handleCharacterMainImageChange(e, editingCharacterIndex)
                              }
                              className="hidden"
                              disabled={uploadingCharacterIndex === editingCharacterIndex}
                            />
                          </div>

                          {/* Additional Character Images */}
                          <div className="space-y-2">
                            <Label>Additional Images (Different Angles/Attire)</Label>
                            <div className="columns-2 md:columns-3 gap-4">
                              {(formData.characters[editingCharacterIndex].images || []).map(
                                (image, imageIndex) => (
                                  <div
                                    key={`${editingCharacterIndex}-${imageIndex}`}
                                    className="relative w-full mb-4 break-inside-avoid rounded-lg overflow-hidden border border-border bg-muted/30"
                                  >
                                    {characterAdditionalPreviewImages[editingCharacterIndex]?.[
                                      imageIndex
                                    ] ? (
                                      <div className="relative group">
                                        {/* eslint-disable-next-line @next/next/no-img-element */}
                                        <img
                                          src={
                                            characterAdditionalPreviewImages[editingCharacterIndex][
                                              imageIndex
                                            ]
                                          }
                                          alt={`${formData.characters?.[editingCharacterIndex]?.name || "Character"} - ${imageIndex + 1}`}
                                          className="w-full h-auto"
                                        />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleCharacterAdditionalImageClick(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingCharacterAdditionalIndex?.characterIndex ===
                                              editingCharacterIndex &&
                                            uploadingCharacterAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional character image ${imageIndex + 1}`}
                                        >
                                          {uploadingCharacterAdditionalIndex?.characterIndex ===
                                            editingCharacterIndex &&
                                          uploadingCharacterAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                        <button
                                          type="button"
                                          onClick={() =>
                                            removeCharacterAdditionalImage(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          className="absolute top-1 right-1 bg-destructive text-destructive-foreground rounded-full p-1 opacity-75 hover:opacity-100 transition-opacity z-10"
                                          aria-label={`Remove image ${imageIndex + 1}`}
                                        >
                                          <X className="h-3 w-3" />
                                        </button>
                                      </div>
                                    ) : image && formData.username ? (
                                      <div className="relative group">
                                        {/* eslint-disable-next-line @next/next/no-img-element */}
                                        <img
                                          src={getImageUrl({
                                            type: "character",
                                            filename: image,
                                            username: formData.username,
                                          })}
                                          alt={`${formData.characters?.[editingCharacterIndex]?.name || "Character"} - ${imageIndex + 1}`}
                                          className="w-full h-auto"
                                        />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleCharacterAdditionalImageClick(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingCharacterAdditionalIndex?.characterIndex ===
                                              editingCharacterIndex &&
                                            uploadingCharacterAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional character image ${imageIndex + 1}`}
                                        >
                                          {uploadingCharacterAdditionalIndex?.characterIndex ===
                                            editingCharacterIndex &&
                                          uploadingCharacterAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                        <button
                                          type="button"
                                          onClick={() =>
                                            removeCharacterAdditionalImage(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          className="absolute top-1 right-1 bg-destructive text-destructive-foreground rounded-full p-1 opacity-75 hover:opacity-100 transition-opacity z-10"
                                          aria-label={`Remove image ${imageIndex + 1}`}
                                        >
                                          <X className="h-3 w-3" />
                                        </button>
                                      </div>
                                    ) : (
                                      <div className="w-full min-h-[150px] flex items-center justify-center relative group">
                                        <Camera className="h-8 w-8 text-muted-foreground" />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleCharacterAdditionalImageClick(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingCharacterAdditionalIndex?.characterIndex ===
                                              editingCharacterIndex &&
                                            uploadingCharacterAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional character image ${imageIndex + 1}`}
                                        >
                                          {uploadingCharacterAdditionalIndex?.characterIndex ===
                                            editingCharacterIndex &&
                                          uploadingCharacterAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                      </div>
                                    )}
                                    <input
                                      ref={(el) => {
                                        characterAdditionalFileInputRefs.current[
                                          `${editingCharacterIndex}-${imageIndex}`
                                        ] = el;
                                      }}
                                      type="file"
                                      accept="image/*"
                                      onChange={(e) =>
                                        handleCharacterAdditionalImageChange(
                                          e,
                                          editingCharacterIndex,
                                          imageIndex
                                        )
                                      }
                                      className="hidden"
                                      disabled={
                                        uploadingCharacterAdditionalIndex?.characterIndex ===
                                          editingCharacterIndex &&
                                        uploadingCharacterAdditionalIndex?.imageIndex === imageIndex
                                      }
                                    />
                                  </div>
                                )
                              )}
                              <div className="relative w-full mb-4 break-inside-avoid">
                                <button
                                  type="button"
                                  onClick={() =>
                                    handleAddCharacterAdditionalImageClick(editingCharacterIndex)
                                  }
                                  className="relative w-full min-h-[150px] rounded-lg border-2 border-dashed border-border bg-muted/30 hover:bg-muted/50 transition-colors flex items-center justify-center"
                                  aria-label="Add additional character image"
                                >
                                  <Plus className="h-8 w-8 text-muted-foreground" />
                                  <input
                                    ref={(el) => {
                                      characterAddImageInputRefs.current[editingCharacterIndex] =
                                        el;
                                    }}
                                    type="file"
                                    accept="image/*"
                                    multiple
                                    onChange={(e) =>
                                      handleAddCharacterAdditionalImageChange(
                                        e,
                                        editingCharacterIndex
                                      )
                                    }
                                    className="hidden"
                                    disabled={
                                      uploadingCharacterAdditionalIndex?.characterIndex ===
                                      editingCharacterIndex
                                    }
                                  />
                                </button>
                              </div>
                            </div>
                          </div>

                          {/* Character Appearance */}
                          <div className="space-y-2">
                            <Label htmlFor={`character-appearance-${editingCharacterIndex}`}>
                              Appearance
                            </Label>
                            <Textarea
                              id={`character-appearance-${editingCharacterIndex}`}
                              placeholder="Describe this character's appearance..."
                              value={formData.characters[editingCharacterIndex].appearance}
                              onChange={(e) =>
                                updateCharacter(editingCharacterIndex, "appearance", e.target.value)
                              }
                              rows={3}
                              className="bg-background resize-none"
                            />
                          </div>

                          {/* Delete Character Button */}
                          <div className="pt-4 flex justify-end">
                            {confirmingCharacterDelete === editingCharacterIndex ? (
                              <div className="space-y-3 text-right">
                                <p className="text-sm text-muted-foreground">
                                  Are you sure you want to delete this character? This action cannot
                                  be undone.
                                </p>
                                <div className="flex items-center justify-end gap-2">
                                  <Button
                                    type="button"
                                    variant="destructive"
                                    size="sm"
                                    onClick={() => {
                                      removeCharacter(editingCharacterIndex);
                                      setEditingCharacterIndex(null);
                                      setConfirmingCharacterDelete(null);
                                    }}
                                  >
                                    <Trash className="h-4 w-4 mr-2" />
                                    Delete Character
                                  </Button>
                                  <Button
                                    type="button"
                                    variant="outline"
                                    size="sm"
                                    onClick={() => setConfirmingCharacterDelete(null)}
                                    className="bg-transparent"
                                  >
                                    Cancel
                                  </Button>
                                </div>
                              </div>
                            ) : (
                              <Button
                                type="button"
                                variant="ghost"
                                size="sm"
                                onClick={() => setConfirmingCharacterDelete(editingCharacterIndex)}
                                className="text-xs text-destructive hover:text-destructive hover:bg-destructive/10"
                              >
                                <X className="h-2 w-2 mr-2" />
                                Delete Character
                              </Button>
                            )}
                          </div>
                        </CardContent>
                      </Card>
                    )}

                  <div className="flex gap-2 flex-wrap items-center">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={addCharacter}
                      className="bg-transparent"
                    >
                      <Plus className="h-4 w-4 mr-2" />
                      Add Character
                    </Button>
                    {formData.screenplayText?.trim() && (
                      <Button
                        type="button"
                        variant="outline"
                        onClick={handleExtractCharacters}
                        disabled={isExtractingCharacters}
                        className="bg-transparent"
                      >
                        {isExtractingCharacters ? (
                          <>
                            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                            Extracting...
                          </>
                        ) : (
                          <>
                            <Film className="h-4 w-4 mr-2" />
                            Extract from Screenplay
                          </>
                        )}
                      </Button>
                    )}
                    {(formData.characters?.length || 0) > 10 && (
                      <>
                        <div className="flex-1" />
                        <button
                          type="button"
                          onClick={() => {
                            const wasShowingAll = showAllCharacters;
                            setShowAllCharacters(!showAllCharacters);
                            if (wasShowingAll) {
                              setTimeout(() => {
                                charactersSectionRef.current?.scrollIntoView({
                                  behavior: "smooth",
                                  block: "start",
                                });
                              }, 0);
                            }
                          }}
                          className="text-sm text-muted-foreground hover:text-foreground flex items-center gap-1 transition-colors"
                        >
                          <ChevronsDown
                            className={cn(
                              "h-4 w-4 transition-transform duration-300",
                              showAllCharacters ? "rotate-180" : ""
                            )}
                          />
                          {showAllCharacters
                            ? "Show Less"
                            : `Show All (${formData.characters?.length})`}
                        </button>
                      </>
                    )}
                  </div>

                  {/* Extract Characters Confirmation Dialog */}
                  <ExtractConfirmDialog
                    open={showExtractCharactersDialog}
                    onOpenChange={setShowExtractCharactersDialog}
                    title="Replace All Characters?"
                    description={`This will replace all ${formData.characters?.length || 0} existing character${(formData.characters?.length || 0) !== 1 ? "s" : ""} with characters extracted from the screenplay. This action cannot be undone.`}
                    confirmLabel="Replace All Characters"
                    isLoading={isExtractingCharacters}
                    onConfirm={performCharacterExtraction}
                  />
                </div>
              </div>

              {/* Locations Section */}
              <div ref={locationsSectionRef} className="space-y-3 pt-4 border-t border-border">
                <div className="flex items-center gap-2">
                  <Camera className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Locations</h3>
                </div>

                <div className="space-y-2">
                  {/* Location List - Compact One-Liner View */}
                  {(formData.setting?.locations || []).length > 0 &&
                    editingLocationIndex === null && (
                      <div className="space-y-1.5">
                        {(() => {
                          const locations = formData.setting?.locations || [];
                          const shouldShowAll = locations.length <= 10 || showAllLocations;
                          const locationsToShow = shouldShowAll ? locations : locations.slice(0, 5);

                          return (
                            <>
                              {locationsToShow.map((location, index) => (
                                <div key={`location-compact-${index}`} className="relative">
                                  <button
                                    type="button"
                                    className="flex items-center gap-2 p-1.5 bg-muted/30 rounded-lg border border-border group hover:bg-muted/50 cursor-pointer transition-colors w-full text-left"
                                    onClick={() => setEditingLocationIndex(index)}
                                  >
                                    {/* Edit indicator */}
                                    <div className="pt-0.5 shrink-0">
                                      <Edit className="h-4 w-4 text-primary opacity-0 group-hover:opacity-100 transition-all duration-500" />
                                    </div>

                                    {/* Location Image - Super Small - Clickable for upload */}
                                    <div
                                      className="relative w-8 h-8 rounded overflow-hidden border border-border shrink-0 group/img cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all"
                                      onClick={(e) => {
                                        e.stopPropagation();
                                        handleLocationMainImageClick(index);
                                      }}
                                      title={
                                        location.image
                                          ? "Click to replace image"
                                          : "Click to add image"
                                      }
                                    >
                                      {uploadingLocationIndex === index ? (
                                        <div className="w-full h-full flex items-center justify-center bg-muted">
                                          <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-primary" />
                                        </div>
                                      ) : location.image && formData.username ? (
                                        <>
                                          <OptimizedImage
                                            type="location"
                                            filename={location.image}
                                            username={formData.username}
                                            alt={location.name || "Location"}
                                            fill
                                            objectFit="cover"
                                          />
                                          <div className="absolute inset-0 bg-black/50 opacity-0 group-hover/img:opacity-100 transition-opacity flex items-center justify-center">
                                            <Camera className="h-3 w-3 text-white" />
                                          </div>
                                        </>
                                      ) : (
                                        <div className="w-full h-full flex items-center justify-center bg-muted group-hover/img:bg-primary/10 transition-colors">
                                          <Camera className="h-4 w-4 text-muted-foreground group-hover/img:text-primary transition-colors" />
                                        </div>
                                      )}
                                    </div>

                                    {/* Location Name */}
                                    <span className="font-medium text-sm shrink-0">
                                      {location.name || "Unnamed"}
                                    </span>

                                    {/* Location Description - Truncated */}
                                    <span className="text-xs text-muted-foreground truncate flex-1">
                                      {location.description || "No description"}
                                    </span>

                                    {/* Additional Images Count */}
                                    {(location.images?.length || 0) > 0 && (
                                      <span className="text-xs text-muted-foreground shrink-0">
                                        +{location.images?.length} img
                                      </span>
                                    )}
                                  </button>
                                  {/* Hidden file input for compact view upload */}
                                  <input
                                    ref={(el) => {
                                      locationFileInputRefs.current[index] = el;
                                    }}
                                    type="file"
                                    accept="image/*"
                                    onChange={(e) => handleLocationMainImageChange(e, index)}
                                    className="hidden"
                                    disabled={uploadingLocationIndex === index}
                                  />
                                </div>
                              ))}
                            </>
                          );
                        })()}
                      </div>
                    )}

                  {/* Location Edit Form - Expanded View */}
                  {editingLocationIndex !== null &&
                    formData.setting?.locations?.[editingLocationIndex] && (
                      <Card className="bg-muted/30 border-border">
                        <CardContent className="space-y-4">
                          <div className="flex items-center justify-between">
                            <h4 className="font-medium">Edit Location</h4>
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              onClick={() => {
                                setEditingLocationIndex(null);
                                setConfirmingLocationDelete(null);
                              }}
                              className="bg-transparent"
                            >
                              Done
                            </Button>
                          </div>

                          {/* Location Name */}
                          <div className="space-y-2">
                            <Label htmlFor={`location-name-${editingLocationIndex}`}>Name</Label>
                            <Input
                              id={`location-name-${editingLocationIndex}`}
                              placeholder="Enter location name"
                              value={formData.setting.locations[editingLocationIndex].name}
                              onChange={(e) =>
                                updateLocation(editingLocationIndex, "name", e.target.value)
                              }
                              className="bg-background"
                            />
                          </div>

                          {/* Location Main Image */}
                          <div className="space-y-2">
                            <Label>Main Image</Label>
                            <div className="relative w-full rounded-lg overflow-hidden border border-border bg-muted/30">
                              {locationPreviewImages[editingLocationIndex] ? (
                                <div className="relative group">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img
                                    src={locationPreviewImages[editingLocationIndex]}
                                    alt={
                                      formData.setting.locations[editingLocationIndex].name ||
                                      "Location"
                                    }
                                    className="w-full h-auto"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleLocationMainImageClick(editingLocationIndex)
                                    }
                                    disabled={uploadingLocationIndex === editingLocationIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload location main image"
                                  >
                                    {uploadingLocationIndex === editingLocationIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              ) : formData.setting.locations[editingLocationIndex].image &&
                                formData.username ? (
                                <div className="relative group">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img
                                    src={getImageUrl({
                                      type: "location",
                                      filename:
                                        formData.setting.locations[editingLocationIndex].image!,
                                      username: formData.username,
                                    })}
                                    alt={
                                      formData.setting.locations[editingLocationIndex].name ||
                                      "Location"
                                    }
                                    className="w-full h-auto"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleLocationMainImageClick(editingLocationIndex)
                                    }
                                    disabled={uploadingLocationIndex === editingLocationIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload location main image"
                                  >
                                    {uploadingLocationIndex === editingLocationIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              ) : (
                                <div className="w-full min-h-[200px] flex items-center justify-center relative group">
                                  <Camera className="h-12 w-12 text-muted-foreground" />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleLocationMainImageClick(editingLocationIndex)
                                    }
                                    disabled={uploadingLocationIndex === editingLocationIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload location main image"
                                  >
                                    {uploadingLocationIndex === editingLocationIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              )}
                            </div>
                            <input
                              ref={(el) => {
                                locationFileInputRefs.current[editingLocationIndex] = el;
                              }}
                              type="file"
                              accept="image/*"
                              onChange={(e) =>
                                handleLocationMainImageChange(e, editingLocationIndex)
                              }
                              className="hidden"
                              disabled={uploadingLocationIndex === editingLocationIndex}
                            />
                          </div>

                          {/* Additional Location Images */}
                          <div className="space-y-2">
                            <Label>Additional Images (Different Angles/Variations)</Label>
                            <div className="columns-2 md:columns-3 gap-4">
                              {(formData.setting.locations[editingLocationIndex].images || []).map(
                                (image, imageIndex) => (
                                  <div
                                    key={`${editingLocationIndex}-${imageIndex}`}
                                    className="relative w-full mb-4 break-inside-avoid rounded-lg overflow-hidden border border-border bg-muted/30"
                                  >
                                    {locationAdditionalPreviewImages[editingLocationIndex]?.[
                                      imageIndex
                                    ] ? (
                                      <div className="relative group">
                                        {/* eslint-disable-next-line @next/next/no-img-element */}
                                        <img
                                          src={
                                            locationAdditionalPreviewImages[editingLocationIndex][
                                              imageIndex
                                            ]
                                          }
                                          alt={`${formData.setting?.locations?.[editingLocationIndex]?.name || "Location"} - ${imageIndex + 1}`}
                                          className="w-full h-auto"
                                        />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleLocationAdditionalImageClick(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingLocationAdditionalIndex?.locationIndex ===
                                              editingLocationIndex &&
                                            uploadingLocationAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional location image ${imageIndex + 1}`}
                                        >
                                          {uploadingLocationAdditionalIndex?.locationIndex ===
                                            editingLocationIndex &&
                                          uploadingLocationAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                        <button
                                          type="button"
                                          onClick={() =>
                                            removeLocationAdditionalImage(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          className="absolute top-1 right-1 bg-destructive text-destructive-foreground rounded-full p-1 opacity-75 hover:opacity-100 transition-opacity z-10"
                                          aria-label={`Remove image ${imageIndex + 1}`}
                                        >
                                          <X className="h-3 w-3" />
                                        </button>
                                      </div>
                                    ) : image && formData.username ? (
                                      <div className="relative group">
                                        {/* eslint-disable-next-line @next/next/no-img-element */}
                                        <img
                                          src={getImageUrl({
                                            type: "location",
                                            filename: image,
                                            username: formData.username,
                                          })}
                                          alt={`${formData.setting?.locations?.[editingLocationIndex]?.name || "Location"} - ${imageIndex + 1}`}
                                          className="w-full h-auto"
                                        />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleLocationAdditionalImageClick(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingLocationAdditionalIndex?.locationIndex ===
                                              editingLocationIndex &&
                                            uploadingLocationAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional location image ${imageIndex + 1}`}
                                        >
                                          {uploadingLocationAdditionalIndex?.locationIndex ===
                                            editingLocationIndex &&
                                          uploadingLocationAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                        <button
                                          type="button"
                                          onClick={() =>
                                            removeLocationAdditionalImage(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          className="absolute top-1 right-1 bg-destructive text-destructive-foreground rounded-full p-1 opacity-75 hover:opacity-100 transition-opacity z-10"
                                          aria-label={`Remove image ${imageIndex + 1}`}
                                        >
                                          <X className="h-3 w-3" />
                                        </button>
                                      </div>
                                    ) : (
                                      <div className="w-full min-h-[150px] flex items-center justify-center relative group">
                                        <Camera className="h-8 w-8 text-muted-foreground" />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleLocationAdditionalImageClick(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingLocationAdditionalIndex?.locationIndex ===
                                              editingLocationIndex &&
                                            uploadingLocationAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional location image ${imageIndex + 1}`}
                                        >
                                          {uploadingLocationAdditionalIndex?.locationIndex ===
                                            editingLocationIndex &&
                                          uploadingLocationAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                      </div>
                                    )}
                                    <input
                                      ref={(el) => {
                                        locationAdditionalFileInputRefs.current[
                                          `${editingLocationIndex}-${imageIndex}`
                                        ] = el;
                                      }}
                                      type="file"
                                      accept="image/*"
                                      onChange={(e) =>
                                        handleLocationAdditionalImageChange(
                                          e,
                                          editingLocationIndex,
                                          imageIndex
                                        )
                                      }
                                      className="hidden"
                                      disabled={
                                        uploadingLocationAdditionalIndex?.locationIndex ===
                                          editingLocationIndex &&
                                        uploadingLocationAdditionalIndex?.imageIndex === imageIndex
                                      }
                                    />
                                  </div>
                                )
                              )}
                              <div className="relative w-full mb-4 break-inside-avoid">
                                <button
                                  type="button"
                                  onClick={() =>
                                    handleAddLocationAdditionalImageClick(editingLocationIndex)
                                  }
                                  className="relative w-full min-h-[150px] rounded-lg border-2 border-dashed border-border bg-muted/30 hover:bg-muted/50 transition-colors flex items-center justify-center"
                                  aria-label="Add additional location image"
                                >
                                  <Plus className="h-8 w-8 text-muted-foreground" />
                                  <input
                                    ref={(el) => {
                                      locationAddImageInputRefs.current[editingLocationIndex] = el;
                                    }}
                                    type="file"
                                    accept="image/*"
                                    onChange={(e) =>
                                      handleAddLocationAdditionalImageChange(
                                        e,
                                        editingLocationIndex
                                      )
                                    }
                                    className="hidden"
                                    disabled={
                                      uploadingLocationAdditionalIndex?.locationIndex ===
                                      editingLocationIndex
                                    }
                                  />
                                </button>
                              </div>
                            </div>
                          </div>

                          {/* Location Description */}
                          <div className="space-y-2">
                            <Label htmlFor={`location-description-${editingLocationIndex}`}>
                              Description
                            </Label>
                            <Textarea
                              id={`location-description-${editingLocationIndex}`}
                              placeholder="Describe this location..."
                              value={formData.setting.locations[editingLocationIndex].description}
                              onChange={(e) =>
                                updateLocation(editingLocationIndex, "description", e.target.value)
                              }
                              rows={3}
                              className="bg-background resize-none"
                            />
                          </div>

                          {/* Delete Location Button */}
                          <div className="pt-4 flex justify-end">
                            {confirmingLocationDelete === editingLocationIndex ? (
                              <div className="space-y-3 text-right">
                                <p className="text-sm text-muted-foreground">
                                  Are you sure you want to delete this location? This action cannot
                                  be undone.
                                </p>
                                <div className="flex items-center justify-end gap-2">
                                  <Button
                                    type="button"
                                    variant="destructive"
                                    size="sm"
                                    onClick={() => {
                                      removeLocation(editingLocationIndex);
                                      setEditingLocationIndex(null);
                                      setConfirmingLocationDelete(null);
                                    }}
                                  >
                                    <Trash className="h-4 w-4 mr-2" />
                                    Delete Location
                                  </Button>
                                  <Button
                                    type="button"
                                    variant="outline"
                                    size="sm"
                                    onClick={() => setConfirmingLocationDelete(null)}
                                    className="bg-transparent"
                                  >
                                    Cancel
                                  </Button>
                                </div>
                              </div>
                            ) : (
                              <Button
                                type="button"
                                variant="ghost"
                                size="sm"
                                onClick={() => setConfirmingLocationDelete(editingLocationIndex)}
                                className="text-xs text-destructive hover:text-destructive hover:bg-destructive/10"
                              >
                                <X className="h-2 w-2 mr-2" />
                                Delete Location
                              </Button>
                            )}
                          </div>
                        </CardContent>
                      </Card>
                    )}

                  <div className="flex gap-2 flex-wrap items-center">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={addLocation}
                      className="bg-transparent"
                    >
                      <Plus className="h-4 w-4 mr-2" />
                      Add Location
                    </Button>
                    {formData.screenplayText?.trim() && (
                      <Button
                        type="button"
                        variant="outline"
                        onClick={handleExtractLocations}
                        disabled={isExtractingLocations}
                        className="bg-transparent"
                      >
                        {isExtractingLocations ? (
                          <>
                            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                            Extracting...
                          </>
                        ) : (
                          <>
                            <Film className="h-4 w-4 mr-2" />
                            Extract from Screenplay
                          </>
                        )}
                      </Button>
                    )}
                    {(formData.setting?.locations?.length || 0) > 10 && (
                      <>
                        <div className="flex-1" />
                        <button
                          type="button"
                          onClick={() => {
                            const wasShowingAll = showAllLocations;
                            setShowAllLocations(!showAllLocations);
                            if (wasShowingAll) {
                              setTimeout(() => {
                                locationsSectionRef.current?.scrollIntoView({
                                  behavior: "smooth",
                                  block: "start",
                                });
                              }, 0);
                            }
                          }}
                          className="text-sm text-muted-foreground hover:text-foreground flex items-center gap-1 transition-colors"
                        >
                          <ChevronsDown
                            className={cn(
                              "h-4 w-4 transition-transform duration-300",
                              showAllLocations ? "rotate-180" : ""
                            )}
                          />
                          {showAllLocations
                            ? "Show Less"
                            : `Show All (${formData.setting?.locations?.length})`}
                        </button>
                      </>
                    )}
                  </div>

                  {/* Extract Locations Confirmation Dialog */}
                  <ExtractConfirmDialog
                    open={showExtractLocationsDialog}
                    onOpenChange={setShowExtractLocationsDialog}
                    title="Replace All Locations?"
                    description={`This will replace all ${formData.setting?.locations?.length || 0} existing location${(formData.setting?.locations?.length || 0) !== 1 ? "s" : ""} with locations extracted from the screenplay. This action cannot be undone.`}
                    confirmLabel="Replace All Locations"
                    isLoading={isExtractingLocations}
                    onConfirm={performLocationExtraction}
                  />
                </div>
              </div>

              {/* Scenes Section */}
              <div className="space-y-4 pt-4 border-t border-border">
                <div className="flex items-center gap-2">
                  <Clapperboard className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Scenes</h3>
                </div>
                <p className="text-sm text-muted-foreground">
                  Add scenes to your project. Each scene can carry screenplay context, characters,
                  reference assets, and prompt-ready shot breakdowns.
                </p>

                <SceneList
                  projectId={effectiveProjectId}
                  scenes={formData.scenes || []}
                  characters={formData.characters || []}
                  locations={formData.setting?.locations || []}
                  screenplayText={formData.screenplayText}
                  onScenesChange={(scenes) => setFormData({ ...formData, scenes })}
                />
              </div>
            </div>
          )}

          {/* Default Layout - All sections in order */}
          {!useGridLayout && (
            <>
              {/* Project Info Section */}
              {!isEditingProjectInfo ? (
                /* Compact Project Info View */
                <div className="flex flex-col sm:flex-row gap-4 p-4 rounded-lg border border-border bg-muted/30">
                  {/* Thumbnail */}
                  <div className="w-full sm:w-48 md:w-64 shrink-0">
                    <div className="relative aspect-video rounded-lg overflow-hidden border border-border bg-muted">
                      {formData.thumbnail && formData.username ? (
                        <OptimizedImage
                          type="thumbnail"
                          filename={formData.thumbnail}
                          username={formData.username}
                          alt="Project image"
                          fill
                          objectFit="cover"
                          sizes="256px"
                        />
                      ) : (
                        <div className="absolute inset-0 flex items-center justify-center">
                          <Film className="h-8 w-8 text-muted-foreground" />
                        </div>
                      )}
                    </div>
                  </div>
                  {/* Info */}
                  <div className="flex-1 min-w-0 space-y-2">
                    <div className="flex items-start justify-between gap-4">
                      <div className="min-w-0">
                        <h3 className="text-2xl font-semibold truncate">
                          {formData.title || "Untitled Project"}
                        </h3>
                        {formData.logline && (
                          <p className="text-muted-foreground line-clamp-2">{formData.logline}</p>
                        )}
                      </div>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => setIsEditingProjectInfo(true)}
                        className="shrink-0 bg-transparent"
                      >
                        <Pencil className="h-4 w-4 mr-2" />
                        Edit
                      </Button>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {formData.genre && (
                        <span className="px-2 py-1 text-xs font-medium rounded-full bg-primary/10 text-primary">
                          {formData.genre}
                        </span>
                      )}
                      {(formData.filmLength || formData.duration) && (
                        <span className="px-2 py-1 text-xs font-medium rounded-full bg-muted text-muted-foreground">
                          {formData.filmLength || formData.duration}
                        </span>
                      )}
                    </div>
                    {formData.filmLink && (
                      <p className="text-xs text-muted-foreground truncate">
                        <LinkIcon className="h-3 w-3 inline mr-1" />
                        {formData.filmLink}
                      </p>
                    )}
                  </div>
                </div>
              ) : (
                /* Expanded Project Info Edit Form */
                <div className="space-y-6 p-4 rounded-lg border border-border bg-muted/10">
                  <div className="flex items-center justify-between">
                    <h3 className="font-medium">Project Info</h3>
                    {isEditing && (
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => setIsEditingProjectInfo(false)}
                        className="bg-transparent"
                      >
                        Done
                      </Button>
                    )}
                  </div>

                  <div className="grid md:grid-cols-2 gap-6">
                    <div className="space-y-6">
                      <div className="space-y-2">
                        <Label htmlFor="title">Project Title *</Label>
                        <Input
                          id="title"
                          placeholder="Enter your project title"
                          value={formData.title}
                          onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                          className="bg-background"
                          required
                        />
                      </div>

                      <div className="space-y-2">
                        <Label htmlFor="logline">Logline</Label>
                        <Input
                          id="logline"
                          placeholder="A one-sentence summary of your film's story"
                          value={formData.logline || ""}
                          onChange={(e) => setFormData({ ...formData, logline: e.target.value })}
                          className="bg-background"
                        />
                        <p className="text-xs text-muted-foreground">
                          A brief, compelling description of your film in 1-2 sentences
                        </p>
                      </div>

                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="genre">Genre</Label>
                          <Select
                            value={formData.genre}
                            onValueChange={(value) => setFormData({ ...formData, genre: value })}
                          >
                            <SelectTrigger id={genreSelectId} className="w-full bg-background">
                              <SelectValue placeholder="Select genre..." />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="Action">Action</SelectItem>
                              <SelectItem value="Animation">Animation</SelectItem>
                              <SelectItem value="Comedy">Comedy</SelectItem>
                              <SelectItem value="Documentary">Documentary</SelectItem>
                              <SelectItem value="Drama">Drama</SelectItem>
                              <SelectItem value="Fantasy">Fantasy</SelectItem>
                              <SelectItem value="Horror">Horror</SelectItem>
                              <SelectItem value="Romance">Romance</SelectItem>
                              <SelectItem value="Sci-Fi">Sci-Fi</SelectItem>
                              <SelectItem value="Thriller">Thriller</SelectItem>
                              <SelectItem value="Experimental">Experimental</SelectItem>
                              <SelectItem value="Other">Other</SelectItem>
                            </SelectContent>
                          </Select>
                        </div>

                        <div className="space-y-2">
                          <Label htmlFor="duration">Film Length</Label>
                          <Select
                            value={formData.filmLength || formData.duration}
                            onValueChange={(value) =>
                              setFormData({
                                ...formData,
                                filmLength: value as FilmLengthOption,
                                duration: value,
                              })
                            }
                          >
                            <SelectTrigger id={durationSelectId} className="w-full bg-background">
                              <SelectValue placeholder="Select film length..." />
                            </SelectTrigger>
                            <SelectContent>
                              {FILM_LENGTH_OPTIONS.map((option) => (
                                <SelectItem key={option} value={option}>
                                  {option}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      </div>

                      <div className="space-y-2">
                        <Label htmlFor="filmLink">Film Link</Label>
                        <Input
                          id="filmLink"
                          placeholder="YouTube or Vimeo URL (e.g., https://youtube.com/watch?v=...)"
                          value={formData.filmLink || ""}
                          onChange={(e) => setFormData({ ...formData, filmLink: e.target.value })}
                          className="bg-background"
                        />
                        <p className="text-xs text-muted-foreground">
                          Add a link to your film on YouTube or Vimeo
                        </p>
                      </div>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="thumbnail">Project Image</Label>
                      <div className="space-y-4">
                        {/* Thumbnail Preview */}
                        <div className="relative w-full aspect-video rounded-lg overflow-hidden border border-border bg-muted/30">
                          {previewImage ? (
                            <ImagePreview
                              src={previewImage}
                              isUploading={isUploadingImage}
                              isUploaded={!!formData.thumbnail}
                              alt="Project image"
                              aspectRatio="video"
                              objectFit="cover"
                            />
                          ) : formData.thumbnail && formData.username ? (
                            <OptimizedImage
                              type="thumbnail"
                              filename={formData.thumbnail}
                              username={formData.username}
                              alt="Project image"
                              fill
                              objectFit="cover"
                              sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
                            />
                          ) : null}
                          {/* Upload overlay */}
                          <button
                            type="button"
                            onClick={handleImageClick}
                            disabled={isUploadingImage}
                            className="group absolute inset-0 flex items-center justify-center bg-black/60 opacity-50 hover:opacity-100 transition-all duration-300 cursor-pointer disabled:cursor-not-allowed"
                            aria-label="Upload project image"
                          >
                            {isUploadingImage ? (
                              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                            ) : (
                              <div className="flex flex-col items-center gap-2">
                                <Camera className="h-8 w-8 text-white" />
                                <span className="text-sm text-white font-medium">
                                  {formData.thumbnail ? "Change Image" : "Upload Image"}
                                </span>
                              </div>
                            )}
                          </button>
                        </div>

                        {/* Upload Button */}
                        <div className="flex items-center gap-4">
                          <Button
                            type="button"
                            variant="outline"
                            onClick={handleImageClick}
                            disabled={isUploadingImage}
                            className="bg-transparent"
                          >
                            <Upload className="h-4 w-4 mr-2" />
                            {isUploadingImage
                              ? "Uploading..."
                              : formData.thumbnail
                                ? "Change Image"
                                : "Upload Image"}
                          </Button>
                          <span className="text-sm text-muted-foreground">
                            {formData.thumbnail ? "Image uploaded" : "No image selected"}
                          </span>
                        </div>

                        {/* Hidden file input */}
                        <input
                          ref={fileInputRef}
                          type="file"
                          accept="image/*"
                          onChange={handleImageChange}
                          className="hidden"
                          disabled={isUploadingImage}
                        />
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* Screenplay Section */}
              <div className="space-y-4 pt-4 border-t border-border" suppressHydrationWarning>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <File className="h-5 w-5 text-primary" />
                    <h3 className="text-lg font-semibold">Screenplay / Script</h3>
                  </div>
                  {isEditing && projectId && (formData.screenplayText || formData.screenplay) && (
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => router.push(`/dashboard/projects/${projectId}/screenplay`)}
                      className="bg-transparent"
                    >
                      <Pencil className="h-4 w-4 mr-2" />
                      Edit Screenplay
                    </Button>
                  )}
                </div>
                {!formData.screenplayText && (
                  <p className="text-sm text-muted-foreground">
                    Upload a PDF screenplay or use the editor to write your screenplay. The text
                    will be automatically extracted from PDFs.
                  </p>
                )}

                {/* Screenplay Status - One Line */}
                {formData.screenplayText ? (
                  <div className="flex items-center justify-between gap-3 px-3 py-2 bg-muted/30 rounded-lg border border-border">
                    <span className="text-sm text-muted-foreground">
                      {formData.screenplayText.split(/\s+/).filter((w) => w.length > 0).length}{" "}
                      words • {formData.screenplayText.match(/^(INT\.|EXT\.)/gm)?.length || 0}{" "}
                      scenes
                    </span>
                    <div className="flex items-center gap-3">
                      {showRemoveScreenplayConfirm ? (
                        <>
                          <span className="text-xs text-muted-foreground">Replace screenplay?</span>
                          <button
                            onClick={() => {
                              setShowRemoveScreenplayConfirm(false);
                              projectFileInputRef.current?.click();
                            }}
                            type="button"
                            className="text-primary hover:text-primary/80 font-medium text-xs"
                          >
                            Yes
                          </button>
                          <button
                            onClick={() => setShowRemoveScreenplayConfirm(false)}
                            type="button"
                            className="text-muted-foreground hover:text-foreground text-xs"
                          >
                            Cancel
                          </button>
                        </>
                      ) : (
                        <button
                          onClick={() => setShowRemoveScreenplayConfirm(true)}
                          type="button"
                          className="text-xs text-muted-foreground hover:text-foreground"
                        >
                          Replace
                        </button>
                      )}
                    </div>
                  </div>
                ) : (
                  <Button
                    type="button"
                    variant="outline"
                    onClick={handleProjectFileClick}
                    disabled={isUploadingFile}
                    className="bg-transparent"
                  >
                    <Upload className="h-4 w-4 mr-2" />
                    {isUploadingFile ? "Uploading..." : "Upload PDF"}
                  </Button>
                )}

                {/* Hidden file input - Always rendered so ref is always available */}
                <input
                  ref={projectFileInputRef}
                  type="file"
                  onChange={handleProjectFileChange}
                  className="hidden"
                  disabled={isUploadingFile}
                  accept=".pdf,application/pdf"
                />
              </div>

              {/* Characters Section */}
              <div ref={charactersSectionRef} className="space-y-3 pt-4 border-t border-border">
                <div className="flex items-center gap-2">
                  <User className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Characters</h3>
                </div>

                <div className="space-y-2">
                  {/* Character List - Compact One-Liner View */}
                  {(formData.characters || []).length > 0 && editingCharacterIndex === null && (
                    <div className="space-y-1.5">
                      {(() => {
                        const characters = formData.characters || [];
                        const shouldShowAll = characters.length <= 10 || showAllCharacters;
                        const charactersToShow = shouldShowAll
                          ? characters
                          : characters.slice(0, 5);

                        return (
                          <>
                            {charactersToShow.map((character, index) => (
                              <div key={`character-compact-${index}`} className="relative">
                                <button
                                  type="button"
                                  className="flex items-center gap-2 p-1.5 bg-muted/30 rounded-lg border border-border group hover:bg-muted/50 cursor-pointer transition-colors w-full text-left"
                                  onClick={() => setEditingCharacterIndex(index)}
                                >
                                  {/* Edit indicator */}
                                  <div className="pt-0.5 shrink-0">
                                    <Edit className="h-4 w-4 text-primary opacity-0 group-hover:opacity-100 transition-all duration-500" />
                                  </div>

                                  {/* Character Image - Super Small - Clickable for upload */}
                                  <div
                                    className="relative w-8 h-8 rounded overflow-hidden border border-border shrink-0 group/img cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all"
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      handleCharacterMainImageClick(index);
                                    }}
                                    title={
                                      character.mainImage
                                        ? "Click to replace image"
                                        : "Click to add image"
                                    }
                                  >
                                    {uploadingCharacterIndex === index ? (
                                      <div className="w-full h-full flex items-center justify-center bg-muted">
                                        <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-primary" />
                                      </div>
                                    ) : character.mainImage && formData.username ? (
                                      <>
                                        <OptimizedImage
                                          type="character"
                                          filename={character.mainImage}
                                          username={formData.username}
                                          alt={character.name || "Character"}
                                          fill
                                          objectFit="cover"
                                        />
                                        <div className="absolute inset-0 bg-black/50 opacity-0 group-hover/img:opacity-100 transition-opacity flex items-center justify-center">
                                          <Camera className="h-3 w-3 text-white" />
                                        </div>
                                      </>
                                    ) : (
                                      <div className="w-full h-full flex items-center justify-center bg-muted group-hover/img:bg-primary/10 transition-colors">
                                        <Camera className="h-4 w-4 text-muted-foreground group-hover/img:text-primary transition-colors" />
                                      </div>
                                    )}
                                  </div>

                                  {/* Character Name */}
                                  <span className="font-medium text-sm shrink-0">
                                    {character.name || "Unnamed"}
                                  </span>

                                  {/* Character Appearance - Truncated */}
                                  <span className="text-xs text-muted-foreground truncate flex-1">
                                    {character.appearance || "No appearance description"}
                                  </span>

                                  {/* Additional Images Count */}
                                  {(character.images?.length || 0) > 0 && (
                                    <span className="text-xs text-muted-foreground shrink-0">
                                      +{character.images?.length} img
                                    </span>
                                  )}
                                </button>
                                {/* Hidden file input for compact view upload */}
                                <input
                                  ref={(el) => {
                                    characterFileInputRefs.current[index] = el;
                                  }}
                                  type="file"
                                  accept="image/*"
                                  onChange={(e) =>
                                    handleCharacterMainImageChange(e, index)
                                  }
                                  className="hidden"
                                  disabled={uploadingCharacterIndex === index}
                                />
                              </div>
                            ))}
                          </>
                        );
                      })()}
                    </div>
                  )}

                  {/* Character Edit Form - Expanded View */}
                  {editingCharacterIndex !== null &&
                    formData.characters?.[editingCharacterIndex] && (
                      <Card className="bg-muted/30 border-border">
                        <CardContent className="p-4 space-y-4">
                          <div className="flex items-center justify-between">
                            <h4 className="font-medium">Edit Character</h4>
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              onClick={() => {
                                setEditingCharacterIndex(null);
                                setConfirmingCharacterDelete(null);
                              }}
                              className="bg-transparent"
                            >
                              Done
                            </Button>
                          </div>

                          {/* Character Name */}
                          <div className="space-y-2">
                            <Label htmlFor={`character-name-${editingCharacterIndex}`}>Name</Label>
                            <Input
                              id={`character-name-${editingCharacterIndex}`}
                              placeholder="Enter character name"
                              value={formData.characters[editingCharacterIndex].name}
                              onChange={(e) =>
                                updateCharacter(editingCharacterIndex, "name", e.target.value)
                              }
                              className="bg-background"
                            />
                          </div>

                          {/* Character Main Image */}
                          <div className="space-y-2">
                            <Label>Main Image</Label>
                            <div className="relative w-full rounded-lg overflow-hidden border border-border bg-muted/30">
                              {characterPreviewImages[editingCharacterIndex] ? (
                                <div className="relative group">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img
                                    src={characterPreviewImages[editingCharacterIndex]}
                                    alt={
                                      formData.characters[editingCharacterIndex].name || "Character"
                                    }
                                    className="w-full h-auto"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleCharacterMainImageClick(editingCharacterIndex)
                                    }
                                    disabled={uploadingCharacterIndex === editingCharacterIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload character main image"
                                  >
                                    {uploadingCharacterIndex === editingCharacterIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              ) : formData.characters[editingCharacterIndex].mainImage &&
                                formData.username ? (
                                <div className="relative group">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img
                                    src={getImageUrl({
                                      type: "character",
                                      filename:
                                        formData.characters[editingCharacterIndex].mainImage!,
                                      username: formData.username,
                                    })}
                                    alt={
                                      formData.characters[editingCharacterIndex].name || "Character"
                                    }
                                    className="w-full h-auto"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleCharacterMainImageClick(editingCharacterIndex)
                                    }
                                    disabled={uploadingCharacterIndex === editingCharacterIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload character main image"
                                  >
                                    {uploadingCharacterIndex === editingCharacterIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              ) : (
                                <div className="w-full min-h-[200px] flex items-center justify-center relative group">
                                  <User className="h-12 w-12 text-muted-foreground" />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleCharacterMainImageClick(editingCharacterIndex)
                                    }
                                    disabled={uploadingCharacterIndex === editingCharacterIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload character main image"
                                  >
                                    {uploadingCharacterIndex === editingCharacterIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              )}
                            </div>
                            <input
                              ref={(el) => {
                                characterFileInputRefs.current[editingCharacterIndex] = el;
                              }}
                              type="file"
                              accept="image/*"
                              onChange={(e) =>
                                handleCharacterMainImageChange(e, editingCharacterIndex)
                              }
                              className="hidden"
                              disabled={uploadingCharacterIndex === editingCharacterIndex}
                            />
                          </div>

                          {/* Additional Character Images */}
                          <div className="space-y-2">
                            <Label>Additional Images (Different Angles/Attire)</Label>
                            <div className="columns-2 md:columns-3 gap-4">
                              {(formData.characters[editingCharacterIndex].images || []).map(
                                (image, imageIndex) => (
                                  <div
                                    key={`${editingCharacterIndex}-${imageIndex}`}
                                    className="relative w-full mb-4 break-inside-avoid rounded-lg overflow-hidden border border-border bg-muted/30"
                                  >
                                    {characterAdditionalPreviewImages[editingCharacterIndex]?.[
                                      imageIndex
                                    ] ? (
                                      <div className="relative group">
                                        {/* eslint-disable-next-line @next/next/no-img-element */}
                                        <img
                                          src={
                                            characterAdditionalPreviewImages[editingCharacterIndex][
                                              imageIndex
                                            ]
                                          }
                                          alt={`${formData.characters?.[editingCharacterIndex]?.name || "Character"} - ${imageIndex + 1}`}
                                          className="w-full h-auto"
                                        />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleCharacterAdditionalImageClick(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingCharacterAdditionalIndex?.characterIndex ===
                                              editingCharacterIndex &&
                                            uploadingCharacterAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional character image ${imageIndex + 1}`}
                                        >
                                          {uploadingCharacterAdditionalIndex?.characterIndex ===
                                            editingCharacterIndex &&
                                          uploadingCharacterAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                        <button
                                          type="button"
                                          onClick={() =>
                                            removeCharacterAdditionalImage(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          className="absolute top-1 right-1 bg-destructive text-destructive-foreground rounded-full p-1 opacity-75 hover:opacity-100 transition-opacity z-10"
                                          aria-label={`Remove image ${imageIndex + 1}`}
                                        >
                                          <X className="h-3 w-3" />
                                        </button>
                                      </div>
                                    ) : image && formData.username ? (
                                      <div className="relative group">
                                        {/* eslint-disable-next-line @next/next/no-img-element */}
                                        <img
                                          src={getImageUrl({
                                            type: "character",
                                            filename: image,
                                            username: formData.username,
                                          })}
                                          alt={`${formData.characters?.[editingCharacterIndex]?.name || "Character"} - ${imageIndex + 1}`}
                                          className="w-full h-auto"
                                        />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleCharacterAdditionalImageClick(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingCharacterAdditionalIndex?.characterIndex ===
                                              editingCharacterIndex &&
                                            uploadingCharacterAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional character image ${imageIndex + 1}`}
                                        >
                                          {uploadingCharacterAdditionalIndex?.characterIndex ===
                                            editingCharacterIndex &&
                                          uploadingCharacterAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                        <button
                                          type="button"
                                          onClick={() =>
                                            removeCharacterAdditionalImage(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          className="absolute top-1 right-1 bg-destructive text-destructive-foreground rounded-full p-1 opacity-75 hover:opacity-100 transition-opacity z-10"
                                          aria-label={`Remove image ${imageIndex + 1}`}
                                        >
                                          <X className="h-3 w-3" />
                                        </button>
                                      </div>
                                    ) : (
                                      <div className="w-full min-h-[150px] flex items-center justify-center relative group">
                                        <Camera className="h-8 w-8 text-muted-foreground" />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleCharacterAdditionalImageClick(
                                              editingCharacterIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingCharacterAdditionalIndex?.characterIndex ===
                                              editingCharacterIndex &&
                                            uploadingCharacterAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional character image ${imageIndex + 1}`}
                                        >
                                          {uploadingCharacterAdditionalIndex?.characterIndex ===
                                            editingCharacterIndex &&
                                          uploadingCharacterAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                      </div>
                                    )}
                                    <input
                                      ref={(el) => {
                                        characterAdditionalFileInputRefs.current[
                                          `${editingCharacterIndex}-${imageIndex}`
                                        ] = el;
                                      }}
                                      type="file"
                                      accept="image/*"
                                      onChange={(e) =>
                                        handleCharacterAdditionalImageChange(
                                          e,
                                          editingCharacterIndex,
                                          imageIndex
                                        )
                                      }
                                      className="hidden"
                                      disabled={
                                        uploadingCharacterAdditionalIndex?.characterIndex ===
                                          editingCharacterIndex &&
                                        uploadingCharacterAdditionalIndex?.imageIndex === imageIndex
                                      }
                                    />
                                  </div>
                                )
                              )}
                              <div className="relative w-full mb-4 break-inside-avoid">
                                <button
                                  type="button"
                                  onClick={() =>
                                    handleAddCharacterAdditionalImageClick(editingCharacterIndex)
                                  }
                                  className="relative w-full min-h-[150px] rounded-lg border-2 border-dashed border-border bg-muted/30 hover:bg-muted/50 transition-colors flex items-center justify-center"
                                  aria-label="Add additional character image"
                                >
                                  <Plus className="h-8 w-8 text-muted-foreground" />
                                  <input
                                    ref={(el) => {
                                      characterAddImageInputRefs.current[editingCharacterIndex] =
                                        el;
                                    }}
                                    type="file"
                                    accept="image/*"
                                    multiple
                                    onChange={(e) =>
                                      handleAddCharacterAdditionalImageChange(
                                        e,
                                        editingCharacterIndex
                                      )
                                    }
                                    className="hidden"
                                    disabled={
                                      uploadingCharacterAdditionalIndex?.characterIndex ===
                                      editingCharacterIndex
                                    }
                                  />
                                </button>
                              </div>
                            </div>
                          </div>

                          {/* Character Appearance */}
                          <div className="space-y-2">
                            <Label htmlFor={`character-appearance-${editingCharacterIndex}`}>
                              Appearance
                            </Label>
                            <Textarea
                              id={`character-appearance-${editingCharacterIndex}`}
                              placeholder="Describe this character's appearance..."
                              value={formData.characters[editingCharacterIndex].appearance}
                              onChange={(e) =>
                                updateCharacter(editingCharacterIndex, "appearance", e.target.value)
                              }
                              rows={3}
                              className="bg-background resize-none"
                            />
                          </div>

                          <div className="grid gap-4 md:grid-cols-2">
                            <div className="space-y-2">
                              <Label htmlFor={`character-role-${editingCharacterIndex}`}>Role</Label>
                              <Input
                                id={`character-role-${editingCharacterIndex}`}
                                placeholder="Protagonist, antagonist, mentor..."
                                value={formData.characters[editingCharacterIndex].role || ""}
                                onChange={(e) =>
                                  updateCharacter(editingCharacterIndex, "role", e.target.value)
                                }
                                className="bg-background"
                              />
                            </div>
                            <div className="space-y-2">
                              <Label htmlFor={`character-motivation-${editingCharacterIndex}`}>
                                Motivation
                              </Label>
                              <Input
                                id={`character-motivation-${editingCharacterIndex}`}
                                placeholder="What does this character want?"
                                value={formData.characters[editingCharacterIndex].motivation || ""}
                                onChange={(e) =>
                                  updateCharacter(
                                    editingCharacterIndex,
                                    "motivation",
                                    e.target.value
                                  )
                                }
                                className="bg-background"
                              />
                            </div>
                          </div>

                          <div className="space-y-2">
                            <Label htmlFor={`character-arc-${editingCharacterIndex}`}>Arc</Label>
                            <Textarea
                              id={`character-arc-${editingCharacterIndex}`}
                              placeholder="How they change over the story..."
                              value={formData.characters[editingCharacterIndex].arc || ""}
                              onChange={(e) =>
                                updateCharacter(editingCharacterIndex, "arc", e.target.value)
                              }
                              rows={2}
                              className="bg-background resize-none"
                            />
                          </div>

                          <div className="space-y-2">
                            <Label htmlFor={`character-visual-prompt-${editingCharacterIndex}`}>
                              Visual Prompt Notes
                            </Label>
                            <Textarea
                              id={`character-visual-prompt-${editingCharacterIndex}`}
                              placeholder="Prompt notes for consistent image generation..."
                              value={formData.characters[editingCharacterIndex].visualPrompt || ""}
                              onChange={(e) =>
                                updateCharacter(
                                  editingCharacterIndex,
                                  "visualPrompt",
                                  e.target.value
                                )
                              }
                              rows={3}
                              className="bg-background resize-none"
                            />
                          </div>

                          {/* Delete Character Button */}
                          <div className="pt-4 border-t border-border flex justify-end">
                            {confirmingCharacterDelete === editingCharacterIndex ? (
                              <div className="space-y-3 text-right">
                                <p className="text-sm text-muted-foreground">
                                  Are you sure you want to delete this character? This action cannot
                                  be undone.
                                </p>
                                <div className="flex items-center justify-end gap-2">
                                  <Button
                                    type="button"
                                    variant="destructive"
                                    size="sm"
                                    onClick={() => {
                                      removeCharacter(editingCharacterIndex);
                                      setEditingCharacterIndex(null);
                                      setConfirmingCharacterDelete(null);
                                    }}
                                  >
                                    <Trash className="h-4 w-4 mr-2" />
                                    Delete Character
                                  </Button>
                                  <Button
                                    type="button"
                                    variant="outline"
                                    size="sm"
                                    onClick={() => setConfirmingCharacterDelete(null)}
                                    className="bg-transparent"
                                  >
                                    Cancel
                                  </Button>
                                </div>
                              </div>
                            ) : (
                              <Button
                                type="button"
                                variant="ghost"
                                size="sm"
                                onClick={() => setConfirmingCharacterDelete(editingCharacterIndex)}
                                className="text-destructive hover:text-destructive hover:bg-destructive/10"
                              >
                                <Trash className="h-4 w-4 mr-2" />
                                Delete Character
                              </Button>
                            )}
                          </div>
                        </CardContent>
                      </Card>
                    )}

                  <div className="flex gap-2 flex-wrap items-center">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={addCharacter}
                      className="bg-transparent"
                    >
                      <Plus className="h-4 w-4 mr-2" />
                      Add Character
                    </Button>
                    {formData.screenplayText?.trim() && (
                      <Button
                        type="button"
                        variant="outline"
                        onClick={handleExtractCharacters}
                        disabled={isExtractingCharacters}
                        className="bg-transparent"
                      >
                        {isExtractingCharacters ? (
                          <>
                            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                            Extracting...
                          </>
                        ) : (
                          <>
                            <Film className="h-4 w-4 mr-2" />
                            Extract from Screenplay
                          </>
                        )}
                      </Button>
                    )}
                    {(formData.characters?.length || 0) > 10 && (
                      <>
                        <div className="flex-1" />
                        <button
                          type="button"
                          onClick={() => {
                            const wasShowingAll = showAllCharacters;
                            setShowAllCharacters(!showAllCharacters);
                            if (wasShowingAll) {
                              setTimeout(() => {
                                charactersSectionRef.current?.scrollIntoView({
                                  behavior: "smooth",
                                  block: "start",
                                });
                              }, 0);
                            }
                          }}
                          className="text-sm text-muted-foreground hover:text-foreground flex items-center gap-1 transition-colors"
                        >
                          <ChevronsDown
                            className={cn(
                              "h-4 w-4 transition-transform duration-300",
                              showAllCharacters ? "rotate-180" : ""
                            )}
                          />
                          {showAllCharacters
                            ? "Show Less"
                            : `Show All (${formData.characters?.length})`}
                        </button>
                      </>
                    )}
                  </div>
                </div>
              </div>

              {/* Locations Section */}
              <div ref={locationsSectionRef} className="space-y-3 pt-4 border-t border-border">
                <div className="flex items-center gap-2">
                  <Camera className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Locations</h3>
                </div>

                <div className="space-y-2">
                  {/* Location List - Compact One-Liner View */}
                  {(formData.setting?.locations || []).length > 0 &&
                    editingLocationIndex === null && (
                      <div className="space-y-1.5">
                        {(() => {
                          const locations = formData.setting?.locations || [];
                          const shouldShowAll = locations.length <= 10 || showAllLocations;
                          const locationsToShow = shouldShowAll ? locations : locations.slice(0, 5);

                          return (
                            <>
                              {locationsToShow.map((location, index) => (
                                <div key={`location-compact-${index}`} className="relative">
                                  <button
                                    type="button"
                                    className="flex items-center gap-2 p-1.5 bg-muted/30 rounded-lg border border-border group hover:bg-muted/50 cursor-pointer transition-colors w-full text-left"
                                    onClick={() => setEditingLocationIndex(index)}
                                  >
                                    {/* Edit indicator */}
                                    <div className="pt-0.5 shrink-0">
                                      <Edit className="h-4 w-4 text-primary opacity-0 group-hover:opacity-100 transition-all duration-500" />
                                    </div>

                                    {/* Location Image - Super Small - Clickable for upload */}
                                    <div
                                      className="relative w-8 h-8 rounded overflow-hidden border border-border shrink-0 group/img cursor-pointer hover:ring-2 hover:ring-primary/50 transition-all"
                                      onClick={(e) => {
                                        e.stopPropagation();
                                        handleLocationMainImageClick(index);
                                      }}
                                      title={
                                        location.image
                                          ? "Click to replace image"
                                          : "Click to add image"
                                      }
                                    >
                                      {uploadingLocationIndex === index ? (
                                        <div className="w-full h-full flex items-center justify-center bg-muted">
                                          <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-primary" />
                                        </div>
                                      ) : location.image && formData.username ? (
                                        <>
                                          <OptimizedImage
                                            type="location"
                                            filename={location.image}
                                            username={formData.username}
                                            alt={location.name || "Location"}
                                            fill
                                            objectFit="cover"
                                          />
                                          <div className="absolute inset-0 bg-black/50 opacity-0 group-hover/img:opacity-100 transition-opacity flex items-center justify-center">
                                            <Camera className="h-3 w-3 text-white" />
                                          </div>
                                        </>
                                      ) : (
                                        <div className="w-full h-full flex items-center justify-center bg-muted group-hover/img:bg-primary/10 transition-colors">
                                          <Camera className="h-4 w-4 text-muted-foreground group-hover/img:text-primary transition-colors" />
                                        </div>
                                      )}
                                    </div>

                                    {/* Location Name */}
                                    <span className="font-medium text-sm shrink-0">
                                      {location.name || "Unnamed"}
                                    </span>

                                    {/* Location Description - Truncated */}
                                    <span className="text-xs text-muted-foreground truncate flex-1">
                                      {location.description || "No description"}
                                    </span>

                                    {/* Additional Images Count */}
                                    {(location.images?.length || 0) > 0 && (
                                      <span className="text-xs text-muted-foreground shrink-0">
                                        +{location.images?.length} img
                                      </span>
                                    )}
                                  </button>
                                  {/* Hidden file input for compact view upload */}
                                  <input
                                    ref={(el) => {
                                      locationFileInputRefs.current[index] = el;
                                    }}
                                    type="file"
                                    accept="image/*"
                                    onChange={(e) => handleLocationMainImageChange(e, index)}
                                    className="hidden"
                                    disabled={uploadingLocationIndex === index}
                                  />
                                </div>
                              ))}
                            </>
                          );
                        })()}
                      </div>
                    )}

                  {/* Location Edit Form - Expanded View */}
                  {editingLocationIndex !== null &&
                    formData.setting?.locations?.[editingLocationIndex] && (
                      <Card className="bg-muted/30 border-border">
                        <CardContent className="space-y-4">
                          <div className="flex items-center justify-between">
                            <h4 className="font-medium">Edit Location</h4>
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              onClick={() => {
                                setEditingLocationIndex(null);
                                setConfirmingLocationDelete(null);
                              }}
                              className="bg-transparent"
                            >
                              Done
                            </Button>
                          </div>

                          {/* Location Name */}
                          <div className="space-y-2">
                            <Label htmlFor={`location-name-alt-${editingLocationIndex}`}>
                              Name
                            </Label>
                            <Input
                              id={`location-name-alt-${editingLocationIndex}`}
                              placeholder="Enter location name"
                              value={formData.setting.locations[editingLocationIndex].name}
                              onChange={(e) =>
                                updateLocation(editingLocationIndex, "name", e.target.value)
                              }
                              className="bg-background"
                            />
                          </div>

                          {/* Location Main Image */}
                          <div className="space-y-2">
                            <Label>Main Image</Label>
                            <div className="relative w-full rounded-lg overflow-hidden border border-border bg-muted/30">
                              {locationPreviewImages[editingLocationIndex] ? (
                                <div className="relative group">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img
                                    src={locationPreviewImages[editingLocationIndex]}
                                    alt={
                                      formData.setting.locations[editingLocationIndex].name ||
                                      "Location"
                                    }
                                    className="w-full h-auto"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleLocationMainImageClick(editingLocationIndex)
                                    }
                                    disabled={uploadingLocationIndex === editingLocationIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload location main image"
                                  >
                                    {uploadingLocationIndex === editingLocationIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              ) : formData.setting.locations[editingLocationIndex].image &&
                                formData.username ? (
                                <div className="relative group">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img
                                    src={getImageUrl({
                                      type: "location",
                                      filename:
                                        formData.setting.locations[editingLocationIndex].image!,
                                      username: formData.username,
                                    })}
                                    alt={
                                      formData.setting.locations[editingLocationIndex].name ||
                                      "Location"
                                    }
                                    className="w-full h-auto"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleLocationMainImageClick(editingLocationIndex)
                                    }
                                    disabled={uploadingLocationIndex === editingLocationIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload location main image"
                                  >
                                    {uploadingLocationIndex === editingLocationIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              ) : (
                                <div className="w-full min-h-[200px] flex items-center justify-center relative group">
                                  <Camera className="h-12 w-12 text-muted-foreground" />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      handleLocationMainImageClick(editingLocationIndex)
                                    }
                                    disabled={uploadingLocationIndex === editingLocationIndex}
                                    className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                    aria-label="Upload location main image"
                                  >
                                    {uploadingLocationIndex === editingLocationIndex ? (
                                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                                    ) : (
                                      <Camera className="h-8 w-8 text-white" />
                                    )}
                                  </button>
                                </div>
                              )}
                            </div>
                            <input
                              ref={(el) => {
                                locationFileInputRefs.current[editingLocationIndex] = el;
                              }}
                              type="file"
                              accept="image/*"
                              onChange={(e) =>
                                handleLocationMainImageChange(e, editingLocationIndex)
                              }
                              className="hidden"
                              disabled={uploadingLocationIndex === editingLocationIndex}
                            />
                          </div>

                          {/* Additional Location Images */}
                          <div className="space-y-2">
                            <Label>Additional Images (Different Angles/Variations)</Label>
                            <div className="columns-2 md:columns-3 gap-4">
                              {(formData.setting.locations[editingLocationIndex].images || []).map(
                                (image, imageIndex) => (
                                  <div
                                    key={`${editingLocationIndex}-${imageIndex}`}
                                    className="relative w-full mb-4 break-inside-avoid rounded-lg overflow-hidden border border-border bg-muted/30"
                                  >
                                    {locationAdditionalPreviewImages[editingLocationIndex]?.[
                                      imageIndex
                                    ] ? (
                                      <div className="relative group">
                                        {/* eslint-disable-next-line @next/next/no-img-element */}
                                        <img
                                          src={
                                            locationAdditionalPreviewImages[editingLocationIndex][
                                              imageIndex
                                            ]
                                          }
                                          alt={`${formData.setting?.locations?.[editingLocationIndex]?.name || "Location"} - ${imageIndex + 1}`}
                                          className="w-full h-auto"
                                        />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleLocationAdditionalImageClick(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingLocationAdditionalIndex?.locationIndex ===
                                              editingLocationIndex &&
                                            uploadingLocationAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional location image ${imageIndex + 1}`}
                                        >
                                          {uploadingLocationAdditionalIndex?.locationIndex ===
                                            editingLocationIndex &&
                                          uploadingLocationAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                        <button
                                          type="button"
                                          onClick={() =>
                                            removeLocationAdditionalImage(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          className="absolute top-1 right-1 bg-destructive text-destructive-foreground rounded-full p-1 opacity-75 hover:opacity-100 transition-opacity z-10"
                                          aria-label={`Remove image ${imageIndex + 1}`}
                                        >
                                          <X className="h-3 w-3" />
                                        </button>
                                      </div>
                                    ) : image && formData.username ? (
                                      <div className="relative group">
                                        {/* eslint-disable-next-line @next/next/no-img-element */}
                                        <img
                                          src={getImageUrl({
                                            type: "location",
                                            filename: image,
                                            username: formData.username,
                                          })}
                                          alt={`${formData.setting?.locations?.[editingLocationIndex]?.name || "Location"} - ${imageIndex + 1}`}
                                          className="w-full h-auto"
                                        />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleLocationAdditionalImageClick(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingLocationAdditionalIndex?.locationIndex ===
                                              editingLocationIndex &&
                                            uploadingLocationAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional location image ${imageIndex + 1}`}
                                        >
                                          {uploadingLocationAdditionalIndex?.locationIndex ===
                                            editingLocationIndex &&
                                          uploadingLocationAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                        <button
                                          type="button"
                                          onClick={() =>
                                            removeLocationAdditionalImage(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          className="absolute top-1 right-1 bg-destructive text-destructive-foreground rounded-full p-1 opacity-75 hover:opacity-100 transition-opacity z-10"
                                          aria-label={`Remove image ${imageIndex + 1}`}
                                        >
                                          <X className="h-3 w-3" />
                                        </button>
                                      </div>
                                    ) : (
                                      <div className="w-full min-h-[150px] flex items-center justify-center relative group">
                                        <Camera className="h-8 w-8 text-muted-foreground" />
                                        <button
                                          type="button"
                                          onClick={() =>
                                            handleLocationAdditionalImageClick(
                                              editingLocationIndex,
                                              imageIndex
                                            )
                                          }
                                          disabled={
                                            uploadingLocationAdditionalIndex?.locationIndex ===
                                              editingLocationIndex &&
                                            uploadingLocationAdditionalIndex?.imageIndex ===
                                              imageIndex
                                          }
                                          className="absolute inset-0 flex items-center justify-center bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                                          aria-label={`Upload additional location image ${imageIndex + 1}`}
                                        >
                                          {uploadingLocationAdditionalIndex?.locationIndex ===
                                            editingLocationIndex &&
                                          uploadingLocationAdditionalIndex?.imageIndex ===
                                            imageIndex ? (
                                            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-white" />
                                          ) : (
                                            <Camera className="h-6 w-6 text-white" />
                                          )}
                                        </button>
                                      </div>
                                    )}
                                    <input
                                      ref={(el) => {
                                        locationAdditionalFileInputRefs.current[
                                          `${editingLocationIndex}-${imageIndex}`
                                        ] = el;
                                      }}
                                      type="file"
                                      accept="image/*"
                                      onChange={(e) =>
                                        handleLocationAdditionalImageChange(
                                          e,
                                          editingLocationIndex,
                                          imageIndex
                                        )
                                      }
                                      className="hidden"
                                      disabled={
                                        uploadingLocationAdditionalIndex?.locationIndex ===
                                          editingLocationIndex &&
                                        uploadingLocationAdditionalIndex?.imageIndex === imageIndex
                                      }
                                    />
                                  </div>
                                )
                              )}
                              <div className="relative w-full mb-4 break-inside-avoid">
                                <button
                                  type="button"
                                  onClick={() =>
                                    handleAddLocationAdditionalImageClick(editingLocationIndex)
                                  }
                                  className="relative w-full min-h-[150px] rounded-lg border-2 border-dashed border-border bg-muted/30 hover:bg-muted/50 transition-colors flex items-center justify-center"
                                  aria-label="Add additional location image"
                                >
                                  <Plus className="h-8 w-8 text-muted-foreground" />
                                  <input
                                    ref={(el) => {
                                      locationAddImageInputRefs.current[editingLocationIndex] = el;
                                    }}
                                    type="file"
                                    accept="image/*"
                                    onChange={(e) =>
                                      handleAddLocationAdditionalImageChange(
                                        e,
                                        editingLocationIndex
                                      )
                                    }
                                    className="hidden"
                                    disabled={
                                      uploadingLocationAdditionalIndex?.locationIndex ===
                                      editingLocationIndex
                                    }
                                  />
                                </button>
                              </div>
                            </div>
                          </div>

                          {/* Location Description */}
                          <div className="space-y-2">
                            <Label htmlFor={`location-description-alt-${editingLocationIndex}`}>
                              Description
                            </Label>
                            <Textarea
                              id={`location-description-alt-${editingLocationIndex}`}
                              placeholder="Describe this location..."
                              value={formData.setting.locations[editingLocationIndex].description}
                              onChange={(e) =>
                                updateLocation(editingLocationIndex, "description", e.target.value)
                              }
                              rows={3}
                              className="bg-background resize-none"
                            />
                          </div>

                          <div className="space-y-2">
                            <Label htmlFor={`location-story-purpose-${editingLocationIndex}`}>
                              Story Purpose
                            </Label>
                            <Input
                              id={`location-story-purpose-${editingLocationIndex}`}
                              placeholder="How this location functions in the story..."
                              value={
                                formData.setting.locations[editingLocationIndex].storyPurpose || ""
                              }
                              onChange={(e) =>
                                updateLocation(
                                  editingLocationIndex,
                                  "storyPurpose",
                                  e.target.value
                                )
                              }
                              className="bg-background"
                            />
                          </div>

                          <div className="space-y-2">
                            <Label htmlFor={`location-visual-prompt-${editingLocationIndex}`}>
                              Visual Prompt Notes
                            </Label>
                            <Textarea
                              id={`location-visual-prompt-${editingLocationIndex}`}
                              placeholder="Prompt notes for consistent location imagery..."
                              value={
                                formData.setting.locations[editingLocationIndex].visualPrompt || ""
                              }
                              onChange={(e) =>
                                updateLocation(
                                  editingLocationIndex,
                                  "visualPrompt",
                                  e.target.value
                                )
                              }
                              rows={3}
                              className="bg-background resize-none"
                            />
                          </div>

                          {/* Delete Location Button */}
                          <div className="pt-4 flex justify-end">
                            {confirmingLocationDelete === editingLocationIndex ? (
                              <div className="space-y-3 text-right">
                                <p className="text-sm text-muted-foreground">
                                  Are you sure you want to delete this location? This action cannot
                                  be undone.
                                </p>
                                <div className="flex items-center justify-end gap-2">
                                  <Button
                                    type="button"
                                    variant="destructive"
                                    size="sm"
                                    onClick={() => {
                                      removeLocation(editingLocationIndex);
                                      setEditingLocationIndex(null);
                                      setConfirmingLocationDelete(null);
                                    }}
                                  >
                                    <Trash className="h-4 w-4 mr-2" />
                                    Delete Location
                                  </Button>
                                  <Button
                                    type="button"
                                    variant="outline"
                                    size="sm"
                                    onClick={() => setConfirmingLocationDelete(null)}
                                    className="bg-transparent"
                                  >
                                    Cancel
                                  </Button>
                                </div>
                              </div>
                            ) : (
                              <Button
                                type="button"
                                variant="ghost"
                                size="sm"
                                onClick={() => setConfirmingLocationDelete(editingLocationIndex)}
                                className="text-xs text-destructive hover:text-destructive hover:bg-destructive/10"
                              >
                                <X className="h-2 w-2 mr-2" />
                                Delete Location
                              </Button>
                            )}
                          </div>
                        </CardContent>
                      </Card>
                    )}

                  <div className="flex gap-2 flex-wrap items-center">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={addLocation}
                      className="bg-transparent"
                    >
                      <Plus className="h-4 w-4 mr-2" />
                      Add Location
                    </Button>
                    {formData.screenplayText?.trim() && (
                      <Button
                        type="button"
                        variant="outline"
                        onClick={handleExtractLocations}
                        disabled={isExtractingLocations}
                        className="bg-transparent"
                      >
                        {isExtractingLocations ? (
                          <>
                            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                            Extracting...
                          </>
                        ) : (
                          <>
                            <Film className="h-4 w-4 mr-2" />
                            Extract from Screenplay
                          </>
                        )}
                      </Button>
                    )}
                    {(formData.setting?.locations?.length || 0) > 10 && (
                      <>
                        <div className="flex-1" />
                        <button
                          type="button"
                          onClick={() => {
                            const wasShowingAll = showAllLocations;
                            setShowAllLocations(!showAllLocations);
                            if (wasShowingAll) {
                              setTimeout(() => {
                                locationsSectionRef.current?.scrollIntoView({
                                  behavior: "smooth",
                                  block: "start",
                                });
                              }, 0);
                            }
                          }}
                          className="text-sm text-muted-foreground hover:text-foreground flex items-center gap-1 transition-colors"
                        >
                          <ChevronsDown
                            className={cn(
                              "h-4 w-4 transition-transform duration-300",
                              showAllLocations ? "rotate-180" : ""
                            )}
                          />
                          {showAllLocations
                            ? "Show Less"
                            : `Show All (${formData.setting?.locations?.length})`}
                        </button>
                      </>
                    )}
                  </div>
                </div>
              </div>

              {/* Scenes Section */}
              <div className="space-y-4 pt-4 border-t border-border">
                <div className="flex items-center gap-2">
                  <Clapperboard className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Scenes</h3>
                </div>
                <p className="text-sm text-muted-foreground">
                  Add scenes to your project. Each scene can carry screenplay context, characters,
                  reference assets, and prompt-ready shot breakdowns.
                </p>

                <SceneList
                  projectId={effectiveProjectId}
                  scenes={formData.scenes || []}
                  characters={formData.characters || []}
                  locations={formData.setting?.locations || []}
                  screenplayText={formData.screenplayText}
                  onScenesChange={(scenes) => setFormData({ ...formData, scenes })}
                />
              </div>

              {/* Full Width Sections - Links, Tools */}
              <div className="space-y-4 pt-4 border-t border-border">
                <div className="flex items-center gap-2">
                  <LinkIcon className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Project Links</h3>
                </div>
                <p className="text-sm text-muted-foreground">
                  Add links to your project (YouTube, Vimeo, Instagram, etc.)
                </p>

                <div className="space-y-3">
                  {formData.links.links.map((link, index) => (
                    <div
                      key={`${link.label}-${link.url}-${index}`}
                      className="flex items-center gap-2 p-3 bg-muted/30 rounded-md"
                    >
                      <div className="flex-1">
                        <p className="text-sm font-medium">{link.label}</p>
                        <p className="text-xs text-muted-foreground truncate">{link.url}</p>
                      </div>
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={() => removeLink(index)}
                        className="text-destructive hover:text-destructive"
                      >
                        <X className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}

                  <div className="flex gap-2">
                    <Input
                      placeholder="Enter URL (e.g., https://youtube.com/watch?v=...)"
                      value={newLinkUrl}
                      onChange={(e) => setNewLinkUrl(e.target.value)}
                      onKeyPress={(e) => {
                        if (e.key === "Enter") {
                          e.preventDefault();
                          addLink();
                        }
                      }}
                      className="bg-background"
                    />
                    <Button
                      type="button"
                      variant="outline"
                      onClick={addLink}
                      className="bg-transparent"
                    >
                      <Plus className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </div>

              <div className="space-y-4 pt-4 border-t border-border">
                <div className="flex items-center gap-2">
                  <Wrench className="h-5 w-5 text-primary" />
                  <h3 className="text-lg font-semibold">Tools</h3>
                </div>
                <p className="text-sm text-muted-foreground">
                  Add the tools you used, organized by category
                </p>

                {/* Add tools by category */}
                <div className="space-y-4">
                  {(["video", "image", "sound", "other"] as ToolCategory[]).map((category) => {
                    const toolsInCategory = getToolsByCategory(category);
                    return (
                      <div key={category} className="space-y-2">
                        <Label htmlFor={`tool-${category}`}>
                          {getCategoryLabel(category)}
                          {category === "video" && !hasVideoTool && (
                            <span className="text-destructive ml-1">*</span>
                          )}
                        </Label>
                        {/* Display added tools for this category */}
                        {toolsInCategory.length > 0 && (
                          <div className="flex flex-wrap gap-2">
                            {toolsInCategory.map((tool, _index) => {
                              const globalIndex = formData.tools.indexOf(tool);
                              return (
                                <div
                                  key={`${category}-${tool.name}-${globalIndex}`}
                                  className="flex items-center gap-2 px-3 py-1.5 bg-primary/10 text-primary rounded-full text-sm"
                                >
                                  <span>{tool.name}</span>
                                  <button
                                    type="button"
                                    onClick={() => removeTool(globalIndex)}
                                    className="hover:text-primary/70 transition-colors"
                                  >
                                    <X className="h-3 w-3" />
                                  </button>
                                </div>
                              );
                            })}
                          </div>
                        )}
                        <div className="space-y-2">
                          <Select
                            value={selectedTool[category]}
                            onValueChange={(value) => {
                              setSelectedTool({ ...selectedTool, [category]: value });
                              if (value !== "Other") {
                                // Auto-add tool when selected (not "Other")
                                addTool(category, value);
                              } else {
                                setCustomToolInput({ ...customToolInput, [category]: "" });
                              }
                            }}
                            key={`tool-select-${category}`}
                          >
                            <SelectTrigger id={toolSelectIds[category]} className="w-full bg-background">
                              <SelectValue
                                placeholder={`Add ${getCategoryLabel(category).toLowerCase()} tool...`}
                              />
                            </SelectTrigger>
                            <SelectContent>
                              {COMMON_TOOLS[category].map((tool) => (
                                <SelectItem key={tool} value={tool}>
                                  {tool}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                          {selectedTool[category] === "Other" && (
                            <div className="flex gap-2">
                              <Input
                                placeholder="Enter custom tool"
                                value={customToolInput[category]}
                                onChange={(e) =>
                                  setCustomToolInput({
                                    ...customToolInput,
                                    [category]: e.target.value,
                                  })
                                }
                                onKeyPress={(e) => {
                                  if (e.key === "Enter") {
                                    e.preventDefault();
                                    addTool(category);
                                  }
                                }}
                                className="flex-1 bg-background"
                              />
                              <Button
                                type="button"
                                variant="outline"
                                onClick={() => addTool(category)}
                                disabled={!customToolInput[category].trim()}
                                className="bg-transparent"
                              >
                                <Plus className="h-4 w-4" />
                              </Button>
                            </div>
                          )}
                        </div>
                        {category === "video" && !hasVideoTool && (
                          <p className="text-xs text-destructive pb-2">
                            * At least one Video Generation tool is required
                          </p>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            </>
          )}

          {/* Only show Create button for new projects - editing uses auto-save */}
          {!isEditing && (
            <div className={useGridLayout ? "col-span-3 flex gap-3 pt-4" : "flex gap-3 pt-4"}>
              <Button
                type="submit"
                className="flex-1 bg-primary text-primary-foreground hover:bg-primary/90"
                disabled={isSubmitting}
              >
                {isSubmitting ? "Creating..." : "Create Project"}
              </Button>
              <Button
                type="button"
                onClick={handleCancel}
                variant="outline"
                className="flex-1 bg-transparent"
                disabled={isSubmitting}
              >
                Cancel
              </Button>
            </div>
          )}
          </div>
        </details>
        )}
      </div>
    </form>
  );
}
