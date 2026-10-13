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
//   FFMPEG_DECODER_ABSENT -> no usable AV1-class decoder -> SKIP (0.3.0)
//
// G2 pin (SPEC.md): generation table + entry-point set + local samples.
// Coverage (pilot): av_version_info + the four library versions + the
// avcodec license/configuration evidence.
//
// 0.3.0 (wave A3, REL-20261013-1926-packages): AV1-class video decode
// surface -- decoder discovery by name ("av1" native first, then the
// "libdav1d"/"libaom-av1" wrappers), codec-context open, a packet/frame
// lifecycle (alloc/unref/free + send/receive/flush) and frame
// width/height/AVPixelFormat read-out.  Container demux (avformat) stays
// out of scope for this wave (ROADMAP Phase 3).
//
// Decode FFI discipline (v0.64.4 findings B-20/B-24/B-25/B-17/B-23):
//   * handles cross as `Int` params in the fn-pointer casts (B-25: never
//     `Int as *UInt8`); `src/ffmpeg_bridge.c` casts in C only;
//   * out-params use one XIOM-owned slot each, read byte-indexed (B-17/B-24);
//   * the AVFrame head is copied by C into an owned slot -- XIOM never reads
//     through the foreign AVFrame pointer (B-20);
//   * nullable C args are Int `0` (B-23: never the bare `null` literal);
//   * no `Result[Option[T]]` shapes (B-26): flat outcome structs instead.
// The bridge is OUR code (compiled with `--c-source`, port.args.json); it
// never links FFmpeg -- the dynamic-loader model is unchanged.

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
// AV1-class decode surface (0.3.0, wave A3)
// =========================================================================

/// A loaded generation exposes no usable AV1-class decoder -> SKIP.
pub const FFMPEG_DECODER_ABSENT: Int = 3;

// Decode outcome kinds (flat, B-26).
pub const FFMPEG_DECODE_FRAME: Int = 0;  // a frame was produced
pub const FFMPEG_DECODE_AGAIN: Int = 1;  // needs more input (AVERROR(EAGAIN))
pub const FFMPEG_DECODE_EOF: Int = 2;    // drained (AVERROR_EOF)
pub const FFMPEG_DECODE_ERROR: Int = 3;  // any other return code

/// AVERROR(EAGAIN) on Windows builds (MSVCRT errno EAGAIN = 11; libavutil
/// error.h: AVERROR(e) = -e).  Complexity: O(1).
pub const FFMPEG_ERR_EAGAIN: Int = -11;

/// AVERROR_EOF = -MKTAG('E','O','F',' ') (libavutil/error.h FFERRTAG).
/// Complexity: O(1).
pub const FFMPEG_ERR_EOF: Int = -541478725;

/// AVERROR(ENOSYS) on Windows builds (MSVCRT errno ENOSYS = 40): what the
/// native `av1` decoder returns on the first packet when no hardware
/// accelerator is negotiated (libavcodec/av1dec.c: the software path is
/// hwaccel-only in the 6.x-8.x lineage).  Callers classify it as SKIP.
/// Complexity: O(1).
pub const FFMPEG_ERR_ENOSYS: Int = -40;

/// The AV1-class candidate names (name-level discovery set, in the order
/// documented by the wave): native libavcodec first, then the wrappers.
pub const FFMPEG_AV1_DECODERS: Str = "av1,libdav1d,libaom-av1";

/// Candidate preference for `ffmpeg_av1_decoder_open`: usable software
/// decoders first (see the rationale on that function).
pub const FFMPEG_AV1_SOFTWARE_ORDER: Str = "libdav1d,libaom-av1,av1";

/// An open AV1-class decoder: the AVCodecContext plus the resolved entry
/// points the decode loop needs.  Owned by the caller; release with
/// `ffmpeg_decoder_close`.  The owning `FfmpegLibrary` must outlive it.
pub type FfDecoder = {
  ctx: Int;
  codec: Int;
  codec_name: Str;
  h_codec: Int;
  h_util: Int;
  p_send_packet: Int;
  p_receive_frame: Int;
  p_free_context: Int;
  p_packet_alloc: Int;
  p_packet_free: Int;
  p_packet_unref: Int;
  p_frame_alloc: Int;
  p_frame_free: Int;
  p_frame_unref: Int;
  p_pix_fmt_name: Int;
}

