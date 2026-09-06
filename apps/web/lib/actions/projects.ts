"use server";

import { auth, currentUser } from "@clerk/nextjs/server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import type { ProjectFormData } from "@/components/project-form";
import { applyProjectBasics, type ProjectBasics } from "@/lib/project-basics";
import { deleteProject as deleteProjectFromS3, getProject, saveProject } from "@/lib/projects";
import {
  deleteObjectFromS3,
  getFileBufferFromS3,
  putObjectToS3,
  uploadFileFromBuffer,
} from "@/lib/s3";
import type { SourceDocumentKind } from "@/lib/types/development";

const MAX_PROJECT_FILE_SIZE = 50 * 1024 * 1024;

function sanitizeFilename(value: string) {
  return value.replace(/[^a-zA-Z0-9.-]/g, "_");
}

function normalizeExtractedText(value: string) {
  return value
    .replace(/\r\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function getSourceDocumentKey(projectId: string, filename: string) {
  return `projects/${projectId}/source/${filename}`;
}

function getSourceTextKey(projectId: string, filename: string) {
  return `projects/${projectId}/source/${filename}-extracted.txt`;
}

/**
 * Get the username from the current Clerk user
 */
async function getCurrentUsername(): Promise<string> {
  const user = await currentUser();

  if (!user) {
    throw new Error("User not found");
  }

  // Use Clerk username or email prefix as username
  return user.username || user.emailAddresses[0]?.emailAddress.split("@")[0] || user.id;
}

/** Save only the project's public-facing basics; retain all stored working material. */
export async function saveProjectBasics(input: ProjectBasics, projectId?: string) {
  const username = await getCurrentUsername();
  const existing = projectId ? await getProject(projectId) : null;
  if (projectId && (!existing || existing.username !== username)) {
    throw new Error("Project not found or you do not have permission to edit it.");
  }
  const id = projectId || `project-${crypto.randomUUID()}`;
  const base: ProjectFormData = existing || {
    title: "",
    logline: "",
    duration: "",
    genre: "",
    links: { links: [] },
    tools: [],
    username,
  };
  const project = applyProjectBasics(base, input);
  project.slug =
    existing?.slug ||
    `${
      project.title
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-|-$/g, "") || "film"
    }-${id.slice(-8)}`;
  await saveProject(id, project);
  revalidatePath("/dashboard");
  revalidatePath(`/dashboard/projects/${id}/edit`);
  revalidatePath(`/dashboard/projects/${id}/development`);
  revalidatePath(`/${username}/${project.slug}`);
  revalidatePath("/projects");
  return { success: true, projectId: id };
}

/**
 * Create a new project
 */
export async function createProject(data: ProjectFormData, providedProjectId?: string) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to create a project");
  }

  try {
    // Generate a unique project ID (slug or UUID)
    const projectId = providedProjectId || data.slug || `project-${Date.now()}`;

    // Add username to project data if not already set
    if (!data.username) {
      data.username = await getCurrentUsername();
    }

    // Save to S3
    await saveProject(projectId, data);

    // Revalidate the dashboard page
    revalidatePath("/dashboard");

    return { success: true, projectId };
  } catch (error) {
    console.error("Error creating project:", error);
    throw new Error("Failed to create project");
  }
}

/**
 * Update an existing project
 */
export async function updateProject(projectId: string, data: ProjectFormData) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to update a project");
  }

  try {
    // Check if project exists and user owns it
    const existingProject = await getProject(projectId);
    if (!existingProject) {
      throw new Error("Project not found");
    }

    // Check if user owns the project
    const currentUsername = await getCurrentUsername();
    if (existingProject.username !== currentUsername) {
      throw new Error("You don't have permission to update this project");
    }

    // Save to S3
    await saveProject(projectId, {
      ...existingProject,
      ...data,
      username: existingProject.username,
      slug: existingProject.slug,
    });

    revalidatePath(`/${currentUsername}/${existingProject.slug}`);
    revalidatePath("/projects");
    // Revalidate the dashboard and edit pages
    revalidatePath("/dashboard");
    revalidatePath(`/dashboard/projects/${projectId}/edit`);

    return { success: true };
  } catch (error) {
    console.error("Error updating project:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to update project");
  }
}

