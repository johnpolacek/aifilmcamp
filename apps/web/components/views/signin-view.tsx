import { SignIn } from "@clerk/nextjs";

export function SignInView() {
  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-md space-y-8">
        {/* Clerk SignIn Component */}
        <div className="flex justify-center">
          <SignIn
            appearance={{
              elements: {
                rootBox: "w-full",
                card: "shadow-none border border-border bg-card",
              },
            }}
            routing="path"
            path="/signin"
            signUpUrl="/signup"
          />
        </div>
      </div>
    </div>
  );
}
