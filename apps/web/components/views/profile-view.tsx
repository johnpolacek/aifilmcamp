import { AlertCircle, ArrowLeft } from "lucide-react";
import Link from "next/link";
import ProfileForm from "@/components/profile-form";
import type { UserProfile } from "@/lib/profiles";

interface ProfileViewProps {
  userProfile: UserProfile;
  isRequired: boolean;
}

export function ProfileView({ userProfile, isRequired }: ProfileViewProps) {
  return (
    <div className="min-h-screen bg-background pt-24 pb-16">
      <div className="container mx-auto px-4 lg:px-8 max-w-2xl">
        {/* Header */}
        <div className="mb-8">
          {!isRequired && (
            <Link
              href="/dashboard"
              className="inline-flex items-center gap-2 text-primary mb-4 hover:opacity-80 transition-opacity"
            >
              <ArrowLeft className="h-4 w-4" />
              <span className="text-sm font-semibold">Back to Dashboard</span>
            </Link>
          )}
          <h1 className="text-4xl md:text-5xl font-bold mb-2">
            {isRequired ? "Complete Your Profile" : "Edit Profile"}
          </h1>
          <p className="text-lg text-muted-foreground">
            {isRequired
              ? "Please tell us about yourself before continuing"
              : "Update your personal information"}
          </p>
        </div>

        {/* Required Profile Notice */}
        {isRequired && (
          <div className="mb-6 p-4 rounded-lg border border-primary/20 bg-primary/5 flex items-start gap-3">
            <AlertCircle className="h-5 w-5 text-primary shrink-0 mt-0.5" />
            <div>
              <h3 className="font-semibold text-primary mb-1">Profile Completion Required</h3>
              <p className="text-sm text-muted-foreground">
                Before you can access your dashboard, please add a brief description about yourself
                in the &quot;About&quot; field below. This helps other filmmakers in the community
                get to know you!
              </p>
            </div>
          </div>
        )}

        <ProfileForm initialData={userProfile} isRequired={isRequired} />
      </div>
    </div>
  );
}