/**
 * Update just the screenplay text for a project
 * This is a simpler action for the screenplay editor
 * Optionally includes PDF file info when uploading a PDF
 */
export async function updateScreenplayText(
  projectId: string,
  screenplayText: string,
  pdfInfo?: {
    name: string;
    filename: string;
    size: number;
    type: string;
  }
): Promise<{ success: true } | { success: false; error: string }> {
  const { userId } = await auth();

  if (!userId) {
    return { success: false, error: "You must be signed in to update the screenplay" };
  }

  try {
    // Check if project exists and user owns it
    const existingProject = await getProject(projectId);
    if (!existingProject) {
      return { success: false, error: "Project not found" };
    }

    // Check if user owns the project
    const currentUsername = await getCurrentUsername();
    if (existingProject.username !== currentUsername) {
      return { success: false, error: "You don't have permission to update this project" };
    }

    // Update the screenplay text and optionally PDF info
    const updatedProject: ProjectFormData = {
      ...existingProject,
      screenplayText,
      ...(pdfInfo && { screenplay: pdfInfo }),
    };

    await saveProject(projectId, updatedProject);

    // Revalidate pages
    revalidatePath("/dashboard");
    revalidatePath(`/dashboard/projects/${projectId}/edit`);
    revalidatePath(`/dashboard/projects/${projectId}/screenplay`);

    return { success: true };
  } catch (error) {
    console.error("Error updating screenplay:", JSON.stringify(error, null, 2));
    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to update screenplay",
    };
  }
}

/**
 * Update screenplay elements (structured JSON format)
 * Also updates the plain text version for backwards compatibility
 */
export async function updateScreenplayElements(
  projectId: string,
  elements: Array<{ id: string; type: string; content: string }>
): Promise<{ success: true } | { success: false; error: string }> {
  const { userId } = await auth();

  if (!userId) {
    return { success: false, error: "You must be signed in to update the screenplay" };
  }

  try {
    // Check if project exists and user owns it
    const existingProject = await getProject(projectId);
    if (!existingProject) {
      return { success: false, error: "Project not found" };
    }

    // Check if user owns the project
    const currentUsername = await getCurrentUsername();
    if (existingProject.username !== currentUsername) {
      return { success: false, error: "You don't have permission to update this project" };
    }

    // Convert elements to plain text for backwards compatibility
    const { elementsToText } = await import("@/lib/screenplay-parser");
    const screenplayText = elementsToText(elements as Parameters<typeof elementsToText>[0]);

    // Update both elements and text
    const updatedProject: ProjectFormData = {
      ...existingProject,
      screenplayElements: elements as ProjectFormData["screenplayElements"],
      screenplayText,
    };

    await saveProject(projectId, updatedProject);

    // Revalidate pages
    revalidatePath("/dashboard");
    revalidatePath(`/dashboard/projects/${projectId}/edit`);
    revalidatePath(`/dashboard/projects/${projectId}/screenplay`);

    return { success: true };
  } catch (error) {
    console.error("Error updating screenplay elements:", JSON.stringify(error, null, 2));
    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to update screenplay",
    };
  }
}

/**
 * Delete a project
 */
export async function deleteProject(projectId: string) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to delete a project");
  }

  try {
    // Check if project exists and user owns it
    const existingProject = await getProject(projectId);
    if (!existingProject) {
      throw new Error("Project not found");
    }

    // Check if user owns the project
    const currentUsername = await getCurrentUsername();
    if (existingProject.username !== currentUsername) {
      throw new Error("You don't have permission to delete this project");
    }

    // Delete from S3
    await deleteProjectFromS3(projectId);
    revalidatePath("/projects");
    revalidatePath(`/${currentUsername}/${existingProject.slug}`);

    // Revalidate the dashboard page
    revalidatePath("/dashboard");

    return { success: true };
  } catch (error) {
    console.error("Error deleting project:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to delete project");
  }
}

/**
 * Publish a project (make it publicly shareable)
 */
