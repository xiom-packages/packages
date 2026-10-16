// XIOM -- MiniAudio Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.miniaudio"
  version: "0.4.0"
  description: "miniaudio bindings for XIOM (vendored 0.11.25 single header, no system library; version/context enumeration, decode/encode, live device lifecycle + playback engine + node graph/mixing + capture, streamed WAV/FLAC/MP3 decode)"
  categories: ["media"]
  keywords: ["miniaudio", "audio", "playback", "capture", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  modules: ["xiom.miniaudio"]
  deps: { "xiom.std": ">=0.60.0 <1.0.0" }
}
