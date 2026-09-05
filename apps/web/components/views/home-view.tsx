"use client";

import Image from "next/image";
import { CallToAction } from "@/components/call-to-action";
import { CommunityFeatures } from "@/components/community-features";
// import { useEffect, useRef, useState } from "react"
import { Hero } from "@/components/hero";

export function HomeView() {
  // const videoRef = useRef<HTMLVideoElement>(null)
  // const [isLoaded, setIsLoaded] = useState(false)

  // useEffect(() => {
  //   const video = videoRef.current
  //   if (video) {
  //     video.playbackRate = 0.5
  //
  //     const handleLoadedData = () => {
  //       setIsLoaded(true)
  //     }
  //
  //     video.addEventListener("loadeddata", handleLoadedData)
  //
  //     return () => {
  //       video.removeEventListener("loadeddata", handleLoadedData)
  //     }
  //   }
  // }, [])

  return (
    <main className="min-h-screen relative">
      {/* Background video */}
      {/* <video
        ref={videoRef}
        autoPlay
        loop
        muted
        playsInline
        className={`fixed inset-0 w-full h-full object-cover -z-10 transition-opacity duration-1000 ${
          isLoaded ? "opacity-70" : "opacity-0"
        }`}
      >
        <source src="/aifilmcamp.mp4" type="video/mp4" />
      </video> */}

      {/* Background image */}
      <div className="fixed top-[25vh] left-0 right-0 bottom-0 -z-10">
        <div className="relative w-full h-full">
          <Image src="/aifilmcamp.png" alt="" fill className="object-cover" priority />
          {/* Gradient overlay from black to transparent */}
          <div
            className="absolute inset-0"
            style={{ background: "linear-gradient(to bottom, black 0%, transparent 33%)" }}
          />
        </div>
      </div>

      {/* Overlay for better content readability */}
      <div className="fixed inset-0 bg-background/50 -z-10" />

      {/* Content */}
      <div className="relative z-10">
        <Hero />
        <CommunityFeatures />
        <CallToAction />
      </div>
    </main>
  );
}
