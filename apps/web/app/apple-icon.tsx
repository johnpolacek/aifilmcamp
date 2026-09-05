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
      <svg width="124" height="124" viewBox="0 0 100 100" role="img" aria-label="AI Film Camp">
        <path
          fill="#F59E0B"
          d="M50 8 A42 42 0 0 0 44 91.57 C40 83 41.5 73 45.5 65 C40.5 53 42 26 50 8 Z"
        />
        <path
          fill="#FFFFFF"
          d="M50 8 A42 42 0 0 1 56 91.57 C62 84 63 66 58 52 C54 40 51 24 50 8 Z"
        />
      </svg>
    </div>,
    size
  );
}