export async function publishProject(projectId: string) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to publish a project");
  }

  try {
    // Check if project exists and user owns it
    const existingProject = await getProject(projectId);
    if (!existingProject) {
      throw new Error("Project not found");
    }

    // Check if user owns the project
    const currentUsername = await getCurrentUsername();
    if (existingProject.username !== currentUsername) {
      throw new Error("You don't have permission to publish this project");
    }

    // Update project with published status
    const updatedProject = {
      ...existingProject,
      isPublished: true,
      publishedAt: new Date().toISOString(),
    };

    await saveProject(projectId, updatedProject);

    // Revalidate pages
    revalidatePath("/dashboard");
    revalidatePath(`/${currentUsername}/${existingProject.slug}`);
    revalidatePath("/projects");

    return { success: true };
  } catch (error) {
    console.error("Error publishing project:", JSON.stringify({ projectId, error }, null, 2));
    throw new Error(error instanceof Error ? error.message : "Failed to publish project");
  }
}

/**
 * Unpublish a project
 */
export async function unpublishProject(projectId: string) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to unpublish a project");
  }

  try {
    // Check if project exists and user owns it
    const existingProject = await getProject(projectId);
    if (!existingProject) {
      throw new Error("Project not found");
    }

    // Check if user owns the project
    const currentUsername = await getCurrentUsername();
    if (existingProject.username !== currentUsername) {
      throw new Error("You don't have permission to unpublish this project");
    }

    // Update project with unpublished status
    const updatedProject = {
      ...existingProject,
      isPublished: false,
    };

    await saveProject(projectId, updatedProject);

    // Revalidate pages
    revalidatePath("/dashboard");
    revalidatePath(`/${currentUsername}/${existingProject.slug}`);
    revalidatePath("/projects");

    return { success: true };
  } catch (error) {
    console.error("Error unpublishing project:", JSON.stringify({ projectId, error }, null, 2));
    throw new Error(error instanceof Error ? error.message : "Failed to unpublish project");
  }
}

/**
 * Upload a project thumbnail image
 */
export async function uploadProjectThumbnail(formData: FormData) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to upload a thumbnail");
  }

  try {
    const username = await getCurrentUsername();
    const file = formData.get("image") as File;

    if (!file) {
      throw new Error("No image file provided");
    }

    // Validate file type
    if (!file.type.startsWith("image/")) {
      throw new Error("File must be an image");
    }

    // Validate file size (max 10MB for thumbnails)
    const maxSize = 10 * 1024 * 1024; // 10MB
    if (file.size > maxSize) {
      throw new Error("Image must be less than 10MB");
    }

    // Convert file to buffer
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    // Generate a unique filename (timestamp only)
    const timestamp = Date.now();
    const filename = `${timestamp}.jpg`;
    const key = `thumbnails/${username}/${filename}`;

    // Upload optimized image to S3
    const { uploadImageFromBuffer } = await import("@/lib/s3");
    await uploadImageFromBuffer(buffer, key, file.type, { isThumbnail: true });

    // Revalidate pages that show project data
    revalidatePath("/dashboard");

    // Return just the filename (not the full key or URL) - URL will be constructed when displaying
    return { success: true, thumbnailFilename: filename };
  } catch (error) {
    console.error("Error uploading project thumbnail:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to upload thumbnail");
  }
}

/**
 * Upload a character image
 */
export async function uploadCharacterImage(formData: FormData) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to upload a character image");
  }

  try {
    const username = await getCurrentUsername();
    const file = formData.get("image") as File;

    if (!file) {
      throw new Error("No image file provided");
    }

    // Validate file type
    if (!file.type.startsWith("image/")) {
      throw new Error("File must be an image");
    }

    // Validate file size (max 10MB for character images)
    const maxSize = 10 * 1024 * 1024; // 10MB
    if (file.size > maxSize) {
      throw new Error("Image must be less than 10MB");
    }

    // Convert file to buffer
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    // Generate a unique filename (timestamp + random to avoid collisions)
    const timestamp = Date.now();
    const random = Math.random().toString(36).substring(2, 9);
    const filename = `${timestamp}-${random}.jpg`;
    const key = `characters/${username}/${filename}`;

    // Upload optimized image to S3 (maintains original aspect ratio)
    const { uploadImageFromBuffer } = await import("@/lib/s3");
    await uploadImageFromBuffer(buffer, key, file.type);

    // Revalidate pages that show project data
    revalidatePath("/dashboard");

    // Return just the filename (not the full key or URL) - URL will be constructed when displaying
    return { success: true, imageFilename: filename };
  } catch (error) {
    console.error("Error uploading character image:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to upload character image");
  }
}

