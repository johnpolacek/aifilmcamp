import { auth } from "@clerk/nextjs/server";
import { NextResponse } from "next/server";
import { MACOS_APP_DOWNLOAD_URL } from "@/lib/tools";

// The download button links here rather than to the release asset directly so
// the file is only handed out to signed-in users. Signed-out visitors are sent
// to sign in and returned to this route, which then redirects to the asset.
export async function GET(request: Request) {
  const { userId } = await auth();
  if (!userId) {
    const signIn = new URL("/signin", request.url);
    signIn.searchParams.set("redirect_url", "/download/mac");
    return NextResponse.redirect(signIn);
  }
  return NextResponse.redirect(MACOS_APP_DOWNLOAD_URL);
}
