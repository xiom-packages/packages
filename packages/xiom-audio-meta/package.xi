// XIOM -- xiom.audio-meta package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library modules import xiom.string and
// xiom.string.builder from it; the tests add xiom.test, xiom.io and
// xiom.string.
//
// Layout: one module per format family to keep every source file small:
//   xiom.audio_meta            MIDI (Standard MIDI File) + MOD (ProTracker)
//   xiom.audio_meta.trackers   XM, S3M, IT and NSF metadata parsers
//   xiom.audio_meta.chiptune   chiptune magic registry + detection

package xiom_audio_meta {
  name: "xiom.audio-meta";
  version: "0.1.0";
  description: "Chiptune/tracker module metadata: MIDI SMF, MOD, XM, S3M, IT and NSF structural parsers plus a chiptune magic registry (no audio rendering)";
  categories: ["media"];
  keywords: ["chiptune", "tracker", "midi", "mod", "xm", "s3m", "it", "nsf", "metadata", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.audio_meta", "xiom.audio_meta.chiptune", "xiom.audio_meta.trackers"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
