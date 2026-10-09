// XIOM -- xiom.ffmpeg: FFmpeg (libavcodec/libavformat/libavutil/libswresample)
// bindings via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DECISION (crypto/media sector, native lane 2026-10-09, BINDINGS-LANE.md
// §11): **system-library SKIP path only** -- no FFmpeg binaries or sources
// are vendored (LGPL policy, §4).  The loader resolves one release
// generation of the four shared libraries at runtime
// (avcodec/avformat/avutil/swresample) and the suite reports SKIP when none
// is present, so CI without FFmpeg stays green.  Local LGPL shared builds
// may be placed on PATH for present-path proof; hashes are recorded in
// SPEC.md as optional local samples (nothing committed).
//
// LGPL-safe surface: the probe only calls version/configuration/license
// entry points -- no codec, demuxer, or GPL-only feature dependency.
//
// All XIOM `unsafe`/`extern` live in this single module (G5); every call is
// an fn-pointer cast over `xiom.ffi.dl`.
//
// Classification:
//   FFMPEG_LOAD_ABSENT  -> no candidate generation resolved -> SKIP
//   FFMPEG_LOAD_ABI     -> a generation loaded but entry points are missing -> FAIL
//   FFMPEG_PROBE_FAILED -> API present but behaved unexpectedly -> FAIL
//
// G2 pin (SPEC.md): generation table + entry-point set + local samples.
// Coverage (pilot): av_version_info + the four library versions + the
// avcodec license/configuration evidence.  Decode/demux/transcode wrappers
// are Phase 2 (ROADMAP.md).

module xiom.ffmpeg

use xiom.ffi.dl;
use xiom.string;

// =========================================================================
// Identity and classification
// =========================================================================

pub const FFMPEG_LOAD_ABSENT: Int = 0;    // no candidate generation -> SKIP
pub const FFMPEG_LOAD_ABI: Int = 1;       // entry points missing -> FAIL
pub const FFMPEG_PROBE_FAILED: Int = 2;   // API behaved unexpectedly -> FAIL

pub type FfLoadError = {
  kind: Int;
  message: Str;
}

/// Capability report for one loaded FFmpeg generation.
pub type FfmpegInfo = {
  version_info: Str;         // av_version_info(), e.g. "6.1.1"
  avcodec_version: Int;      // packed major<<16 | minor<<8 | micro
  avformat_version: Int;
  avutil_version: Int;
  swresample_version: Int;
  license: Str;              // avcodec_license()
  gpl_enabled: Bool;         // "--enable-gpl" in avcodec_configuration()
}

/// One loaded FFmpeg generation: the four shared libraries + resolved
/// entry points.  Owned by the caller; release with `ffmpeg_close`.
pub type FfmpegLibrary = {
  h_codec: Int;
  h_format: Int;
  h_util: Int;
  h_swr: Int;
  soname_codec: Str;
  soname_format: Str;
  soname_util: Str;
  soname_swr: Str;
  p_codec_version: Int;
  p_codec_configuration: Int;
  p_codec_license: Int;
  p_format_version: Int;
  p_util_version: Int;
  p_version_info: Int;
  p_swr_version: Int;
}

// =========================================================================
// Loader (one release generation = four sonames)
// =========================================================================

