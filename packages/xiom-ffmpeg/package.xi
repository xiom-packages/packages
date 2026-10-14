package xiom_ffmpeg {
  name: "xiom.ffmpeg";
  version: "0.4.1";
  description: "FFmpeg (libavcodec/libavformat/libavutil/libswresample) bindings for XIOM via dynamic loader (system-library SKIP path; LGPL-safe probe; AV1-class decode surface; container demux -- avformat open/close, stream enumeration, best-stream selection, packet read loop, seek)";
  categories: ["media"];
  keywords: ["ffmpeg", "video", "audio", "codecs", "av1", "demux", "container", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.ffmpeg"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