/// Flat packet outcome (never `Result[Option[T]]`, finding B-26).
pub type FfPacketOutcome = {
  ok: Bool;
  packet: Int;
  message: Str;
}

/// Flat frame outcome: `kind` is one of the FFMPEG_DECODE_* constants; on
/// FFMPEG_DECODE_FRAME the caller owns `frame` (release with
/// `ffmpeg_frame_unref` + `ffmpeg_frame_free`).
pub type FfFrameOutcome = {
  kind: Int;
  rc: Int;
  frame: Int;
  width: Int;
  height: Int;
  pix_fmt: Int;
  pix_fmt_name: Str;
  message: Str;
}

/// Locate and open one named AV1-class decoder.  Discovery primitive:
/// `avcodec_find_decoder_by_name(name)` -> `avcodec_alloc_context3` ->
/// `avcodec_open2`.  Err(FFMPEG_DECODER_ABSENT) when the name is not
/// registered or the open is refused (e.g. a wrapper whose backing library
/// is absent), so the caller can try the next candidate -> SKIP.
/// Complexity: O(symbols + open).
pub fn ffmpeg_av1_decoder_open_named(lib: &FfmpegLibrary, name: Str) -> Result[FfDecoder, FfLoadError]
  requires: lib.h_codec != 0
  requires: name.len() > 0
{
  let api = ffmpeg_resolve_decode_api(lib);
  if !api.is_ok {
    return Err(api.error);
  }
  let api_v: FfDecodeApi = api.value;
  return ffmpeg_open_named_with_api(&api_v, name);
}

/// Open the first usable AV1-class decoder.  Candidate preference:
/// "libdav1d", "libaom-av1", then the native "av1" (`FFMPEG_AV1_DECODERS`
/// lists the full name set).  Rationale: in the pinned 6.x-8.x lineage the
/// native `av1` decoder's only software path goes through a hardware
/// accelerator -- without one, the first packet returns AVERROR(ENOSYS)
/// (`libavcodec/av1dec.c`, "Your platform doesn't support hardware
/// accelerated AV1 decoding") -- so the dav1d/aom software wrappers are
/// preferred and the native entry stays as the last fallback for callers
/// that later attach a hardware device.  Err(FFMPEG_DECODER_ABSENT) when no
/// candidate opens -> the caller reports SKIP.
/// Complexity: O(candidates * (symbols + open)).
pub fn ffmpeg_av1_decoder_open(lib: &FfmpegLibrary) -> Result[FfDecoder, FfLoadError]
  requires: lib.h_codec != 0
{
  let api = ffmpeg_resolve_decode_api(lib);
  if !api.is_ok {
    return Err(api.error);
  }
  let api_v: FfDecodeApi = api.value;

  let r1 = ffmpeg_open_named_with_api(&api_v, "libdav1d");
  if r1.is_ok { return Ok(r1.value); }
  let r2 = ffmpeg_open_named_with_api(&api_v, "libaom-av1");
  if r2.is_ok { return Ok(r2.value); }
  let r3 = ffmpeg_open_named_with_api(&api_v, "av1");
  if r3.is_ok { return Ok(r3.value); }

  return Err(FfLoadError{
    kind: FFMPEG_DECODER_ABSENT;
    message: "no usable AV1-class decoder (tried " + FFMPEG_AV1_SOFTWARE_ORDER + ") -- "
      + r1.error.message + "; " + r2.error.message + "; " + r3.error.message;
  });
}

/// Allocate an AVPacket.
/// Complexity: O(1).
pub fn ffmpeg_packet_alloc(dec: &FfDecoder) -> FfPacketOutcome
  requires: dec.p_packet_alloc != 0
{
  let pkt = ffmpeg_alloc_packet(dec.p_packet_alloc);
  if pkt == 0 {
    return FfPacketOutcome{ ok: false; packet: 0; message: "av_packet_alloc returned null" };
  }
  return FfPacketOutcome{ ok: true; packet: pkt; message: "" };
}

