package xiom_ffmpeg {
  name: "xiom.ffmpeg";
  version: "0.2.0";
  description: "FFmpeg (libavcodec/libavformat/libavutil/libswresample) bindings for XIOM via dynamic loader (system-library SKIP path; LGPL-safe probe)";
  categories: ["media"];
  keywords: ["ffmpeg", "video", "audio", "codecs", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