/**
 * Upload a location image
 */
export async function uploadLocationImage(formData: FormData) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to upload a location image");
  }

  try {
    const username = await getCurrentUsername();
    const file = formData.get("image") as File;

    if (!file) {
      throw new Error("No image file provided");
    }

    // Validate file type
    if (!file.type.startsWith("image/")) {
      throw new Error("File must be an image");
    }

    // Validate file size (max 10MB for location images)
    const maxSize = 10 * 1024 * 1024; // 10MB
    if (file.size > maxSize) {
      throw new Error("Image must be less than 10MB");
    }

    // Convert file to buffer
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    // Generate a unique filename (timestamp + random to avoid collisions)
    const timestamp = Date.now();
    const random = Math.random().toString(36).substring(2, 9);
    const filename = `${timestamp}-${random}.jpg`;
    const key = `locations/${username}/${filename}`;

    // Upload optimized image to S3 (using thumbnail optimization for location images)
    const { uploadImageFromBuffer } = await import("@/lib/s3");
    await uploadImageFromBuffer(buffer, key, file.type, { isThumbnail: true });

    // Revalidate pages that show project data
    revalidatePath("/dashboard");

    // Return just the filename (not the full key or URL) - URL will be constructed when displaying
    return { success: true, imageFilename: filename };
  } catch (error) {
    console.error("Error uploading location image:", error);
    throw new Error(error instanceof Error ? error.message : "Failed to upload location image");
  }
}

/**
 * Upload a project file (PDF, documents, etc.)
 * Optionally extracts text from PDF files
 */
export async function uploadProjectFile(
  formData: FormData,
  extractText: boolean = true
): Promise<
  | {
      success: true;
      filename: string;
      originalName: string;
      size: number;
      type: string;
      extractedText?: string;
      extractionError?: string;
    }
  | { success: false; error: string }
> {
  const { userId } = await auth();

  if (!userId) {
    return { success: false, error: "You must be signed in to upload a file" };
  }

  try {
    const username = await getCurrentUsername();
    const file = formData.get("file") as File;

    if (!file) {
      return { success: false, error: "No file provided" };
    }

    // Validate file size (max 50MB for project files)
    if (file.size > MAX_PROJECT_FILE_SIZE) {
      return { success: false, error: "File must be less than 50MB" };
    }

    // Convert file to buffer
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    // Generate a unique filename (timestamp + original filename sanitized)
    const timestamp = Date.now();
    const originalName = sanitizeFilename(file.name);
    const filename = `${timestamp}-${originalName}`;
    const key = `projects/${username}/files/${filename}`;

    // Upload file to S3
    await uploadFileFromBuffer(buffer, key, file.type || "application/octet-stream");

    // Revalidate pages that show project data
    revalidatePath("/dashboard");

    // Extract text from PDF if requested and file is a PDF
    let extractedText: string | undefined;
    let extractionError: string | undefined;
    if (
      extractText &&
      (file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf"))
    ) {
      const extractResult = await extractPdfText(buffer);
      if (extractResult.success) {
        extractedText = extractResult.text;
      } else {
        extractionError = extractResult.error;
        console.error(
          "[uploadProjectFile] PDF text extraction failed:",
          JSON.stringify(
            {
              filename: file.name,
              error: extractionError,
            },
            null,
            2
          )
        );
      }
    }

    // Return filename and metadata
    return {
      success: true,
      filename: filename,
      originalName: file.name,
      size: file.size,
      type: file.type || "application/octet-stream",
      ...(extractedText && { extractedText }),
      ...(extractionError && { extractionError }),
    };
  } catch (error) {
    console.error("Error uploading project file:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to upload file",
    };
  }
}

async function extractTextFromPdfBuffer(
  pdfBuffer: Buffer,
  options?: { stripToFirstSceneHeading?: boolean; filename?: string }
): Promise<{ success: true; text: string } | { success: false; error: string }> {
  try {
    const { PDFParse } = await import("pdf-parse");

    const parser = new PDFParse({
      data: new Uint8Array(pdfBuffer.buffer, pdfBuffer.byteOffset, pdfBuffer.byteLength),
    });

    const pdfData = await parser.getText().finally(() => parser.destroy());

    if (!pdfData?.text) {
      return {
        success: false,
        error: "Could not extract text from PDF. The PDF may be image-based or corrupted.",
      };
    }

    let extractedText = normalizeExtractedText(pdfData.text);
    if (!extractedText) {
      return {
        success: false,
        error:
          "PDF appears to be empty or contains only images. Text extraction requires a text-based PDF.",
      };
    }

    if (options?.stripToFirstSceneHeading) {
      const firstSceneMatch = extractedText.match(/^(INT\.|EXT\.)/im);
      if (firstSceneMatch && firstSceneMatch.index !== undefined && firstSceneMatch.index > 0) {
        extractedText = extractedText.substring(firstSceneMatch.index);
      }
    }

    console.log(
      "[extractTextFromPdfBuffer] Successfully extracted text:",
      JSON.stringify(
        {
          textLength: extractedText.length,
          pageCount: pdfData.total || 0,
          filename: options?.filename || "from buffer",
        },
        null,
        2
      )
    );

    return { success: true, text: extractedText };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to extract text from PDF",
    };
  }
}

