declare module "fluent-ffmpeg" {
  interface FfmpegCommand {
    noVideo(): FfmpegCommand;
    audioCodec(codec: string): FfmpegCommand;
    audioBitrate(bitrate: number): FfmpegCommand;
    seekInput(time: number): FfmpegCommand;
    frames(count: number): FfmpegCommand;
    setStartTime(time: number): FfmpegCommand;
    setDuration(duration: number): FfmpegCommand;
    videoCodec(codec: string): FfmpegCommand;
    outputOptions(options: string[]): FfmpegCommand;
    output(outputPath: string): FfmpegCommand;
    on(event: "end", callback: () => void): FfmpegCommand;
    on(event: "error", callback: (err: Error) => void): FfmpegCommand;
    run(): void;
  }

  function ffmpeg(input: string): FfmpegCommand;

  export = ffmpeg;
}
