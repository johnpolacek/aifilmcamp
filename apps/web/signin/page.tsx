import type { Metadata } from "next";
import { SignInView } from "@/components/views/signin-view";

export const metadata: Metadata = {
  title: "Sign In - AI Film Camp",
  description: "Sign in to your AI Film Camp account",
};

export default function SignInPage() {
  return <SignInView />;
}