/// Build an AVPacket whose payload is a copy of `data[offset .. offset+size)`
/// (owned XIOM bytes copied by the bridge into an av_malloc'ed buffer; the
/// packet owns the copy and `ffmpeg_packet_free` releases it).
/// Complexity: O(size).
pub fn ffmpeg_packet_from_bytes(dec: &FfDecoder, data: &Vec[UInt8], offset: Int, size: Int) -> FfPacketOutcome
  requires: dec.h_codec != 0
  requires: offset >= 0
  requires: size > 0
  requires: data.len() >= offset + size
{
  let pkt = unsafe { ffmpeg_bridge_packet_from_bytes(dec.h_codec, dec.h_util, data.as_mut_ptr(), offset, size) as Int };
  if pkt == 0 {
    return FfPacketOutcome{ ok: false; packet: 0; message: "packet_from_bytes bridge failed (av_packet_alloc/av_packet_from_data/av_malloc)" };
  }
  return FfPacketOutcome{ ok: true; packet: pkt; message: "" };
}

/// Release the payload references of a packet (the packet object stays
/// allocated and reusable).  Complexity: O(1).
pub fn ffmpeg_packet_unref(dec: &FfDecoder, packet: Int)
  requires: dec.p_packet_unref != 0
  requires: packet != 0
{
  unsafe {
    let f_unref = dec.p_packet_unref as fn(Int);
    f_unref(packet);
  }
}

/// Free a packet (object + payload).  Complexity: O(1).
pub fn ffmpeg_packet_free(dec: &FfDecoder, packet: Int) -> Result[Unit, Str]
  requires: dec.p_packet_free != 0
  requires: packet != 0
{
  ffmpeg_free_ptr(dec.p_packet_free, packet);
  return Ok(());
}

/// Allocate an AVFrame for receive.  Complexity: O(1).
pub fn ffmpeg_frame_alloc(dec: &FfDecoder) -> Result[Int, Str]
  requires: dec.p_frame_alloc != 0
{
  let frame = ffmpeg_alloc_frame(dec.p_frame_alloc);
  if frame == 0 {
    return Err("av_frame_alloc returned null");
  }
  return Ok(frame);
}

/// Drop a frame's references (the frame object stays allocated and
/// reusable).  Complexity: O(1).
pub fn ffmpeg_frame_unref(dec: &FfDecoder, frame: Int)
  requires: dec.p_frame_unref != 0
  requires: frame != 0
{
  unsafe {
    let f_unref = dec.p_frame_unref as fn(Int);
    f_unref(frame);
  }
}

/// Free a frame (object + buffers).  Complexity: O(1).
pub fn ffmpeg_frame_free(dec: &FfDecoder, frame: Int) -> Result[Unit, Str]
  requires: dec.p_frame_free != 0
  requires: frame != 0
{
  ffmpeg_free_ptr(dec.p_frame_free, frame);
  return Ok(());
}

/// Feed one packet to the decoder (0 = accepted, FFMPEG_ERR_EAGAIN = drain
/// frames first, other = error).  Complexity: O(1).
pub fn ffmpeg_decoder_send(dec: &FfDecoder, packet: Int) -> Int
  requires: dec.ctx != 0
  requires: packet != 0
{
  unsafe {
    let f_send = dec.p_send_packet as fn(Int, Int) -> Int32;
    return f_send(dec.ctx, packet) as Int;
  }
}

/// Enter drain mode: sends the null packet (avcodec docs: "send NULL") so
/// buffered frames are emitted; receive until FFMPEG_DECODE_EOF.
/// Complexity: O(1).
pub fn ffmpeg_decoder_flush(dec: &FfDecoder) -> Int
  requires: dec.ctx != 0
{
  unsafe {
    let f_send = dec.p_send_packet as fn(Int, Int) -> Int32;
    return f_send(dec.ctx, 0) as Int;
  }
}

