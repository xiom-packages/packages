// xiom.ffmpeg conformance suite -- dynamic-loader path (system FFmpeg DLLs).
//
// CI WITHOUT FFmpeg stays green: no candidate generation resolves -> SKIP
// (the SKIP classification is exercised deterministically every run via
// bogus sonames).  With an LGPL shared build on PATH the probe reports
// av_version_info plus the four library versions and the build's license
// evidence -- 4 checks.
//
// 0.3.0 adds the AV1-class decode surface.  With a loaded generation:
//   * the preferred software decoder ("libdav1d" then "libaom-av1", native
//     "av1" last) is discovered by name and its codec context opens -> check;
//   * the local IVF fixture (tests/fixtures/av1_64x48.ivf, 3 AV1 frames,
//     generated from a synthetic pattern -- PROVENANCE.md) is demuxed
//     in-suite (IVF framing only), fed as packets and decoded -> checks on
//     packet/frame lifecycle + width/height/pixel-format read-out;
//   * DLLs present but no usable AV1 decoder -> SKIP; fixture absent -> SKIP;
//   * only the native "av1" available (no dav1d/aom backing library) ->
//     hardware-only decoder, AVERROR(ENOSYS) on the first packet -> SKIP
//     (the pinned 6.x-8.x lineage is hwaccel-only on that path).
//
// Build+run (the bridge C source from port.args.json; pure dynamic loading --
// no FFmpeg link):
//   scripts/port.ps1 -Package xiom.ffmpeg

module ffmpeg_conformance

use xiom.io;
use xiom.test;
use xiom.ffmpeg;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  if n < 0 { return "-" + i2s(0 - n); }
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

// ---- IVF framing helpers (test-local; avformat demux is out of scope) ------

fn u16_le(b: &Vec[UInt8], off: Int) -> Int
  requires: b.len() >= off + 2
{
  return (b[off] as Int) | ((b[off + 1] as Int) << 8);
}

fn u32_le(b: &Vec[UInt8], off: Int) -> Int
  requires: b.len() >= off + 4
{
  return (b[off] as Int) | ((b[off + 1] as Int) << 8) | ((b[off + 2] as Int) << 16) | ((b[off + 3] as Int) << 24);
}

/// Locate the fixture: port.ps1 runs with the package dir as cwd; the
/// repo-root form is tried as a fallback.  Empty Vec when absent -> SKIP.
fn load_fixture() -> Vec[UInt8] {
  let r1 = io.read_file_bytes("tests/fixtures/av1_64x48.ivf");
  if r1.is_ok { return r1.value; }
  let r2 = io.read_file_bytes("packages/xiom-ffmpeg/tests/fixtures/av1_64x48.ivf");
  if r2.is_ok { return r2.value; }
  return Vec[UInt8].new();
}

// ---- Decode loop ------------------------------------------------------------
//
// Note: the drain state is kept in scalar locals (no struct passed by value --
// v0.64.4 move warnings) and the whole flow lives in one function.