async function extractTextFromDocxBuffer(
  buffer: Buffer
): Promise<{ success: true; text: string } | { success: false; error: string }> {
  try {
    const JSZip = (await import("jszip")).default;
    const zip = await JSZip.loadAsync(buffer);
    const documentXml = await zip.file("word/document.xml")?.async("string");

    if (!documentXml) {
      return { success: false, error: "DOCX file is missing document content." };
    }

    const text = normalizeExtractedText(
      documentXml
        .replace(/<w:p[^>]*>/g, "\n")
        .replace(/<w:tab\/>/g, "\t")
        .replace(/<w:br\/>/g, "\n")
        .replace(/<w:cr\/>/g, "\n")
        .replace(/<[^>]+>/g, " ")
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
    );

    if (!text) {
      return { success: false, error: "DOCX file appears to be empty." };
    }

    return { success: true, text };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to extract text from DOCX",
    };
  }
}

async function extractTextFromSourceFile(
  buffer: Buffer,
  file: { name: string; type?: string }
): Promise<
  { success: true; text: string; kind: SourceDocumentKind } | { success: false; error: string }
> {
  const lowerName = file.name.toLowerCase();
  if (file.type === "application/pdf" || lowerName.endsWith(".pdf")) {
    const result = await extractTextFromPdfBuffer(buffer, { filename: file.name });
    return result.success ? { ...result, kind: "pdf" } : result;
  }

  if (
    file.type === "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
    lowerName.endsWith(".docx")
  ) {
    const result = await extractTextFromDocxBuffer(buffer);
    return result.success ? { ...result, kind: "docx" } : result;
  }

  if (file.type === "text/plain" || lowerName.endsWith(".txt")) {
    return {
      success: true,
      text: normalizeExtractedText(buffer.toString("utf8")),
      kind: "txt",
    };
  }

  if (
    file.type === "text/markdown" ||
    lowerName.endsWith(".md") ||
    lowerName.endsWith(".markdown")
  ) {
    return {
      success: true,
      text: normalizeExtractedText(buffer.toString("utf8")),
      kind: "md",
    };
  }

  return { success: false, error: "Unsupported file format. Use PDF, DOCX, TXT, or MD." };
}

export async function uploadSourceDocument(
  projectId: string,
  formData: FormData
): Promise<
  | {
      success: true;
      filename: string;
      originalName: string;
      size: number;
      type: string;
      sourceTextKey: string;
      sourceDocumentKind: SourceDocumentKind;
    }
  | { success: false; error: string }
