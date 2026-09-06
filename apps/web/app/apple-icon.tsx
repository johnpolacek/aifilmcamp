import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "#1F1A15",
      }}
    >
      <svg
        width="124"
        height="124"
        viewBox="0 0 24 24"
        fill="none"
        stroke="#FBBF24"
        strokeWidth="0.5"
        strokeLinecap="round"
        strokeLinejoin="round"
        role="img"
        aria-label="AI Film Camp"
      >
        {/* Custom flame adapted from Lucide Flame, ISC license; see public/brand/lucide-LICENSE.txt. */}
        <path d="M16 4.404A9.3 9.3 0 1 1 10 3.717" />
        <path d="M13.8 1.5C13.35 5.775 19.2 8.15 19.2 12.9C19.2 17.08 15.96 20.5 12 20.5C8.04 20.5 4.8 17.36 4.8 13.37C4.8 10.43 6.42 8.53 8.4 6.725C7.95 9.1 8.67 10.71 9.75 11.47C8.85 6.725 11.1 3.875 13.8 1.5Z" />
      </svg>
    </div>,
    size
  );
}
