import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  outputFileTracingRoot: path.join(__dirname, "../.."),
  turbopack: { root: path.join(__dirname, "../..") },
  images: {
    // Disable Vercel image optimization to avoid costs
    // Images will still benefit from lazy loading, responsive sizing, and layout shift prevention
    unoptimized: true,
    remotePatterns: [
      {
        protocol: "https",
        hostname: "aifilmcamp-public.s3.us-east-1.amazonaws.com",
      },
      {
        protocol: "https",
        hostname: "aifilmcamp-public.s3.amazonaws.com",
      },
      {
        protocol: "https",
        hostname: "img.clerk.com",
      },
      {
        protocol: "https",
        hostname: "*.cloudfront.net",
      },
    ],
  },
};

export default nextConfig;