/// Decode the whole IVF fixture: feed every frame as a packet, drain, flush,
/// drain to EOF.  Returns the updated failure count.
fn run_decode_checks(dec: &FfDecoder, failed: Int) -> Int {
  let fx = load_fixture();
  if fx.len() < 32 {
    return failed + report(true, "decode: SKIP -- tests/fixtures/av1_64x48.ivf not found");
  }

  let magic = (fx[0] as Int) == 68 && (fx[1] as Int) == 75 && (fx[2] as Int) == 73 && (fx[3] as Int) == 70;
  let fourcc = (fx[8] as Int) == 65 && (fx[9] as Int) == 86 && (fx[10] as Int) == 48 && (fx[11] as Int) == 49;
  let iw = u16_le(&fx, 12);
  let ih = u16_le(&fx, 14);
  let nframes = u32_le(&fx, 24);
  var out = failed + report(magic && fourcc && iw == 64 && ih == 48 && nframes >= 1,
    "decode: IVF fixture DKIF/AV01 " + i2s(iw) + "x" + i2s(ih) + " frames=" + i2s(nframes));

  var frames = 0;
  var drain_err = 0;
  var saw_eof = false;
  var fw = 0;
  var fh = 0;
  var fp = "";

  // Phase 1: feed every IVF frame as a packet.
  var off = 32;
  var i = 0;
  var sent = 0;
  var pkt_err = 0;
  var send_err = 0;
  var resends = 0;
  var hw_only = false;
  while i < nframes {
    if off + 12 > fx.len() {
      i = nframes;
    } else {
      let fsz = u32_le(&fx, off);
      let dstart = off + 12;
      if fsz <= 0 || dstart + fsz > fx.len() {
        i = nframes;
      } else {
        let po = ffmpeg_packet_from_bytes(dec, &fx, dstart, fsz);
        if !po.ok {
          pkt_err = pkt_err + 1;
        } else {
          var snd = ffmpeg_decoder_send(dec, po.packet);
          if snd == FFMPEG_ERR_ENOSYS {
            // Native "av1" decoder on the pinned lineage without a hardware
            // accelerator: hwaccel-only software path -> SKIP, not FAIL.
            hw_only = true;
          } else {
            if snd == FFMPEG_ERR_EAGAIN {
              // Output is pending: drain every available frame, then re-send.
              var more = true;
              var dguard = 0;
              while more && dguard < 16 {
                let fr0 = ffmpeg_decoder_receive(dec);
                if fr0.kind == FFMPEG_DECODE_FRAME {
                  frames = frames + 1;
                  if fw == 0 { fw = fr0.width; fh = fr0.height; fp = fr0.pix_fmt_name; }
                  ffmpeg_frame_unref(dec, fr0.frame);
                  var igf0 = ffmpeg_frame_free(dec, fr0.frame);
                } else {
                  if fr0.kind == FFMPEG_DECODE_ERROR {
                    drain_err = drain_err + 1;
                  }
                  more = false;
                }
                dguard = dguard + 1;
              }
              resends = resends + 1;
              snd = ffmpeg_decoder_send(dec, po.packet);
            }
            if snd == 0 { sent = sent + 1; } else { send_err = send_err + 1; }
          }
          ffmpeg_packet_unref(dec, po.packet);
          var igp = ffmpeg_packet_free(dec, po.packet);
        }
        off = dstart + fsz;
        if hw_only { i = nframes; } else { i = i + 1; }
      }
    }
  }
  if hw_only {
    return out + report(true, "decode: SKIP -- decoder '" + dec.codec_name
      + "' is hardware-accelerated-only (AVERROR(ENOSYS) on the first packet; no hw device attached)");
  }
  let pre_frames = frames;

  // Phase 2: drain after the packets; then flush (send NULL) and drain to EOF.
  var phase = 0;
  var flrc = -1;
  while phase < 2 {
    var terminal = false;
    var guard = 0;
    while !terminal && guard < 64 {
      let fr = ffmpeg_decoder_receive(dec);
      if fr.kind == FFMPEG_DECODE_FRAME {
        frames = frames + 1;
        if fw == 0 { fw = fr.width; fh = fr.height; fp = fr.pix_fmt_name; }
        ffmpeg_frame_unref(dec, fr.frame);
        var igf = ffmpeg_frame_free(dec, fr.frame);
      } elif fr.kind == FFMPEG_DECODE_AGAIN {
        terminal = true;
      } elif fr.kind == FFMPEG_DECODE_EOF {
        terminal = true;
        saw_eof = true;
      } else {
        drain_err = drain_err + 1;
        terminal = true;
      }
      guard = guard + 1;
    }
    if phase == 0 {
      flrc = ffmpeg_decoder_flush(dec);
    }
    phase = phase + 1;
  }

  out = out + report(sent == nframes && pkt_err == 0 && send_err == 0,
    "decode: packets fed " + i2s(sent) + "/" + i2s(nframes) + " (packet errors " + i2s(pkt_err)
      + ", send errors " + i2s(send_err) + ", EAGAIN resends " + i2s(resends) + ")");
  out = out + report(frames >= 1 && fw == iw && fh == ih,
    "decode: " + i2s(frames) + " frame(s) (pre-flush " + i2s(pre_frames)
      + "); first " + i2s(fw) + "x" + i2s(fh) + " matches IVF header");
  out = out + report(fp.len() > 0, "decode: pixel format " + fp);
  out = out + report(flrc == 0 && drain_err == 0 && saw_eof,
    "decode: flush rc=" + i2s(flrc) + " drain errors=" + i2s(drain_err)
      + " eof=" + b2s(saw_eof));
  return out;
}

fn main() -> Int {
  io.println("=== xiom.ffmpeg conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // SKIP-path classification, deterministic on every host (bogus sonames).
  let missing = ffmpeg_load_named(
    "xiom-absent-avcodec-probe-xyz.dll",
    "xiom-absent-avformat-probe-xyz.dll",
    "xiom-absent-avutil-probe-xyz.dll",
    "xiom-absent-swresample-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus sonames unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == FFMPEG_LOAD_ABSENT,
      "skip-path: absent libraries classified as FFMPEG_LOAD_ABSENT (SKIP)");
  }

  let l = ffmpeg_load();
  if !l.is_ok {
    if l.error.kind == FFMPEG_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- no FFmpeg shared-library generation present (" + l.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + l.error.message);
      return failed;
    }
    failed = failed + report(true, "decode: SKIP -- no FFmpeg shared-library generation present");
  } else {
    let lib: FfmpegLibrary = l.value;
    let p = ffmpeg_probe(&lib);
    if p.is_ok {
      let info: FfmpegInfo = p.value;
      failed = failed + report(info.version_info.len() > 0,
        "version: FFmpeg " + info.version_info);
      failed = failed + report(
        info.avcodec_version > 0 && info.avformat_version > 0
          && info.avutil_version > 0 && info.swresample_version > 0,
        "set: avcodec " + ffmpeg_version_str(info.avcodec_version)
          + " / avformat " + ffmpeg_version_str(info.avformat_version)
          + " / avutil " + ffmpeg_version_str(info.avutil_version)
          + " / swresample " + ffmpeg_version_str(info.swresample_version));
      failed = failed + report(ffmpeg_lgpl_build(&info) != info.gpl_enabled,
        "license: " + info.license + " (gpl-configured " + b2s(info.gpl_enabled) + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error);
    }

    // Decode surface (SKIP-classified when the decoder/fixture is absent).
    let dres = ffmpeg_av1_decoder_open(&lib);
    if !dres.is_ok {
      if dres.error.kind == FFMPEG_DECODER_ABSENT {
        failed = failed + report(true, "decode: SKIP -- " + dres.error.message);
      } else {
        failed = failed + report(false, "decode: entry points missing -- " + dres.error.message);
      }
    } else {
      let dec: FfDecoder = dres.value;
      failed = failed + report(dec.ctx != 0, "decode: AV1 decoder opened (" + dec.codec_name + ")");
      failed = run_decode_checks(&dec, failed);
      let cl = ffmpeg_decoder_close(&dec);
      failed = failed + report(cl.is_ok, "decode: decoder closed");
    }

    let lc = ffmpeg_close(&lib);
    failed = failed + report(lc.is_ok, "loader: library generation closed");
  }

  if failed == 0 {
    io.println("xiom.ffmpeg: all tests passed");
  } else {
    io.println("xiom.ffmpeg: tests failed");
  }
  return failed;
}
