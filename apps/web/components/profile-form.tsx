"use client";

import { Camera, LinkIcon, Plus, User, X } from "lucide-react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ImagePlaceholder } from "@/components/ui/image-placeholder";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import type { UserProfile } from "@/lib/profiles";

interface ProfileFormProps {
  initialData: UserProfile;
  isRequired?: boolean;
}

export default function ProfileForm({ initialData, isRequired = false }: ProfileFormProps) {
  const router = useRouter();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [profile, setProfile] = useState<UserProfile>(initialData);
  const [newLink, setNewLink] = useState({ text: "", url: "" });
  const [isUploadingImage, setIsUploadingImage] = useState(false);
  const [previewImage, setPreviewImage] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    // Validate about field if required
    if (isRequired && (!profile.about || profile.about.trim() === "")) {
      toast.error("Please fill out the 'About' field to continue");
      return;
    }

    setIsSubmitting(true);

    const loadingToast = toast.loading("Updating profile...");

    try {
      const { updateUserProfile } = await import("@/lib/actions/profiles");
      await updateUserProfile(profile);

      toast.success("Profile updated successfully!", {
        id: loadingToast,
      });

      router.push("/dashboard");
    } catch (error) {
      console.error("Error updating profile:", error);
      const errorMessage = error instanceof Error ? error.message : "Failed to update profile";

      toast.error(errorMessage, {
        id: loadingToast,
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleCancel = () => {
    router.push("/dashboard");
  };

  const addLink = () => {
    if (newLink.text && newLink.url) {
      setProfile({
        ...profile,
        links: [...profile.links, newLink],
      });
      setNewLink({ text: "", url: "" });
    }
  };

  const removeLink = (index: number) => {
    setProfile({
      ...profile,
      links: profile.links.filter((_, i) => i !== index),
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

    // Validate file size (max 5MB)
    const maxSize = 5 * 1024 * 1024; // 5MB
    if (file.size > maxSize) {
      toast.error("Image must be less than 5MB");
      return;
    }

    // Create preview
    const reader = new FileReader();
    reader.onloadend = () => {
      setPreviewImage(reader.result as string);
    };
    reader.readAsDataURL(file);

    // Upload image
    setIsUploadingImage(true);
    const loadingToast = toast.loading("Uploading image...");

    try {
      const { uploadProfileImage } = await import("@/lib/actions/profiles");
      const formData = new FormData();
      formData.append("image", file);

      const result = await uploadProfileImage(formData);

      if (result.success && result.avatarUrl) {
        setProfile({
          ...profile,
          avatar: result.avatarUrl,
        });
        setPreviewImage(null);
        toast.success("Profile image updated!", {
          id: loadingToast,
        });
      }
    } catch (error) {
      console.error("Error uploading image:", error);
      const errorMessage = error instanceof Error ? error.message : "Failed to upload image";
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

  return (
    <form onSubmit={handleSubmit}>
      <Card className="bg-card border-border">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <User className="h-5 w-5 text-primary" />
            Profile Information
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-6">
            {/* Avatar Preview with Upload */}
            <div className="flex justify-center">
              <div className="relative group">
                {previewImage || profile.avatar ? (
                  <Image
                    src={(previewImage || profile.avatar) ?? ""}
                    alt={profile.name}
                    width={128}
                    height={128}
                    className="h-32 w-32 rounded-full object-cover border-4 border-primary/20"
                  />
                ) : (
                  <ImagePlaceholder variant="avatar" className="h-32 w-32" />
                )}
                <button
                  type="button"
                  onClick={handleImageClick}
                  disabled={isUploadingImage}
                  className="absolute inset-0 flex items-center justify-center rounded-full bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer disabled:cursor-not-allowed"
                  aria-label="Upload profile image"
                >
                  {isUploadingImage ? (
                    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                  ) : (
                    <div className="flex flex-col items-center gap-1">
                      <Camera className="h-8 w-8 text-white" />
                      <span className="text-xs text-white font-medium">Change Photo</span>
                    </div>
                  )}
                </button>
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
            <p className="text-xs text-center text-muted-foreground -mt-3">
              Click on your avatar to upload a new image (max 5MB)
            </p>

            {/* Form Fields */}
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="name">Full Name *</Label>
                <Input
                  id="name"
                  value={profile.name}
                  onChange={(e) => setProfile({ ...profile, name: e.target.value })}
                  className="bg-background"
                  placeholder="Your full name"
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="username">Username</Label>
                <Input id="username" value={profile.username} className="bg-muted" disabled />
                <p className="text-xs text-muted-foreground">
                  Your profile will be available at: /{profile.username}
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  type="email"
                  value={profile.email}
                  className="bg-muted"
                  disabled
                />
                <p className="text-xs text-muted-foreground">
                  Email is managed by your account settings
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="about">
                  About {isRequired && <span className="text-destructive">*</span>}
                </Label>
                <Textarea
                  id="about"
                  value={profile.about || ""}
                  onChange={(e) => setProfile({ ...profile, about: e.target.value })}
                  rows={4}
                  className="bg-background resize-none"
                  placeholder="Tell us about yourself and your filmmaking interests..."
                  maxLength={500}
                  required={isRequired}
                />
                <p className="text-xs text-muted-foreground">
                  {(profile.about || "").length} / 500 characters
                  {isRequired && (profile.about || "").length === 0 && (
                    <span className="text-destructive ml-2">• Required field</span>
                  )}
                </p>
              </div>
            </div>

            {/* Links Section */}
            <div className="space-y-4 pt-4 border-t border-border">
              <div className="flex items-center gap-2">
                <LinkIcon className="h-5 w-5 text-primary" />
                <h3 className="text-lg font-semibold">Your Links</h3>
              </div>

              <div className="space-y-3">
                {profile.links.map((link, index) => (
                  <div
                    key={`${link.text}-${link.url}-${index}`}
                    className="flex items-center gap-2 p-3 bg-muted/30 rounded-md"
                  >
                    <div className="flex-1">
                      <p className="text-sm font-medium">{link.text}</p>
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
                    placeholder="Link text (e.g., Portfolio)"
                    value={newLink.text}
                    onChange={(e) => setNewLink({ ...newLink, text: e.target.value })}
                    className="bg-background"
                  />
                  <Input
                    placeholder="URL"
                    value={newLink.url}
                    onChange={(e) => setNewLink({ ...newLink, url: e.target.value })}
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

            {/* Action Buttons */}
            <div className="flex gap-3 pt-4">
              <Button
                type="submit"
                className={isRequired ? "w-full" : "flex-1"}
                disabled={isSubmitting}
              >
                {isSubmitting ? "Saving..." : isRequired ? "Complete Profile" : "Save Changes"}
              </Button>
              {!isRequired && (
                <Button
                  type="button"
                  onClick={handleCancel}
                  variant="outline"
                  className="flex-1 bg-transparent"
                  disabled={isSubmitting}
                >
                  Cancel
                </Button>
              )}
            </div>
          </div>
        </CardContent>
      </Card>
    </form>
  );
}