/// Receive one frame.  On FFMPEG_DECODE_FRAME the caller owns the returned
/// frame handle and must release it (unref + free).  On every other kind the
/// internally allocated frame has already been released.
/// Complexity: O(1).
pub fn ffmpeg_decoder_receive(dec: &FfDecoder) -> FfFrameOutcome
  requires: dec.ctx != 0
{
  let frame = ffmpeg_alloc_frame(dec.p_frame_alloc);
  if frame == 0 {
    return FfFrameOutcome{ kind: FFMPEG_DECODE_ERROR; rc: 0; frame: 0; width: 0; height: 0; pix_fmt: 0; pix_fmt_name: ""; message: "av_frame_alloc returned null" };
  }

  var rc: Int = 0;
  unsafe {
    let f_recv = dec.p_receive_frame as fn(Int, Int) -> Int32;
    rc = f_recv(dec.ctx, frame) as Int;
  }

  if rc == 0 {
    let fi = ffmpeg_frame_info_copy(frame);
    if !fi.ok {
      ffmpeg_free_ptr(dec.p_frame_free, frame);
      return FfFrameOutcome{ kind: FFMPEG_DECODE_ERROR; rc: rc; frame: 0; width: 0; height: 0; pix_fmt: 0; pix_fmt_name: ""; message: "frame head copy failed (bridge ABI mismatch?)" };
    }
    let pname = ffmpeg_pix_fmt_name(dec.p_pix_fmt_name, fi.format);
    return FfFrameOutcome{
      kind: FFMPEG_DECODE_FRAME;
      rc: rc;
      frame: frame;
      width: fi.width;
      height: fi.height;
      pix_fmt: fi.format;
      pix_fmt_name: pname;
      message: "";
    };
  }

  ffmpeg_free_ptr(dec.p_frame_free, frame);
  if rc == FFMPEG_ERR_EAGAIN {
    return FfFrameOutcome{ kind: FFMPEG_DECODE_AGAIN; rc: rc; frame: 0; width: 0; height: 0; pix_fmt: 0; pix_fmt_name: ""; message: "" };
  }
  if rc == FFMPEG_ERR_EOF {
    return FfFrameOutcome{ kind: FFMPEG_DECODE_EOF; rc: rc; frame: 0; width: 0; height: 0; pix_fmt: 0; pix_fmt_name: ""; message: "" };
  }
  return FfFrameOutcome{
    kind: FFMPEG_DECODE_ERROR;
    rc: rc;
    frame: 0;
    width: 0;
    height: 0;
    pix_fmt: 0;
    pix_fmt_name: "";
    message: "avcodec_receive_frame rc=" + fi_to_str(rc);
  };
}

/// Close a decoder: frees the codec context.  Idempotent for ctx == 0.
/// Complexity: O(1).
pub fn ffmpeg_decoder_close(dec: &FfDecoder) -> Result[Unit, Str]
  requires: true
{
  if dec.ctx == 0 {
    return Ok(());
  }
  ffmpeg_free_ptr(dec.p_free_context, dec.ctx);
  return Ok(());
}

// =========================================================================
// Decode internals
// =========================================================================

/// The bridge out-slot copy result for one frame head.
type FfFrameInfo = {
  ok: Bool;
  width: Int;
  height: Int;
  format: Int;
}

/// Bridge: AVPacket built from owned bytes (see src/ffmpeg_bridge.c).
extern "C" {
  fn ffmpeg_bridge_packet_from_bytes(codec_mod: Int, util_mod: Int, src: *UInt8, offset: Int, size: Int) -> Int;
  fn ffmpeg_bridge_frame_info(frame: Int, out_slot: *UInt8) -> Int32;
}

/// Resolved decode entry points on a loaded generation (flat, B-26).
type FfDecodeApi = {
  h_codec: Int;
  h_util: Int;
  p_find: Int;
  p_alloc_ctx: Int;
  p_open: Int;
  p_send: Int;
  p_recv: Int;
  p_free_ctx: Int;
  p_packet_alloc: Int;
  p_packet_free: Int;
  p_packet_unref: Int;
  p_frame_alloc: Int;
  p_frame_free: Int;
  p_frame_unref: Int;
  p_pix_name: Int;
}

