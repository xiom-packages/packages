// XIOM -- xiom.streaming package manifest
// Port task: promote the xiom.streaming placeholder to a real, tested,
// pure-XIOM package (RTP/RTCP/RTSP wire formats; WebRTC/RTMP/HLS/DASH out of
// scope and documented as such).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.convert from it; the tests additionally use xiom.test, xiom.io,
// xiom.string.compare and xiom.encoding.hex.

package xiom_streaming {
  name: "xiom.streaming";
  version: "0.1.0";
  description: "RTP/RTCP/RTSP wire-format codecs: header parse/build, wrap-safe sequence and timestamp arithmetic, interarrival jitter, report blocks, text messages";
  categories: ["media", "network"];
  keywords: ["rtp", "rtcp", "rtsp", "streaming", "jitter", "wire-format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.streaming"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
