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
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
        role="img"
        aria-label="AI Film Camp"
      >
        {/* Custom flame adapted from Lucide Flame, ISC license; see public/brand/lucide-LICENSE.txt. */}
        <path d="M14 2C13.5 6.5 20 9 20 14C20 18.4 16.4 22 12 22C7.6 22 4 18.7 4 14.5C4 11.4 5.8 9.4 8 7.5C7.5 10 8.3 11.7 9.5 12.5C8.5 7.5 11 4.5 14 2Z" />
      </svg>
    </div>,
    size
  );
}