/// Resolve the 13 decode entry points (a missing one = FFMPEG_LOAD_ABI).
/// Complexity: O(symbols).
fn ffmpeg_resolve_decode_api(lib: &FfmpegLibrary) -> Result[FfDecodeApi, FfLoadError]
  requires: lib.h_codec != 0
{
  let s_find = dl.dl_sym(lib.h_codec, "avcodec_find_decoder_by_name");
  if !s_find.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avcodec_find_decoder_by_name: " + s_find.error }); }
  let s_alloc = dl.dl_sym(lib.h_codec, "avcodec_alloc_context3");
  if !s_alloc.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avcodec_alloc_context3: " + s_alloc.error }); }
  let s_open = dl.dl_sym(lib.h_codec, "avcodec_open2");
  if !s_open.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avcodec_open2: " + s_open.error }); }
  let s_send = dl.dl_sym(lib.h_codec, "avcodec_send_packet");
  if !s_send.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avcodec_send_packet: " + s_send.error }); }
  let s_recv = dl.dl_sym(lib.h_codec, "avcodec_receive_frame");
  if !s_recv.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avcodec_receive_frame: " + s_recv.error }); }
  let s_free_ctx = dl.dl_sym(lib.h_codec, "avcodec_free_context");
  if !s_free_ctx.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "avcodec_free_context: " + s_free_ctx.error }); }
  let s_pkt_alloc = dl.dl_sym(lib.h_codec, "av_packet_alloc");
  if !s_pkt_alloc.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "av_packet_alloc: " + s_pkt_alloc.error }); }
  let s_pkt_free = dl.dl_sym(lib.h_codec, "av_packet_free");
  if !s_pkt_free.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "av_packet_free: " + s_pkt_free.error }); }
  let s_pkt_unref = dl.dl_sym(lib.h_codec, "av_packet_unref");
  if !s_pkt_unref.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "av_packet_unref: " + s_pkt_unref.error }); }
  let s_frame_alloc = dl.dl_sym(lib.h_util, "av_frame_alloc");
  if !s_frame_alloc.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "av_frame_alloc: " + s_frame_alloc.error }); }
  let s_frame_free = dl.dl_sym(lib.h_util, "av_frame_free");
  if !s_frame_free.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "av_frame_free: " + s_frame_free.error }); }
  let s_frame_unref = dl.dl_sym(lib.h_util, "av_frame_unref");
  if !s_frame_unref.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "av_frame_unref: " + s_frame_unref.error }); }
  let s_pix_name = dl.dl_sym(lib.h_util, "av_get_pix_fmt_name");
  if !s_pix_name.is_ok { return Err(FfLoadError{ kind: FFMPEG_LOAD_ABI; message: "av_get_pix_fmt_name: " + s_pix_name.error }); }

  return Ok(FfDecodeApi{
    h_codec: lib.h_codec;
    h_util: lib.h_util;
    p_find: s_find.value;
    p_alloc_ctx: s_alloc.value;
    p_open: s_open.value;
    p_send: s_send.value;
    p_recv: s_recv.value;
    p_free_ctx: s_free_ctx.value;
    p_packet_alloc: s_pkt_alloc.value;
    p_packet_free: s_pkt_free.value;
    p_packet_unref: s_pkt_unref.value;
    p_frame_alloc: s_frame_alloc.value;
    p_frame_free: s_frame_free.value;
    p_frame_unref: s_frame_unref.value;
    p_pix_name: s_pix_name.value;
  });
}

/// Find + alloc ctx + open for one candidate name, using a resolved api.
/// Complexity: O(open).
fn ffmpeg_open_named_with_api(api: &FfDecodeApi, name: Str) -> Result[FfDecoder, FfLoadError]
  requires: name.len() > 0
{
  let codec = ffmpeg_find_decoder(api.p_find, name);
  if codec == 0 {
    return Err(FfLoadError{ kind: FFMPEG_DECODER_ABSENT; message: name + ": avcodec_find_decoder_by_name returned null" });
  }
  let ctx = ffmpeg_alloc_context(api.p_alloc_ctx, codec);
  if ctx == 0 {
    return Err(FfLoadError{ kind: FFMPEG_DECODER_ABSENT; message: name + ": avcodec_alloc_context3 returned null" });
  }
  let rc = ffmpeg_open_context(api.p_open, ctx, codec);
  if rc < 0 {
    ffmpeg_free_ptr(api.p_free_ctx, ctx);
    return Err(FfLoadError{ kind: FFMPEG_DECODER_ABSENT; message: name + ": avcodec_open2 rc=" + fi_to_str(rc) });
  }
  return Ok(FfDecoder{
    ctx: ctx;
    codec: codec;
    codec_name: name;
    h_codec: api.h_codec;
    h_util: api.h_util;
    p_send_packet: api.p_send;
    p_receive_frame: api.p_recv;
    p_free_context: api.p_free_ctx;
    p_packet_alloc: api.p_packet_alloc;
    p_packet_free: api.p_packet_free;
    p_packet_unref: api.p_packet_unref;
    p_frame_alloc: api.p_frame_alloc;
    p_frame_free: api.p_frame_free;
    p_frame_unref: api.p_frame_unref;
    p_pix_fmt_name: api.p_pix_name;
  });
}

