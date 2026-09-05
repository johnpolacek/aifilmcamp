import type { Metadata } from "next";
import { SignUpView } from "@/components/views/signup-view";

export const metadata: Metadata = {
  title: "Sign Up - AI Film Camp",
  description: "Create your AI Film Camp account",
};

export default function SignUpPage() {
  return <SignUpView />;
}
