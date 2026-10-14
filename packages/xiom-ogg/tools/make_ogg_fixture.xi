// xiom.ogg -- fixture generator: mux a real Opus tone into `tone.ogg`.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Builds `tests/fixtures/tone.ogg` from scratch at development time:
//
//   1. encode a 25-frame (0.5 s) 440 Hz tone at 48 kHz mono with xiom.opus
//      (64 kbps VBR),
//   2. build the OpusHead + OpusTags identification headers,
//   3. mux everything with the libogg write path (xiom.ogg.mux OggMuxer:
//      packetin + pageout/flush + page checksums),
//   4. write the page bytes to tests/fixtures/tone.ogg.
//
// The committed fixture is the mux-side evidence; the ogg conformance suite
// demuxes it again (and validates every page against the independent pure-
// XIOM page walk + CRC-32 oracle).
//
// RUNNING THIS FILE (module resolution is package-scoped, so the generator
// must execute from the repo's `packages/` directory where both xiom.opus
// and xiom.ogg modules are visible):
//
//   copy packages/xiom-ogg/tools/make_ogg_fixture.xi packages/.gen_fixture.xi
//   cd packages
//   xiom --run .gen_fixture.xi --c-source xiom-ogg/src/ogg_bridge.c \
//     --c-source xiom-ogg/vendor/ogg/bitwise.c \
//     --c-source xiom-ogg/vendor/ogg/framing.c \
//     --c-source xiom-opus/src/opus_bridge.c \
//     --c-source xiom-opus/src/opus_vendor_celt.c \
//     --c-source xiom-opus/src/opus_vendor_silk.c \
//     --c-source xiom-opus/src/opus_vendor_silk_float.c \
//     --c-source xiom-opus/src/opus_vendor_src.c --timeout 900
//   del packages/.gen_fixture.xi
//
// (helper: tools/gen_fixture.ps1 does exactly this and moves the output
// into place).

module ogg_fixture_gen

use xiom.io;
use xiom.math;
use xiom.string;
use xiom.opus;
use xiom.opus.abi;
use xiom.ogg.mux;
use xiom.ogg.types;

fn push_i16(v: &mut Vec[UInt8], s: Int) {
  v.push((s & 255) as UInt8);
  v.push(((s >> 8) & 255) as UInt8);
}

fn push_i32(v: &mut Vec[UInt8], x: Int) {
  v.push((x & 255) as UInt8);
  v.push(((x >> 8) & 255) as UInt8);
  v.push(((x >> 16) & 255) as UInt8);
  v.push(((x >> 24) & 255) as UInt8);
}

fn push_text(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn tone(frame_size: Int, offset: Int) -> Vec[UInt8] {
  var pcm: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < frame_size {
    let t = ((offset + i) as Float64) / 48000.0;
    let s = (math.sin(2.0 * 3.14159265358979 * 440.0 * t) * 12000.0) as Int;
    push_i16(&mut pcm, s);
    i = i + 1;
  }
  return pcm;
}

fn main() -> Int {
  io.println("== ogg fixture generator ==");
  // 1. encode the tone.
  let er = Encoder.create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
  if !er.is_ok {
    io.println("encoder create failed: " + er.error.message);
    return 1;
  }
  let enc = er.value;
  let br = Encoder.set_bitrate(&enc, 64000);
  let lr = Encoder.lookahead(&enc);
  var preskip = 312;
  if lr.is_ok {
    preskip = lr.value;
  }
  io.println("lookahead/preskip=" + preskip);
  var blob: Vec[UInt8] = Vec[UInt8].new();
  var lens: Vec[Int] = Vec[Int].new();
  var frame = 0;
  while frame < 25 {
    var out = slot_bytes(1024);
    let pcm = tone(960, frame * 960);
    let r = Encoder.encode(&enc, &pcm, 960, &mut out);
    if !r.is_ok {
      io.println("encode failed at frame " + frame);
      return 2;
    }
    lens.push(r.value);
    var i = 0;
    while i < r.value {
      blob.push(out[i]);
      i = i + 1;
    }
    frame = frame + 1;
  }
  Encoder.destroy(&enc);
  io.println("encoded packets=" + lens.len());

  // 2. identification headers.
  var head: Vec[UInt8] = Vec[UInt8].new();
  push_text(&mut head, "OpusHead");
  head.push(1 as UInt8);            // version
  head.push(1 as UInt8);            // channels
  push_i16(&mut head, preskip);
  push_i32(&mut head, 48000);
  push_i16(&mut head, 0);           // gain
  head.push(0 as UInt8);            // mapping family 0
  var tags: Vec[UInt8] = Vec[UInt8].new();
  push_text(&mut tags, "OpusTags");
  let vendor = "xiom.fixture";
  push_i32(&mut tags, vendor.len());
  push_text(&mut tags, vendor);
  push_i32(&mut tags, 0);

  // 3. mux.
  let mxr = OggMuxer.create(1330664521);
  if !mxr.is_ok {
    io.println("muxer create failed");
    return 3;
  }
  let mx = mxr.value;
  var all: Vec[UInt8] = Vec[UInt8].new();
  var pages = 0;
  let h1 = OggMuxer.add(&mx, &head, 0, true, false);
  if !h1.is_ok { return 4; }
  pages = pages + drain_flush(&mx, &mut all);
  let t1 = OggMuxer.add(&mx, &tags, 0, false, false);
  if !t1.is_ok { return 5; }
  pages = pages + drain_flush(&mx, &mut all);
  var n = 0;
  var offset = 0;
  while n < lens.len() {
    let gp = preskip + (n + 1) * 960;
    var eos = false;
    if n == lens.len() - 1 {
      eos = true;
    }
    var pkt: Vec[UInt8] = Vec[UInt8].new();
    var k = 0;
    while k < lens[n] {
      pkt.push(blob[offset + k]);
      k = k + 1;
    }
    offset = offset + lens[n];
    let pr = OggMuxer.add(&mx, &pkt, gp, false, eos);
    if !pr.is_ok { return 6; }
    pages = pages + drain_pages(&mx, &mut all);
    n = n + 1;
  }
  pages = pages + drain_flush(&mx, &mut all);
  OggMuxer.destroy(&mx);
  io.println("muxed pages=" + pages + " bytes=" + all.len());

  // 4. write.
  // run from packages/: target the ogg package's fixtures dir
  let wr = io.write_file_bytes("xiom-ogg/tests/fixtures/tone.ogg", &all);
  if !wr.is_ok {
    io.println("write failed");
    return 7;
  }
  io.println("wrote xiom-ogg/tests/fixtures/tone.ogg (" + all.len() + " bytes)");
  return 0;
}

fn slot_bytes(n: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

fn append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

// Drain all currently available pages into `all`; returns the page count.
// Flush the muxer and append the emitted page (headers get their own pages).
fn drain_flush(mx: &OggMuxer, all: &mut Vec[UInt8]) -> Int {
  let fr = OggMuxer.flush(mx);
  if fr.is_ok {
    if fr.value.found {
      append_bytes(all, &page_bytes(&fr.value));
      return 1;
    }
  }
  return 0;
}

fn drain_pages(mx: &OggMuxer, all: &mut Vec[UInt8]) -> Int {
  var count = 0;
  var guard = 0;
  while guard < 64 {
    let pr = OggMuxer.page(mx);
    if !pr.is_ok {
      guard = 64;
    } else {
      if !pr.value.found {
        guard = 64;
      } else {
        append_bytes(all, &page_bytes(&pr.value));
        count = count + 1;
      }
    }
  }
  return count;
}
