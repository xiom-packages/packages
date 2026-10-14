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
// 0.4.0 adds the container demux surface (libavformat).  With a loaded
// generation and the fixture present:
//   * the same IVF fixture is opened through avformat_open_input +
//     avformat_find_stream_info (stream enumeration: count, codec id/type,
//     time base, geometry; best-stream selection);
//   * the codec-id gate is generation-independent (0.4.1): the expected AV1
//     id is resolved from the stable codec name at runtime -- the numeric
//     AVCodecID shifts across FFmpeg majors (226 on lavc 60.x, 225 on
//     lavc 61.x), so no constant is asserted;
//   * the packet loop is checked against the IVF framing (count, sizes,
//     payload byte equality, stream_index/pts against the container header,
//     clean EOF) and the demuxed packets are fed to a fresh AV1 decoder
//     (demux -> decode integration);
//   * seek(0, BACKWARD) then re-read is checked;
//   * a bogus path is classified FFMPEG_DEMUX_FAILED (typed error);
//   * fixture absent -> SKIP; no usable decoder -> the demux->decode feed
//     check is SKIP while the container checks still run.
//
// Build+run (the bridge C source from port.args.json; pure dynamic loading --
// no FFmpeg link):
//   scripts/port.ps1 -Package xiom.ffmpeg

module ffmpeg_conformance

use xiom.io;
use xiom.test;
use xiom.ffmpeg;
use xiom.string;

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

// ---- Container demux (0.4.0) -----------------------------------------------

fn u64_le(b: &Vec[UInt8], off: Int) -> Int
  requires: b.len() >= off + 8
{
  return u32_le(b, off) | (u32_le(b, off + 4) << 32);
}

/// Fixture path for avformat (same candidates as load_fixture; the suite
/// runs with the package dir as cwd).
fn fixture_path() -> Str {
  let p1 = "tests/fixtures/av1_64x48.ivf";
  let r1 = io.read_file_bytes(p1);
  if r1.is_ok { return p1; }
  return "packages/xiom-ffmpeg/tests/fixtures/av1_64x48.ivf";
}

fn same_bytes(a: &Vec[UInt8], b: &Vec[UInt8], b_off: Int, n: Int) -> Bool
  requires: a.len() >= n
  requires: b.len() >= b_off + n
{
  var i = 0;
  while i < n {
    if (a[i] as Int) != (b[b_off + i] as Int) { return false; }
    i = i + 1;
  }
  return true;
}