fn try_load_generation(soname_codec: Str, soname_format: Str, soname_util: Str, soname_swr: Str) -> Result[FfmpegLibrary, FfLoadError]
  requires: soname_codec.len() > 0
  requires: soname_format.len() > 0
  requires: soname_util.len() > 0
  requires: soname_swr.len() > 0
{
  let r_codec = dl.dl_open(soname_codec);
  if !r_codec.is_ok {
    // Not this generation: report ABSENT so the caller can try the next one.
    return Err(FfLoadError{ kind: FFMPEG_LOAD_ABSENT; message: soname_codec + ": " + r_codec.error });
  }
  let h_codec: Int = r_codec.value;

  let r_format = dl.dl_open(soname_format);
  if !r_format.is_ok {
    var ig1 = dl.dl_close(h_codec);
    return Err(FfLoadError{ kind: FFMPEG_LOAD_ABSENT; message: soname_format + ": " + r_format.error });
  }
  let h_format: Int = r_format.value;

  let r_util = dl.dl_open(soname_util);
  if !r_util.is_ok {
    var ig2 = dl.dl_close(h_codec);
    var ig3 = dl.dl_close(h_format);
    return Err(FfLoadError{ kind: FFMPEG_LOAD_ABSENT; message: soname_util + ": " + r_util.error });
  }
  let h_util: Int = r_util.value;

  let r_swr = dl.dl_open(soname_swr);
  if !r_swr.is_ok {
    var ig4 = dl.dl_close(h_codec);
    var ig5 = dl.dl_close(h_format);
    var ig6 = dl.dl_close(h_util);
    return Err(FfLoadError{ kind: FFMPEG_LOAD_ABSENT; message: soname_swr + ": " + r_swr.error });
  }
  let h_swr: Int = r_swr.value;

  let s1 = dl.dl_sym(h_codec, "avcodec_version");
  if !s1.is_ok { var c1 = dl.dl_close(h_codec); var c2 = dl.dl_close(h_format); var c3 = dl.dl_close(h_util); var c4 = dl.dl_close(h_swr); return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avcodec_version: " + s1.error }); }
  let s2 = dl.dl_sym(h_codec, "avcodec_configuration");
  if !s2.is_ok { var c5 = dl.dl_close(h_codec); var c6 = dl.dl_close(h_format); var c7 = dl.dl_close(h_util); var c8 = dl.dl_close(h_swr); return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avcodec_configuration: " + s2.error }); }
  let s3 = dl.dl_sym(h_codec, "avcodec_license");
  if !s3.is_ok { var c9 = dl.dl_close(h_codec); var c10 = dl.dl_close(h_format); var c11 = dl.dl_close(h_util); var c12 = dl.dl_close(h_swr); return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avcodec_license: " + s3.error }); }
  let s4 = dl.dl_sym(h_format, "avformat_version");
  if !s4.is_ok { var c13 = dl.dl_close(h_codec); var c14 = dl.dl_close(h_format); var c15 = dl.dl_close(h_util); var c16 = dl.dl_close(h_swr); return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avformat_version: " + s4.error }); }
  let s5 = dl.dl_sym(h_util, "avutil_version");
  if !s5.is_ok { var c17 = dl.dl_close(h_codec); var c18 = dl.dl_close(h_format); var c19 = dl.dl_close(h_util); var c20 = dl.dl_close(h_swr); return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avutil_version: " + s5.error }); }
  let s6 = dl.dl_sym(h_util, "av_version_info");
  if !s6.is_ok { var c21 = dl.dl_close(h_codec); var c22 = dl.dl_close(h_format); var c23 = dl.dl_close(h_util); var c24 = dl.dl_close(h_swr); return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "av_version_info: " + s6.error }); }
  let s7 = dl.dl_sym(h_swr, "swresample_version");
  if !s7.is_ok { var c25 = dl.dl_close(h_codec); var c26 = dl.dl_close(h_format); var c27 = dl.dl_close(h_util); var c28 = dl.dl_close(h_swr); return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "swresample_version: " + s7.error }); }

  return Ok(FfmpegLibrary{
    h_codec: h_codec;
    h_format: h_format;
    h_util: h_util;
    h_swr: h_swr;
    soname_codec: soname_codec;
    soname_format: soname_format;
    soname_util: soname_util;
    soname_swr: soname_swr;
    p_codec_version: s1.value;
    p_codec_configuration: s2.value;
    p_codec_license: s3.value;
    p_format_version: s4.value;
    p_util_version: s5.value;
    p_version_info: s6.value;
    p_swr_version: s7.value;
  });
}

/// Load an explicitly named generation (four sonames).  Bogus names exercise
/// the ABSENT/SKIP classification deterministically on any host.
/// Complexity: O(symbols).
pub fn ffmpeg_load_named(soname_codec: Str, soname_format: Str, soname_util: Str, soname_swr: Str) -> Result[FfmpegLibrary, FfLoadError]
  requires: soname_codec.len() > 0
  requires: soname_format.len() > 0
  requires: soname_util.len() > 0
  requires: soname_swr.len() > 0
{
  return try_load_generation(soname_codec, soname_format, soname_util, soname_swr);
}

/// Load the first available FFmpeg release generation from the common
/// Windows sonames (8.x .. 4.x).  A generation must resolve all four
/// libraries; a partially present generation is skipped.
/// Complexity: O(generations * symbols).
pub fn ffmpeg_load() -> Result[FfmpegLibrary, FfLoadError]
  requires: true
{
  let g1 = try_load_generation("avcodec-62.dll", "avformat-62.dll", "avutil-60.dll", "swresample-6.dll");
  if g1.is_ok { return Ok(g1.value); }
  if g1.error.kind == FFMPEG_LOAD_ABI { return Err(g1.error); }

  let g2 = try_load_generation("avcodec-61.dll", "avformat-61.dll", "avutil-59.dll", "swresample-5.dll");
  if g2.is_ok { return Ok(g2.value); }
  if g2.error.kind == FFMPEG_LOAD_ABI { return Err(g2.error); }

  let g3 = try_load_generation("avcodec-60.dll", "avformat-60.dll", "avutil-58.dll", "swresample-4.dll");
  if g3.is_ok { return Ok(g3.value); }
  if g3.error.kind == FFMPEG_LOAD_ABI { return Err(g3.error); }

  let g4 = try_load_generation("avcodec-59.dll", "avformat-59.dll", "avutil-57.dll", "swresample-4.dll");
  if g4.is_ok { return Ok(g4.value); }
  if g4.error.kind == FFMPEG_LOAD_ABI { return Err(g4.error); }

  let g5 = try_load_generation("avcodec-58.dll", "avformat-58.dll", "avutil-56.dll", "swresample-3.dll");
  if g5.is_ok { return Ok(g5.value); }
  if g5.error.kind == FFMPEG_LOAD_ABI { return Err(g5.error); }

  return Err(FfLoadError{
    kind: FFMPEG_LOAD_ABSENT;
    message: "ffmpeg: no shared-library generation resolved (tried avcodec 62/61/60/59/58)",
  });
}

/// Release the four library handles.
/// Complexity: O(1).
pub fn ffmpeg_close(lib: &FfmpegLibrary) -> Result[Unit, Str]
  requires: lib.h_codec != 0
{
  var first_err = "";
  let r1 = dl.dl_close(lib.h_codec);
  if !r1.is_ok { first_err = r1.error; }
  let r2 = dl.dl_close(lib.h_format);
  if !r2.is_ok { if first_err.len() == 0 { first_err = r2.error; } }
  let r3 = dl.dl_close(lib.h_util);
  if !r3.is_ok { if first_err.len() == 0 { first_err = r3.error; } }
  let r4 = dl.dl_close(lib.h_swr);
  if !r4.is_ok { if first_err.len() == 0 { first_err = r4.error; } }
  if first_err.len() > 0 { return Err(first_err); }
  return Ok(());
}

// =========================================================================
// Probe
// =========================================================================

/// Version + license/configuration evidence.  Only LGPL-safe entry points
/// are called; the license string and `--enable-gpl` presence are reported
/// as data (a GPL-configured host build is not an error -- the package does
/// not depend on any GPL-only feature).
/// Complexity: O(1).
pub fn ffmpeg_probe(lib: &FfmpegLibrary) -> Result[FfmpegInfo, Str]
  requires: lib.h_codec != 0
{
  unsafe {
    let f_version_info = lib.p_version_info as fn() -> *UInt8;
    let f_codec_version = lib.p_codec_version as fn() -> UInt32;
    let f_format_version = lib.p_format_version as fn() -> UInt32;
    let f_util_version = lib.p_util_version as fn() -> UInt32;
    let f_swr_version = lib.p_swr_version as fn() -> UInt32;
    let f_configuration = lib.p_codec_configuration as fn() -> *UInt8;
    let f_license = lib.p_codec_license as fn() -> *UInt8;

    var version_info = "";
    let vp = f_version_info();
    if (vp as Int) != 0 {
      version_info = Str::from_c_str(vp);
    }

    var license = "";
    let lp = f_license();
    if (lp as Int) != 0 {
      license = Str::from_c_str(lp);
    }

    var configuration = "";
    let cp = f_configuration();
    if (cp as Int) != 0 {
      configuration = Str::from_c_str(cp);
    }

    return Ok(FfmpegInfo{
      version_info: version_info;
      avcodec_version: f_codec_version() as Int;
      avformat_version: f_format_version() as Int;
      avutil_version: f_util_version() as Int;
      swresample_version: f_swr_version() as Int;
      license: license;
      gpl_enabled: str_contains(configuration, "--enable-gpl");
    });
  }
}

/// Decode a packed FFmpeg version (`major << 16 | minor << 8 | micro`).
/// Complexity: O(1).
pub fn ffmpeg_version_str(v: Int) -> Str
  requires: v >= 0
{
  let major = v >> 16;
  let minor = (v >> 8) & 255;
  let micro = v & 255;
  return fi_to_str(major) + "." + fi_to_str(minor) + "." + fi_to_str(micro);
}

/// Whether the loaded build reports an LGPL license string (probe evidence;
/// the package only depends on LGPL-safe APIs regardless of host build).
/// Complexity: O(1).
pub fn ffmpeg_lgpl_build(info: &FfmpegInfo) -> Bool
  requires: true
{
  return str_contains(info.license, "LGPL");
}

/// Load an explicitly named generation and run `ffmpeg_probe`.
/// Complexity: O(symbols + probe).
pub fn ffmpeg_probe_named(soname_codec: Str, soname_format: Str, soname_util: Str, soname_swr: Str) -> Result[FfmpegInfo, FfLoadError]
  requires: soname_codec.len() > 0
  requires: soname_format.len() > 0
  requires: soname_util.len() > 0
  requires: soname_swr.len() > 0
{
  let l = ffmpeg_load_named(soname_codec, soname_format, soname_util, soname_swr);
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: FfmpegLibrary = l.value;
  let p = ffmpeg_probe(&lib);
  let cl = ffmpeg_close(&lib);
  if !p.is_ok {
    return Err(FfLoadError{ kind: FFMPEG_PROBE_FAILED; message: p.error });
  }
  if !cl.is_ok {
    return Err(FfLoadError{ kind: FFMPEG_PROBE_FAILED; message: cl.error });
  }
  return Ok(p.value);
}

/// Probe the first available generation.
/// Complexity: O(generations * symbols + probe).
pub fn ffmpeg_probe_default() -> Result[FfmpegInfo, FfLoadError]
  requires: true
{
  let l = ffmpeg_load();
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: FfmpegLibrary = l.value;
  let p = ffmpeg_probe(&lib);
  let cl = ffmpeg_close(&lib);
  if !p.is_ok {
    return Err(FfLoadError{ kind: FFMPEG_PROBE_FAILED; message: p.error });
  }
  if !cl.is_ok {
    return Err(FfLoadError{ kind: FFMPEG_PROBE_FAILED; message: cl.error });
  }
  return Ok(p.value);
}

// =========================================================================
// Internals
// =========================================================================

fn fi_to_str(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  return buf;
}
