// XIOM -- xiom.video package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The core module imports xiom.string.builder from
// it; the tests additionally use xiom.test, xiom.io, xiom.string and
// xiom.string.compare.

package xiom_video {
  name: "xiom.video";
  version: "0.1.0";
  description: "Core video container abstractions: format-agnostic demux/mux, a minimal RIFF/AVI proof container (LIST/chunks, idx1 index, stream headers), a raw elementary-stream round-trip, magic sniffing for avi/mkv/mp4/ogg and integer timebase/frame math; payloads stay opaque (no codecs)";
  categories: ["media"];
  keywords: ["video", "container", "avi", "riff", "demux", "mux", "frame", "timebase", "sniff", "elementary-stream"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.video", "xiom.video.store", "xiom.video.avi", "xiom.video.raw", "xiom.video.container"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