fn ffmpeg_find_decoder(p_find: Int, name: Str) -> Int
  requires: p_find != 0
  requires: name.len() > 0
{
  unsafe {
    let f_find = p_find as fn(*UInt8) -> Int;
    return f_find(name.c_str());
  }
}

fn ffmpeg_alloc_context(p_alloc: Int, codec: Int) -> Int
  requires: p_alloc != 0
  requires: codec != 0
{
  unsafe {
    let f_alloc = p_alloc as fn(Int) -> Int;
    return f_alloc(codec);
  }
}

fn ffmpeg_open_context(p_open: Int, ctx: Int, codec: Int) -> Int
  requires: p_open != 0
  requires: ctx != 0
  requires: codec != 0
{
  unsafe {
    // options: AVDictionary** -- Int 0 (never the bare `null` literal, B-23).
    let f_open = p_open as fn(Int, Int, Int) -> Int32;
    return f_open(ctx, codec, 0) as Int;
  }
}

fn ffmpeg_alloc_packet(p_alloc: Int) -> Int
  requires: p_alloc != 0
{
  unsafe {
    let f_alloc = p_alloc as fn() -> Int;
    return f_alloc();
  }
}

fn ffmpeg_alloc_frame(p_alloc: Int) -> Int
  requires: p_alloc != 0
{
  unsafe {
    let f_alloc = p_alloc as fn() -> Int;
    return f_alloc();
  }
}

/// Free a foreign object through a pointer-to-pointer API
/// (avcodec_free_context / av_packet_free / av_frame_free): the handle is
/// written little-endian into ONE owned 8-byte slot and the slot's address
/// is passed to C (B-17/B-25: never pointer arithmetic, never `Int as
/// *UInt8`).  Complexity: O(1).
fn ffmpeg_free_ptr(p_free: Int, handle: Int)
  requires: p_free != 0
  requires: handle != 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  slot.push((handle & 255) as UInt8);
  slot.push(((handle >> 8) & 255) as UInt8);
  slot.push(((handle >> 16) & 255) as UInt8);
  slot.push(((handle >> 24) & 255) as UInt8);
  slot.push(((handle >> 32) & 255) as UInt8);
  slot.push(((handle >> 40) & 255) as UInt8);
  slot.push(((handle >> 48) & 255) as UInt8);
  slot.push(((handle >> 56) & 255) as UInt8);
  unsafe {
    let f_free = p_free as fn(*UInt8);
    f_free(slot.as_mut_ptr());
  }
}

/// Copy the AVFrame head (width/height/format) through the bridge into an
/// owned slot and read it byte-indexed (B-20/B-24: no foreign reads).
/// Complexity: O(1).
fn ffmpeg_frame_info_copy(frame: Int) -> FfFrameInfo
  requires: frame != 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  var k = 0;
  while k < 12 {
    slot.push(0 as UInt8);
    k = k + 1;
  }
  let rc = unsafe { ffmpeg_bridge_frame_info(frame, slot.as_mut_ptr()) as Int };
  if rc != 0 {
    return FfFrameInfo{ ok: false; width: 0; height: 0; format: 0 };
  }
  let w = (slot[0] as Int) | ((slot[1] as Int) << 8) | ((slot[2] as Int) << 16) | ((slot[3] as Int) << 24);
  let h = (slot[4] as Int) | ((slot[5] as Int) << 8) | ((slot[6] as Int) << 16) | ((slot[7] as Int) << 24);
  let fmt = (slot[8] as Int) | ((slot[9] as Int) << 8) | ((slot[10] as Int) << 16) | ((slot[11] as Int) << 24);
  return FfFrameInfo{ ok: true; width: w; height: h; format: fmt };
}

/// av_get_pix_fmt_name on the resolved pointer; empty string when unknown.
/// Complexity: O(1).
fn ffmpeg_pix_fmt_name(p_name: Int, fmt: Int) -> Str
  requires: p_name != 0
  requires: fmt >= 0
{
  unsafe {
    let f_name = p_name as fn(Int32) -> *UInt8;
    let np = f_name(fmt as Int32);
    if (np as Int) != 0 {
      return Str::from_c_str(np);
    }
    return "";
  }
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
