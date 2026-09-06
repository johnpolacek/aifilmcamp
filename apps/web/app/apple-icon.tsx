import { ImageResponse } from "next/og";
import { BRAND_AMBER, BRAND_DARK, BRAND_MARK_PATH } from "@/lib/brand";

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
        background: BRAND_DARK,
      }}
    >
      <svg
        width="124"
        height="124"
        viewBox="0 0 24 24"
        fill={BRAND_AMBER}
        role="img"
        aria-label="AI Film Camp"
      >
        <path fillRule="evenodd" d={BRAND_MARK_PATH} />
      </svg>
    </div>,
    size
  );
}