/// 0.4.0 demux checks: open the IVF fixture through libavformat, enumerate
/// streams, select the best video stream, run the packet loop (sizes/bytes
/// against the container framing), feed the demuxed packets to a fresh AV1
/// decoder, seek back and re-read.  All Str comparisons use str_compare.
fn run_demux_section(lib: &FfmpegLibrary, failed: Int) -> Int {
  let fx = load_fixture();
  if fx.len() < 32 {
    return failed + report(true, "demux: SKIP -- tests/fixtures/av1_64x48.ivf not found");
  }
  let path = fixture_path();
  var out = failed;

  let iw = u16_le(&fx, 12);
  let ih = u16_le(&fx, 14);
  let nframes = u32_le(&fx, 24);

  // Typed error path: an absent container path is FFMPEG_DEMUX_FAILED.
  let bad = ffmpeg_demux_open(lib, "tests/fixtures/xiom-absent-container-xyz.ivf");
  if bad.is_ok {
    out = out + report(false, "demux: absent path unexpectedly opened");
  } else {
    out = out + report(bad.error.kind == FFMPEG_DEMUX_FAILED && bad.error.message.len() > 0,
      "demux: absent path -> " + bad.error.message);
  }

  let r = ffmpeg_demux_open(lib, path);
  if !r.is_ok {
    if r.error.kind == FFMPEG_LOAD_ABI {
      return out + report(false, "demux: entry points missing -- " + r.error.message);
    }
    return out + report(false, "demux: open failed -- " + r.error.message);
  }
  let demux: FfDemuxer = r.value;

  var count = -1;
  let sc = ffmpeg_demux_stream_count(&demux);
  if sc.is_ok { count = sc.value; }
  out = out + report(sc.is_ok && count == 1,
    "demux: opened " + path + " (streams=" + i2s(count) + ")");

  let si = ffmpeg_demux_stream_info(&demux, 0);
  // The numeric AVCodecID is not stable across FFmpeg major generations
  // (AV_CODEC_ID_AV1: 226 on lavc 60.x, 225 on lavc 61.x after the
  // deprecated packed-YUV ids were removed): resolve the loaded
  // generation's own AV1 id from the stable codec NAME instead of gating on
  // a hardcoded constant.
  let av1_id = ffmpeg_codec_id_by_name(lib, "av1");
  var cname = "";
  if si.ok && si.codec_id >= 0 { cname = ffmpeg_codec_name(lib, si.codec_id); }
  out = out + report(si.ok && av1_id >= 0 && si.codec_id == av1_id && si.codec_type == FFMPEG_MEDIA_TYPE_VIDEO
      && str_compare(cname, "av1") == 0 && si.time_base_num == 1 && si.time_base_den == 4,
    "demux: stream 0 codec=" + cname + " id=" + i2s(si.codec_id) + " (generation av1 id=" + i2s(av1_id)
      + ") type=" + i2s(si.codec_type) + " time_base=" + i2s(si.time_base_num) + "/" + i2s(si.time_base_den));
  out = out + report(si.ok && si.width == iw && si.height == ih,
    "demux: stream 0 geometry " + i2s(si.width) + "x" + i2s(si.height) + " matches IVF header");

  let bv = ffmpeg_demux_best_stream(&demux, FFMPEG_MEDIA_TYPE_VIDEO);
  let ba = ffmpeg_demux_best_stream(&demux, FFMPEG_MEDIA_TYPE_AUDIO);
  var astr = "none";
  if ba.ok { astr = "index " + i2s(ba.index); }
  out = out + report(bv.ok && bv.index == 0 && !ba.ok,
    "demux: best video stream=" + i2s(bv.index) + "; best audio " + astr);

  // Fresh decoder for the demux -> decode feed (independent of the decode
  // section above; SKIP when no usable AV1 decoder is present).
  let dres = ffmpeg_av1_decoder_open(lib);
  var have_dec = dres.is_ok;
  var dec: FfDecoder = FfDecoder{ ctx: 0; codec: 0; codec_name: ""; h_codec: 0; h_util: 0; p_send_packet: 0; p_receive_frame: 0; p_free_context: 0; p_packet_alloc: 0; p_packet_free: 0; p_packet_unref: 0; p_frame_alloc: 0; p_frame_free: 0; p_frame_unref: 0; p_pix_fmt_name: 0 };
  if have_dec { dec = dres.value; }
  var frames = 0;
  var send_err = 0;
  var drain_err = 0;
  var resends = 0;
  var fw = 0;
  var fh = 0;
  var fp = "";

  var packets = 0;
  var frames_seen = 0;
  var sizes_ok = true;
  var bytes_ok = true;
  var meta_ok = true;
  var first_flags = -1;
  var off = 32;
  var i = 0;
  while i < nframes {
    let pr = ffmpeg_demux_read_packet(&demux);
    if !pr.ok {
      i = nframes;
      meta_ok = false;
    } else {
      packets = packets + 1;
      let esz = u32_le(&fx, off);
      let ets = u64_le(&fx, off + 4);
      if pr.size != esz { sizes_ok = false; }
      if pr.stream_index != 0 { meta_ok = false; }
      if pr.pts != ets { meta_ok = false; }
      if frames_seen == 0 { first_flags = pr.flags; }
      let pb = ffmpeg_demux_packet_bytes(&demux, pr.packet, pr.size);
      if !pb.is_ok {
        bytes_ok = false;
      } else {
        let pbv: Vec[UInt8] = pb.value;
        if !same_bytes(&pbv, &fx, off + 12, pr.size) { bytes_ok = false; }
      }
      if have_dec {
        var snd = ffmpeg_decoder_send(&dec, pr.packet);
        if snd == FFMPEG_ERR_EAGAIN {
          var more = true;
          var dguard = 0;
          while more && dguard < 16 {
            let fr0 = ffmpeg_decoder_receive(&dec);
            if fr0.kind == FFMPEG_DECODE_FRAME {
              frames = frames + 1;
              if fw == 0 { fw = fr0.width; fh = fr0.height; fp = fr0.pix_fmt_name; }
              ffmpeg_frame_unref(&dec, fr0.frame);
              var igf0 = ffmpeg_frame_free(&dec, fr0.frame);
            } else {
              if fr0.kind == FFMPEG_DECODE_ERROR { drain_err = drain_err + 1; }
              more = false;
            }
            dguard = dguard + 1;
          }
          resends = resends + 1;
          snd = ffmpeg_decoder_send(&dec, pr.packet);
        }
        if snd == FFMPEG_ERR_ENOSYS {
          // Native hwaccel-only decoder -> the feed check becomes SKIP.
          have_dec = false;
        } elif snd != 0 {
          send_err = send_err + 1;
        }
      }
      off = off + 12 + esz;
      frames_seen = frames_seen + 1;
      ffmpeg_demux_packet_unref(&demux, pr.packet);
      var igf = ffmpeg_demux_packet_free(&demux, pr.packet);
      i = i + 1;
    }
  }
  let eofpr = ffmpeg_demux_read_packet(&demux);
  let saw_eof = eofpr.eof && !eofpr.ok;

  out = out + report(packets == nframes && sizes_ok && frames_seen == nframes && saw_eof,
    "demux: packet loop " + i2s(packets) + "/" + i2s(nframes) + " sizes match IVF framing (eof="
      + b2s(saw_eof) + ")");
  out = out + report(bytes_ok && first_flags >= 0,
    "demux: packet bytes match container payload (first flags=" + i2s(first_flags) + ")");
  out = out + report(meta_ok, "demux: packet stream_index/pts match IVF header");

  if have_dec {
    var flush_rc = -1;
    var saw_dec_eof = false;
    var phase = 0;
    while phase < 2 {
      var terminal = false;
      var guard = 0;
      while !terminal && guard < 64 {
        let fr = ffmpeg_decoder_receive(&dec);
        if fr.kind == FFMPEG_DECODE_FRAME {
          frames = frames + 1;
          if fw == 0 { fw = fr.width; fh = fr.height; fp = fr.pix_fmt_name; }
          ffmpeg_frame_unref(&dec, fr.frame);
          var igf2 = ffmpeg_frame_free(&dec, fr.frame);
        } elif fr.kind == FFMPEG_DECODE_AGAIN {
          terminal = true;
        } elif fr.kind == FFMPEG_DECODE_EOF {
          terminal = true;
          saw_dec_eof = true;
        } else {
          drain_err = drain_err + 1;
          terminal = true;
        }
        guard = guard + 1;
      }
      if phase == 0 { flush_rc = ffmpeg_decoder_flush(&dec); }
      phase = phase + 1;
    }
    let cld = ffmpeg_decoder_close(&dec);
    out = out + report(frames == nframes && fw == iw && fh == ih && flush_rc == 0
        && send_err == 0 && drain_err == 0 && saw_dec_eof && cld.is_ok,
      "demux->decode: " + i2s(frames) + " frame(s) " + i2s(fw) + "x" + i2s(fh) + " " + fp
        + " from demuxed packets (flush rc=" + i2s(flush_rc) + ", send errors=" + i2s(send_err)
        + ", resends=" + i2s(resends) + ")");
  } else {
    if dres.is_ok {
      // A decoder was opened but is hardware-accelerated-only (ENOSYS on
      // the first demuxed packet): release it, the feed check is SKIP.
      var hcl = ffmpeg_decoder_close(&dec);
    }
    out = out + report(true, "demux->decode: SKIP -- no usable AV1 decoder for the demux feed check");
  }

  let sk = ffmpeg_demux_seek(&demux, 0, 0, FFMPEG_SEEK_BACKWARD);
  var rp = 0;
  var rpts0 = -1;
  var rguard = 0;
  if sk.ok {
    while rguard < 8 {
      let pr2 = ffmpeg_demux_read_packet(&demux);
      if !pr2.ok {
        rguard = 8;
      } else {
        if rp == 0 { rpts0 = pr2.pts; }
        rp = rp + 1;
        ffmpeg_demux_packet_unref(&demux, pr2.packet);
        var igf3 = ffmpeg_demux_packet_free(&demux, pr2.packet);
        rguard = rguard + 1;
      }
    }
  }
  out = out + report(sk.ok && rp == nframes && rpts0 == 0,
    "demux: seek(0, BACKWARD) rc=" + i2s(sk.rc) + " re-read " + i2s(rp) + "/" + i2s(nframes)
      + " packet(s), first pts=" + i2s(rpts0));

  let dc = ffmpeg_demux_close(&demux);
  out = out + report(dc.is_ok, "demux: demuxer closed");
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
    failed = failed + report(true, "decode+demux: SKIP -- no FFmpeg shared-library generation present");
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

    // Container demux surface (0.4.0; SKIP-classified per check).
    failed = run_demux_section(&lib, failed);

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
