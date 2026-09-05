import { Edit, ExternalLink, Film, Plus } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import type { ProjectFormData } from "@/components/project-form";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { DashboardView } from "@/components/views/dashboard-view";
import type { Post } from "@/lib/posts";
import type { UserProfile } from "@/lib/profiles";

interface DashboardPageViewProps {
  userProfile: UserProfile;
  projects: (ProjectFormData & { id: string })[];
  postsByProject: Record<string, Post[]>;
}

export function DashboardPageView({
  userProfile,
  projects,
  postsByProject,
}: DashboardPageViewProps) {
  return (
    <div className="min-h-screen bg-background pt-24 pb-16">
      <div className="container mx-auto px-4 lg:px-8">
        <div className="grid md:grid-cols-3 lg:grid-cols-4 gap-8">
          {/* Profile Section */}
          <div className="col-span-1">
            <Card className="bg-card border-border">
              <CardContent>
                <div className="space-y-4">
                  <div className="flex justify-center">
                    <Image
                      src={userProfile.avatar || "/placeholder.svg"}
                      width={96}
                      height={96}
                      alt={userProfile.name}
                      className="h-24 w-24 rounded-full object-cover border-2 border-primary/20"
                    />
                  </div>
                  <div className="text-center">
                    <h3 className="text-xl font-bold">{userProfile.name}</h3>
                    <p className="text-sm text-muted-foreground">@{userProfile.username}</p>
                  </div>
                  <div className="space-y-3 pt-4">
                    <div>
                      <p className="text-xs text-muted-foreground mb-1">Email</p>
                      <p className="text-sm">{userProfile.email}</p>
                    </div>
                    {userProfile.about && (
                      <div>
                        <p className="text-xs text-muted-foreground mb-1">About</p>
                        <p className="text-sm leading-relaxed">{userProfile.about}</p>
                      </div>
                    )}
                    {userProfile.links.length > 0 && (
                      <div>
                        <p className="text-xs text-muted-foreground mb-1">Links</p>
                        <div className="space-y-2">
                          {userProfile.links.map((link, index) => (
                            <a
                              key={`${link.text}-${link.url}-${index}`}
                              href={link.url}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="flex items-center gap-2 text-sm text-primary hover:underline"
                            >
                              <ExternalLink className="h-3 w-3" />
                              {link.text}
                            </a>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                  <div className="pt-4 border-t">
                    <Link href="/dashboard/profile" className="w-full">
                      <Button
                        variant="ghost"
                        size="sm"
                        className="w-full justify-center text-muted-foreground hover:text-foreground"
                      >
                        <Edit className="h-4 w-4 mr-2" />
                        Edit Profile
                      </Button>
                    </Link>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>

          {/* Projects Section */}
          <div className="col-span-2 lg:col-span-3">
            <Card className="bg-card border-border">
              <CardHeader>
                <div className="flex items-center justify-between">
                  <div>
                    <CardTitle className="flex items-center gap-2">
                      <Film className="h-5 w-5 text-primary" />
                      My Projects
                    </CardTitle>
                    <CardDescription>
                      Manage concept-to-prompt development packages and publish finished phases when
                      ready
                    </CardDescription>
                  </div>
                  <Link href="/dashboard/projects/new">
                    <Button className="bg-primary text-primary-foreground hover:bg-primary/90">
                      <Plus className="h-4 w-4 mr-2" />
                      New Project
                    </Button>
                  </Link>
                </div>
              </CardHeader>
              <CardContent>
                {projects.length === 0 ? (
                  <div className="text-center py-12">
                    <Film className="h-12 w-12 text-primary opacity-50 mx-auto mb-2" />
                    <p className="text-primary mb-8">No projects yet</p>
                    <Link href="/dashboard/projects/new">
                      <Button className="bg-primary text-primary-foreground hover:bg-primary/90">
                        <Plus className="h-4 w-4 mr-2" />
                        Start Your First Development Package
                      </Button>
                    </Link>
                  </div>
                ) : (
                  <DashboardView
                    initialProjects={projects}
                    initialPostsByProject={postsByProject}
                  />
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
