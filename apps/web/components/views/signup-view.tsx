import { SignUp } from "@clerk/nextjs";

export function SignUpView() {
  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-md space-y-8 py-20">
        {/* Clerk SignUp Component */}
        <div className="flex justify-center">
          <SignUp
            appearance={{
              elements: {
                rootBox: "w-full",
                card: "shadow-none border border-border bg-card",
              },
            }}
            routing="path"
            path="/signup"
            signInUrl="/signin"
            fallbackRedirectUrl="/dashboard"
            forceRedirectUrl="/dashboard"
          />
        </div>
      </div>
    </div>
  );
}