> {
  const { userId } = await auth();
  if (!userId) {
    return { success: false, error: "You must be signed in to upload a file" };
  }

  try {
    const file = formData.get("file") as File;
    if (!file) {
      return { success: false, error: "No file provided" };
    }

    if (file.size > MAX_PROJECT_FILE_SIZE) {
      return { success: false, error: "File must be less than 50MB" };
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    const extracted = await extractTextFromSourceFile(buffer, file);
    if (!extracted.success) {
      return extracted;
    }

    const timestamp = Date.now();
    const filename = `${timestamp}-${sanitizeFilename(file.name)}`;
    const sourceKey = getSourceDocumentKey(projectId, filename);
    const sourceTextKey = getSourceTextKey(projectId, filename);

    await uploadFileFromBuffer(buffer, sourceKey, file.type || "application/octet-stream");
    await putObjectToS3(sourceTextKey, extracted.text, "text/plain; charset=utf-8");

    return {
      success: true,
      filename,
      originalName: file.name,
      size: file.size,
      type: file.type || "application/octet-stream",
      sourceTextKey,
      sourceDocumentKind: extracted.kind,
    };
  } catch (error) {
    console.error("Error uploading source document:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to upload source document",
    };
  }
}

export async function removeSourceDocument(
  projectId: string,
  filename?: string,
  sourceTextKey?: string
): Promise<{ success: true } | { success: false; error: string }> {
  const { userId } = await auth();
  if (!userId) {
    return { success: false, error: "You must be signed in to remove a source document" };
  }

  try {
    if (filename) {
      await deleteObjectFromS3(getSourceDocumentKey(projectId, filename));
    }
    if (sourceTextKey) {
      await deleteObjectFromS3(sourceTextKey);
    }
    return { success: true };
  } catch (error) {
    console.error("Error removing source document:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to remove source document",
    };
  }
}

/**
 * Extract text from a PDF file
 * Can extract from either a file buffer (during upload) or from S3 (existing file)
 */
export async function extractPdfText(
  fileBuffer?: Buffer,
  filename?: string,
  username?: string
): Promise<{ success: true; text: string } | { success: false; error: string }> {
  const { userId } = await auth();

  if (!userId) {
    return { success: false, error: "You must be signed in to extract PDF text" };
  }

  try {
    let pdfBuffer: Buffer;

    // Get PDF buffer from either provided buffer or S3
    if (fileBuffer) {
      pdfBuffer = fileBuffer;
    } else if (filename && username) {
      const key = `projects/${username}/files/${filename}`;
      const buffer = await getFileBufferFromS3(key);

      if (!buffer) {
        return { success: false, error: "PDF file not found in storage" };
      }
      pdfBuffer = buffer;
    } else {
      return {
        success: false,
        error: "Either file buffer or filename with username must be provided",
      };
    }
    return extractTextFromPdfBuffer(pdfBuffer, {
      stripToFirstSceneHeading: true,
      filename,
    });
  } catch (error) {
    console.error(
      "[extractPdfText] Error extracting PDF text:",
      JSON.stringify(
        {
          error: error instanceof Error ? error.message : String(error),
          filename: filename || "from buffer",
        },
        null,
        2
      )
    );

    // Provide helpful error messages
    if (error instanceof Error) {
      if (error.message.includes("Invalid PDF")) {
        return {
          success: false,
          error: "Invalid PDF file. Please ensure the file is a valid PDF.",
        };
      }
      if (error.message.includes("password")) {
        return {
          success: false,
          error: "PDF is password-protected. Please remove the password and try again.",
        };
      }
    }

    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to extract text from PDF",
    };
  }
}

/**
 * Submit project form (create or update based on context)
 */
export async function submitProjectForm(
  data: ProjectFormData,
  projectId?: string,
  redirectPath: string = "/dashboard",
  skipRedirect: boolean = false,
  createProjectId?: string
) {
  const { userId } = await auth();

  if (!userId) {
    throw new Error("You must be signed in to submit a project");
  }

  try {
    let resolvedProjectId = projectId;

    if (projectId) {
      // Update existing project
      await updateProject(projectId, data);
    } else {
      // Create new project
      const result = await createProject(data, createProjectId);
      resolvedProjectId = result.projectId;
    }

    // Skip redirect for auto-save
    if (skipRedirect) {
      return { success: true, projectId: resolvedProjectId };
    }

    // Redirect to success page
    redirect(redirectPath);
  } catch (error) {
    // Check if this is a Next.js redirect error - if so, re-throw it
    if (error && typeof error === "object" && "digest" in error) {
      const errorDigest = String(error.digest || "");
      if (errorDigest.includes("NEXT_REDIRECT")) {
        throw error; // Re-throw redirect errors to let Next.js handle them
      }
    }

    console.error("Error submitting project:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "Failed to save project",
    };
  }
}
