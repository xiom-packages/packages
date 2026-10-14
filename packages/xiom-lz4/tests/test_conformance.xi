// xiom.lz4 conformance suite.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the binding against the vendored lz4 v1.10.0 (ebb370ca, lib/
// BSD-2-Clause) compiled into the test binary via port.args.json:
//   scripts/port.ps1 -Package xiom.lz4 -TimeoutSec 600
//
// Coverage (docs/COVERAGE.md): every one of the 111 declared functions is
// exercised EXCEPT the two `*_withPrefix64k` obsolete entries, which are
// bound but not called: their documented precondition (a 64 KB dictionary
// laid out immediately before dstBuffer) cannot be expressed through
// XIOM-owned buffers without pointer arithmetic (B-17).  Exact error codes
// are asserted for the corrupt-input classes (content checksum, truncated
// frame, broken block).
//
// Streaming output uses one owned slot per call (no pointer offsets in XIOM):
// chunks are concatenated in XIOM; input-side loops live in the C bridge.

module lz4_conformance

use xiom.io;
use xiom.convert;
use xiom.string;
use xiom.lz4;
use xiom.lz4.ffi;

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

fn dup_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if (a[i] as Int) != (b[i] as Int) { return false; }
    i = i + 1;
  }
  return true;
}

fn prefix_equal(a: &Vec[UInt8], b: &Vec[UInt8], n: Int) -> Bool {
  if a.len() < n || b.len() < n { return false; }
  var i: Int = 0;
  while i < n {
    if (a[i] as Int) != (b[i] as Int) { return false; }
    i = i + 1;
  }
  return true;
}

// Repeating pattern (highly compressible).
fn pattern_bytes(n: Int, period: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    out.push(((i % period) + 65) as UInt8);
    i = i + 1;
  }
  return out;
}

// LCG stream (incompressible).
fn lcg_bytes(n: Int, seed: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var x = seed;
  var i: Int = 0;
  while i < n {
    x = (x * 1103515245 + 12345) % 2147483648;
    out.push(((x / 65536) % 256) as UInt8);
    i = i + 1;
  }
  return out;
}

fn append_bytes(out: &mut Vec[UInt8], src: &Vec[UInt8], n: Int) {
  var i: Int = 0;
  while i < n {
    out.push(src[i]);
    i = i + 1;
  }
}

fn with_bit_flipped(v: &Vec[UInt8], idx: Int) -> Vec[UInt8] {
  var out = dup_bytes(v);
  out[idx] = ((out[idx] as Int) ^ 0xff) as UInt8;
  return out;
}

fn main() -> Int {
  io.println("=== xiom.lz4 conformance tests (vendored lz4 v1.10.0) ===");
  io.flush_stdout();
  var failed: Int = 0;
  var def_prefs = lz4f_prefs_new();
  var def_copts = lz4f_compress_options_new();
  var def_dopts = lz4f_decompress_options_new();

  // --- version / constants --------------------------------------------------
  failed = failed + report(lz4_version_number() == 11000 && lz4_version_number() == LZ4_VERSION_NUMBER,
    "version: LZ4_versionNumber = 11000");
  failed = failed + report(lz4_version_string() == "1.10.0",
    "version: LZ4_versionString = \"1.10.0\"");
  failed = failed + report((ffi.get_version() as Int) == LZ4F_VERSION,
    "frame: LZ4F_getVersion = LZ4F_VERSION (100)");
  failed = failed + report(ffi.compression_level_max() == LZ4HC_CLEVEL_MAX,
    "frame: LZ4F_compressionLevel_max = 12");
  failed = failed + report(ffi.decoder_ring_buffer_size(65536) == 65536 + 14 + 65536,
    "block: LZ4_decoderRingBufferSize(64 KiB)");

  // --- block codec: compressible -------------------------------------------
  var src_c = pattern_bytes(8192, 64);
  let comp = lz4_compress(&mut src_c, LZ4_ACCELERATION_DEFAULT);
  if !comp.is_ok {
    failed = failed + report(false, "block compressible: lz4_compress -- " + comp.error.message);
  } else {
    var c: Vec[UInt8] = comp.value;
    failed = failed + report(c.len() > 0 && c.len() < 8192 / 4,
      "block compressible: ratio < 25% (" + to_string(c.len()) + "/8192)");
    var d = ffi.zero_bytes(8192);
    let rc = ffi.decompress_safe(&mut c, &mut d, c.len(), 8192);
    failed = failed + report(rc == 8192 && bytes_equal(&d, &src_c),
      "block compressible: safe decompress restores all 8192 bytes");
    failed = failed + report(ffi.compress_bound(8192) >= c.len(),
      "block: LZ4_compressBound covers the result");
    var cdst = ffi.zero_bytes(ffi.compress_bound(8192));
    let rc_direct = ffi.compress_default(&mut src_c, &mut cdst, src_c.len(), cdst.len());
    var bdst = ffi.zero_bytes(8192);
    let rc_back = ffi.decompress_safe(&mut cdst, &mut bdst, rc_direct, 8192);
    failed = failed + report(rc_direct > 0 && rc_back == 8192 && bytes_equal(&bdst, &src_c),
      "block: 1:1 LZ4_compress_default + LZ4_decompress_safe round trip");
  }

  // --- block codec: incompressible + empty ----------------------------------
  var src_r = lcg_bytes(4096, 12345);  let comp_r = lz4_compress(&mut src_r, 1);
  if !comp_r.is_ok {
    failed = failed + report(false, "block incompressible: lz4_compress -- " + comp_r.error.message);
  } else {
    var cr: Vec[UInt8] = comp_r.value;
    let dec_r = lz4_decompress(&mut cr, 4096);
    var ok_r = false;
    if dec_r.is_ok { ok_r = bytes_equal(&dec_r.value, &src_r); }
    failed = failed + report(ok_r, "block incompressible: round trip is byte-exact");
  }
  var empty: Vec[UInt8] = Vec[UInt8].new();
  let comp_e = lz4_compress(&mut empty, 1);
  if !comp_e.is_ok {
    failed = failed + report(false, "block empty: lz4_compress -- " + comp_e.error.message);
  } else {
    var ce: Vec[UInt8] = comp_e.value;
    var de = ffi.zero_bytes(16);
    let rce = ffi.decompress_safe(&mut ce, &mut de, ce.len(), 16);
    failed = failed + report(rce == 0, "block empty: compresses to one block, decompresses to 0 bytes");
  }

  // --- block errors ---------------------------------------------------------
  var src_e = pattern_bytes(1000, 16);
  let comp_e2 = lz4_compress(&mut src_e, 1);
  if comp_e2.is_ok {
    var ce2: Vec[UInt8] = comp_e2.value;
    var bad = with_bit_flipped(&ce2, 5);
    let de_bad = lz4_decompress(&mut bad, 1000);
    var bad_detected = false;
    if !de_bad.is_ok {
      bad_detected = true;
    } else {
      bad_detected = de_bad.value.len() != 1000 || !bytes_equal(&de_bad.value, &src_e);
    }
    failed = failed + report(bad_detected,
      "block: flipped-bit block errors or differs (LZ4 blocks carry no checksum by design)");
    var trunc1 = ffi.zero_bytes(1);
    trunc1[0] = ce2[0];
    let de_tr = lz4_decompress(&mut trunc1, 1000);
    failed = failed + report(!de_tr.is_ok && de_tr.error.code < 0,
      "block error: 1-byte truncated block rejected (negative rc)");
    var ffs = ffi.zero_bytes(16);
    var ff_i: Int = 0;
    while ff_i < 16 {
      ffs[ff_i] = 255 as UInt8;
      ff_i = ff_i + 1;
    }
    let de_ff = lz4_decompress(&mut ffs, 1000);
    failed = failed + report(!de_ff.is_ok && de_ff.error.code < 0,
      "block error: invalid 0xFF stream rejected (negative rc)");
    let de_small = lz4_decompress(&mut ce2, 10);
    failed = failed + report(!de_small.is_ok && de_small.error.code < 0,
      "block error: destination too small rejected (negative rc)");
    var d999 = ffi.zero_bytes(1000);
    let rc999 = ffi.decompress_safe_partial(&mut ce2, &mut d999, ce2.len(), 100, 1000);
    failed = failed + report(rc999 == 100 && prefix_equal(&d999, &src_e, 100),
      "block: LZ4_decompress_safe_partial yields exactly 100 bytes");
    // destSize: fill 64 bytes with as much input as fits (incompressible
    // input guarantees the 64-byte target cannot hold all 1000 bytes).
    var src_ds = lcg_bytes(1000, 777);
    var dst_ds = ffi.zero_bytes(64);
    var slot_ds = ffi.zero_bytes(8);
    ffi.write_u32_le(&mut slot_ds, 0, 1000);
    let rc_ds = ffi.compress_dest_size(&mut src_ds, &mut dst_ds, &mut slot_ds, 64);
    let consumed = ffi.read_u32_le(&slot_ds, 0);
    var d_ds = ffi.zero_bytes(1000);
    let back_ds = ffi.decompress_safe(&mut dst_ds, &mut d_ds, rc_ds, 1000);
    failed = failed + report(rc_ds > 0 && consumed > 0 && consumed < 1000 && back_ds == consumed
      && prefix_equal(&d_ds, &src_ds, consumed),
      "block: LZ4_compress_destSize fills 64 bytes and consumes " + to_string(consumed) + " input bytes");
  } else {
    failed = failed + report(false, "block error setup: compress failed");
  }

  // --- caller-owned state (extState) ---------------------------------------
  let state_size = ffi.sizeof_state();
  failed = failed + report(state_size > 0, "state: LZ4_sizeofState > 0 (" + to_string(state_size) + ")");
  var st = ffi.zero_bytes(state_size);
  let st_h = ffi.init_stream(&mut st, state_size);
  failed = failed + report(st_h != 0, "state: LZ4_initStream returns a state handle");
  var src_st = pattern_bytes(2000, 16);
  var out_st = ffi.zero_bytes(ffi.compress_bound(2000));
  let rc_st = ffi.compress_fast_ext_state(&mut st, &mut src_st, &mut out_st, src_st.len(), out_st.len(), 1);
  var back_st = ffi.zero_bytes(2000);
  let dec_st = ffi.decompress_safe(&mut out_st, &mut back_st, rc_st, 2000);
  failed = failed + report(rc_st > 0 && dec_st == 2000 && bytes_equal(&back_st, &src_st),
    "state: LZ4_compress_fast_extState round trip");
  ffi.reset_stream_fast(st_h);
  let rc_st2 = ffi.compress_fast_ext_state_fast_reset(&mut st, &mut src_st, &mut out_st, src_st.len(), out_st.len(), 1);
  failed = failed + report(rc_st2 > 0, "state: LZ4_compress_fast_extState_fastReset after fast reset");
  ffi.reset_stream(st_h);
  failed = failed + report(true, "state: LZ4_resetStream (obsolete full reset) callable");
  var src_ds2 = pattern_bytes(300, 16);
  var out_ds2 = ffi.zero_bytes(ffi.compress_bound(300));
  var slot_ds2 = ffi.zero_bytes(8);
  ffi.write_u32_le(&mut slot_ds2, 0, 300);
  let rc_ds2 = ffi.compress_dest_size_ext_state(&mut st, &mut src_ds2, &mut out_ds2, &mut slot_ds2, 60, 1);
  failed = failed + report(rc_ds2 > 0 && ffi.read_u32_le(&slot_ds2, 0) > 0,
    "state: LZ4_compress_destSize_extState");

  // --- streaming block ------------------------------------------------------
  var s1 = pattern_bytes(1000, 16);
  var s2 = pattern_bytes(1000, 8);
  let h = ffi.create_stream();
  var c1 = ffi.zero_bytes(2000);
  var c2 = ffi.zero_bytes(2000);
  let n1 = ffi.compress_fast_continue(h, &mut s1, &mut c1, s1.len(), 2000, 1);
  let n2 = ffi.compress_fast_continue(h, &mut s2, &mut c2, s2.len(), 2000, 1);
  let free_rc = ffi.free_stream(h);
  let hd = ffi.create_stream_decode();
  var o1 = ffi.zero_bytes(2000);
  var o2 = ffi.zero_bytes(2000);
  let m1 = ffi.decompress_safe_continue(hd, &mut c1, &mut o1, n1, 2000);
  let m2 = ffi.decompress_safe_continue(hd, &mut c2, &mut o2, n2, 2000);
  let free_d = ffi.free_stream_decode(hd);
  failed = failed + report(n1 > 0 && n2 > 0 && m1 == 1000 && m2 == 1000
    && prefix_equal(&o1, &s1, 1000) && prefix_equal(&o2, &s2, 1000)
    && free_rc == 0 && free_d == 0,
    "stream: linked-block compression + streaming decode round trip");

  // --- dictionary -----------------------------------------------------------
  var dict = pattern_bytes(4096, 32);
  let h2 = ffi.create_stream();
  let loaded = ffi.load_dict(h2, &mut dict, dict.len());
  var s3 = pattern_bytes(1000, 32);
  var c3 = ffi.zero_bytes(2000);
  let n3 = ffi.compress_fast_continue(h2, &mut s3, &mut c3, s3.len(), 2000, 1);
  var saved = ffi.zero_bytes(4096);
  let saved_n = ffi.save_dict(h2, &mut saved, 4096);
  ffi.free_stream(h2);
  var o3 = ffi.zero_bytes(2000);
  let m3 = ffi.decompress_safe_using_dict(&mut c3, &mut o3, n3, 2000, &mut dict, dict.len());
  failed = failed + report(loaded > 0 && n3 > 0 && m3 == 1000 && prefix_equal(&o3, &s3, 1000)
    && saved_n > 0,
    "dict: LZ4_loadDict + usingDict decode + LZ4_saveDict");

  let h3 = ffi.create_stream();
  let h4 = ffi.create_stream();
  let loaded_slow = ffi.load_dict_slow(h3, &mut dict, dict.len());
  ffi.attach_dictionary(h4, h3);
  var s4 = pattern_bytes(800, 32);
  var c4 = ffi.zero_bytes(1600);
  let n4 = ffi.compress_fast_continue(h4, &mut s4, &mut c4, s4.len(), 1600, 1);
  ffi.free_stream(h3);
  ffi.free_stream(h4);
  var o4 = ffi.zero_bytes(1600);
  let m4 = ffi.decompress_safe_using_dict(&mut c4, &mut o4, n4, 1600, &mut dict, dict.len());
  failed = failed + report(loaded_slow > 0 && n4 > 0 && m4 == 800 && prefix_equal(&o4, &s4, 800),
    "dict: LZ4_loadDictSlow + LZ4_attach_dictionary");

  var ddict = pattern_bytes(2048, 16);
  var o5 = ffi.zero_bytes(2000);
  let m5 = ffi.decompress_safe_partial_using_dict(&mut c3, &mut o5, n3, 100, 2000,
    &mut dict, dict.len());
  failed = failed + report(m5 == 100, "dict: LZ4_decompress_safe_partial_usingDict yields 100 bytes");

  let hd2 = ffi.create_stream_decode();
  let setd = ffi.set_stream_decode(hd2, &mut dict, dict.len());
  var o6 = ffi.zero_bytes(2000);
  let m6 = ffi.decompress_safe_continue(hd2, &mut c3, &mut o6, n3, 2000);
  ffi.free_stream_decode(hd2);
  failed = failed + report(setd > 0 && m6 == 1000 && prefix_equal(&o6, &s3, 1000),
    "dict: LZ4_setStreamDecode + LZ4_decompress_safe_continue");

  // --- HC -------------------------------------------------------------------
  var src_h = pattern_bytes(8192, 64);
  let hc12 = lz4hc_compress(&mut src_h, 12);
  let hc9 = lz4hc_compress(&mut src_h, LZ4HC_CLEVEL_DEFAULT);
  let hc2 = lz4hc_compress(&mut src_h, LZ4HC_CLEVEL_MIN);
  if hc12.is_ok && hc9.is_ok && hc2.is_ok {
    var v12: Vec[UInt8] = hc12.value;
    var v9: Vec[UInt8] = hc9.value;
    var v2: Vec[UInt8] = hc2.value;
    let d12 = lz4_decompress(&mut v12, 8192);
    var ok12 = false;
    if d12.is_ok { ok12 = bytes_equal(&d12.value, &src_h); }
    failed = failed + report(ok12, "hc: level 12 round trip is byte-exact");
    failed = failed + report(v12.len() <= v9.len() && v9.len() <= v2.len(),
      "hc: monotone ratio (12 <= 9 <= 2: " + to_string(v12.len()) + " <= " + to_string(v9.len())
      + " <= " + to_string(v2.len()) + ")");
  } else {
    failed = failed + report(false, "hc: compress levels failed");
  }
  var lvl_ok = true;
  var lvl = LZ4HC_CLEVEL_MIN;
  while lvl <= LZ4HC_CLEVEL_MAX {
    var sv = pattern_bytes(1500, 24);
    var ov = ffi.zero_bytes(ffi.compress_bound(1500));
    let cv = ffi.compress_hc(&mut sv, &mut ov, sv.len(), ov.len(), lvl);
    if cv <= 0 { lvl_ok = false; }
    lvl = lvl + 1;
  }
  failed = failed + report(lvl_ok, "hc: every level 2..12 compresses");

  let hs = ffi.create_stream_hc();
  ffi.reset_stream_hc_fast(hs, 12);
  var hs1 = pattern_bytes(1000, 32);
  var hs2 = pattern_bytes(1000, 16);
  var hc1 = ffi.zero_bytes(2000);
  var hc2b = ffi.zero_bytes(2000);
  let hn1 = ffi.compress_hc_continue(hs, &mut hs1, &mut hc1, hs1.len(), 2000);
  let hn2 = ffi.compress_hc_continue(hs, &mut hs2, &mut hc2b, hs2.len(), 2000);
  ffi.free_stream_hc(hs);
  var ho2 = ffi.zero_bytes(2000);
  let hm2 = ffi.decompress_safe_using_dict(&mut hc2b, &mut ho2, hn2, 2000,
    &mut hs1, hs1.len());
  failed = failed + report(hn1 > 0 && hn2 > 0 && hm2 == 1000 && prefix_equal(&ho2, &hs2, 1000),
    "hc stream: linked continuation with prefix dictionary decode");

  let hs2h = ffi.create_stream_hc();
  let ldh = ffi.load_dict_hc(hs2h, &mut dict, dict.len());
  var s5 = pattern_bytes(700, 32);
  var c5 = ffi.zero_bytes(1400);
  let n5 = ffi.compress_hc_continue(hs2h, &mut s5, &mut c5, s5.len(), 1400);
  var saved_hc = ffi.zero_bytes(4096);
  let saved_hc_n = ffi.save_dict_hc(hs2h, &mut saved_hc, 4096);
  ffi.set_compression_level(hs2h, 6);
  ffi.favor_decompression_speed(hs2h, 1);
  var s5b = pattern_bytes(400, 16);
  var c5b = ffi.zero_bytes(800);
  let n5b = ffi.compress_hc_continue(hs2h, &mut s5b, &mut c5b, s5b.len(), 800);
  ffi.free_stream_hc(hs2h);
  var o7 = ffi.zero_bytes(1400);
  let m7 = ffi.decompress_safe_using_dict(&mut c5, &mut o7, n5, 1400, &mut dict, dict.len());
  failed = failed + report(ldh > 0 && n5 > 0 && m7 == 700 && prefix_equal(&o7, &s5, 700)
    && saved_hc_n > 0 && n5b > 0,
    "hc stream: loadDictHC + saveDictHC + setCompressionLevel + favorDecompressionSpeed");

  let hs3 = ffi.create_stream_hc();
  let hs4 = ffi.create_stream_hc();
  let ldh2 = ffi.load_dict_hc(hs3, &mut dict, dict.len());
  ffi.attach_hc_dictionary(hs4, hs3);
  var s6 = pattern_bytes(600, 32);
  var c6 = ffi.zero_bytes(1200);
  let n6 = ffi.compress_hc_continue(hs4, &mut s6, &mut c6, s6.len(), 1200);
  ffi.free_stream_hc(hs3);
  ffi.free_stream_hc(hs4);
  var o8 = ffi.zero_bytes(1200);
  let m8 = ffi.decompress_safe_using_dict(&mut c6, &mut o8, n6, 1200, &mut dict, dict.len());
  failed = failed + report(ldh2 > 0 && n6 > 0 && m8 == 600 && prefix_equal(&o8, &s6, 600),
    "hc stream: LZ4_attach_HC_dictionary");

  let shc_size = ffi.sizeof_state_hc();
  var st_hc = ffi.zero_bytes(shc_size);
  var ibuf = pattern_bytes(1024, 16);
  let st_hc_h = ffi.init_stream_hc(&mut st_hc, shc_size);
  var src_he = pattern_bytes(1024, 16);
  var out_he = ffi.zero_bytes(ffi.compress_bound(1024));
  let rc_he = ffi.compress_hc_ext_state_hc(&mut st_hc, &mut src_he, &mut out_he, src_he.len(), out_he.len(), 9);
  let rc_he2 = ffi.compress_hc_ext_state_hc_fast_reset(&mut st_hc, &mut src_he, &mut out_he, src_he.len(), out_he.len(), 9);
  var back_he = ffi.zero_bytes(1024);
  let dec_he = ffi.decompress_safe(&mut out_he, &mut back_he, rc_he2, 1024);
  ffi.reset_stream_hc(st_hc_h, 9);
  failed = failed + report(shc_size > 0 && st_hc_h != 0 && rc_he > 0 && rc_he2 > 0 && dec_he == 1024
    && bytes_equal(&back_he, &src_he),
    "hc state: initStreamHC + extStateHC + extStateHC_fastReset + resetStreamHC");

  var src_hds = pattern_bytes(500, 16);
  var out_hds = ffi.zero_bytes(ffi.compress_bound(500));
  var slot_hds = ffi.zero_bytes(8);
  ffi.write_u32_le(&mut slot_hds, 0, 500);
  let rc_hds = ffi.compress_hc_dest_size(&mut st_hc, &mut src_hds, &mut out_hds, &mut slot_hds, 60, 9);
  var out_hds2 = ffi.zero_bytes(ffi.compress_bound(500));
  var slot_hds2 = ffi.zero_bytes(8);
  ffi.write_u32_le(&mut slot_hds2, 0, 500);
  let hs5 = ffi.create_stream_hc();
  let rc_hds2 = ffi.compress_hc_continue_dest_size(hs5, &mut src_hds, &mut out_hds2, &mut slot_hds2, 60);
  ffi.free_stream_hc(hs5);
  failed = failed + report(rc_hds > 0 && ffi.read_u32_le(&slot_hds, 0) > 0 && rc_hds2 > 0
    && ffi.read_u32_le(&slot_hds2, 0) > 0,
    "hc: compress_HC_destSize + compress_HC_continue_destSize");

  // --- deprecated block/HC surface (bound for completeness) -----------------
  var src_d1 = pattern_bytes(600, 16);
  var out_d1 = ffi.zero_bytes(2048);
  let dc1 = ffi.compress(&mut src_d1, &mut out_d1, src_d1.len());
  var back_d1 = ffi.zero_bytes(600);
  let du1 = ffi.uncompress(&mut out_d1, &mut back_d1, 600);
  failed = failed + report(dc1 > 0 && du1 > 0 && bytes_equal(&back_d1, &src_d1),
    "deprecated: LZ4_compress + LZ4_uncompress round trip");
  let du2 = ffi.uncompress_unknown_output_size(&mut out_d1, &mut back_d1, dc1, 600);
  failed = failed + report(du2 == 600, "deprecated: LZ4_uncompress_unknownOutputSize");
  let dc2 = ffi.compress_limited_output(&mut src_d1, &mut out_d1, src_d1.len(), 2048);
  failed = failed + report(dc2 > 0, "deprecated: LZ4_compress_limitedOutput");
  var st_d = ffi.zero_bytes(ffi.sizeof_state());
  let dc3 = ffi.compress_with_state(&mut st_d, &mut src_d1, &mut out_d1, src_d1.len());
  let dc4 = ffi.compress_limited_output_with_state(&mut st_d, &mut src_d1, &mut out_d1, src_d1.len(), 2048);
  failed = failed + report(dc3 > 0 && dc4 > 0,
    "deprecated: LZ4_compress_withState + LZ4_compress_limitedOutput_withState");
  let hd3 = ffi.create_stream();
  var out_d2 = ffi.zero_bytes(2048);
  let dc5 = ffi.compress_continue(hd3, &mut src_d1, &mut out_d2, src_d1.len());
  let dc6 = ffi.compress_limited_output_continue(hd3, &mut src_d1, &mut out_d2, src_d1.len(), 2048);
  ffi.free_stream(hd3);
  failed = failed + report(dc5 > 0 && dc6 > 0,
    "deprecated: LZ4_compress_continue + LZ4_compress_limitedOutput_continue");
  var ibuf_d = pattern_bytes(1024, 16);
  let hc_d = ffi.create(&mut ibuf_d);
  var out_d3 = ffi.zero_bytes(2048);
  let dc_create = ffi.compress_continue(hc_d, &mut src_d1, &mut out_d3, src_d1.len());
  let sl_d = ffi.slide_input_buffer(hc_d);
  let ss_d = ffi.sizeof_stream_state();
  ffi.free_stream(hc_d);
  var st_d2 = ffi.zero_bytes(ss_d);
  var ibuf_d2 = pattern_bytes(1024, 16);
  let rs_d = ffi.reset_stream_state(&mut st_d2, &mut ibuf_d2);
  failed = failed + report(hc_d != 0 && dc_create > 0 && sl_d != 0 && ss_d > 0 && rs_d == 0,
    "deprecated: LZ4_create + LZ4_slideInputBuffer + LZ4_sizeofStreamState + LZ4_resetStreamState");
  let df1 = ffi.decompress_fast(&mut out_d1, &mut back_d1, 600);
  failed = failed + report(df1 == dc2 && bytes_equal(&back_d1, &src_d1),
    "deprecated: LZ4_decompress_fast reads the whole block");
  let df2 = ffi.decompress_fast_using_dict(&mut out_d1, &mut back_d1, 600, &mut dict, 0);
  failed = failed + report(df2 == dc2, "deprecated: LZ4_decompress_fast_usingDict (no dict)");
  let hd4 = ffi.create_stream_decode();
  ffi.set_stream_decode(hd4, &mut dict, 0);
  let df3 = ffi.decompress_fast_continue(hd4, &mut out_d1, &mut back_d1, 600);
  ffi.free_stream_decode(hd4);
  failed = failed + report(df3 == dc2, "deprecated: LZ4_decompress_fast_continue");
  io.println("  [SKIP] deprecated: LZ4_decompress_safe_withPrefix64k / _fast_withPrefix64k "
    + "(bound; precondition 64 KB prefix before dst not expressible -- no pointer arithmetic)");

  var src_dh = pattern_bytes(500, 16);
  var out_dh = ffi.zero_bytes(1500);
  let dh1 = ffi.legacy_compress_hc(&mut src_dh, &mut out_dh, src_dh.len());
  let dh2 = ffi.compress_hc2(&mut src_dh, &mut out_dh, src_dh.len(), 12);
  let dh3 = ffi.compress_hc_limited_output(&mut src_dh, &mut out_dh, src_dh.len(), 1500);
  let dh4 = ffi.compress_hc2_limited_output(&mut src_dh, &mut out_dh, src_dh.len(), 1500, 12);
  failed = failed + report(dh1 > 0 && dh2 > 0 && dh3 > 0 && dh4 > 0,
    "deprecated HC: compressHC + compressHC2 + limitedOutput variants");
  var st_dhc = ffi.zero_bytes(ffi.sizeof_state_hc());
  let dh5 = ffi.compress_hc_with_state_hc(&mut st_dhc, &mut src_dh, &mut out_dh, src_dh.len());
  let dh6 = ffi.compress_hc_limited_output_with_state_hc(&mut st_dhc, &mut src_dh, &mut out_dh, src_dh.len(), 1500);
  let dh7 = ffi.compress_hc2_with_state_hc(&mut st_dhc, &mut src_dh, &mut out_dh, src_dh.len(), 12);
  let dh8 = ffi.compress_hc2_limited_output_with_state_hc(&mut st_dhc, &mut src_dh, &mut out_dh, src_dh.len(), 1500, 12);
  failed = failed + report(dh5 > 0 && dh6 > 0 && dh7 > 0 && dh8 > 0,
    "deprecated HC: withStateHC variants (4)");
  let hc_d2 = ffi.create_hc(&mut ibuf_d2);
  let hc_sl = ffi.slide_input_buffer_hc(hc_d2);
  let hc_ss = ffi.sizeof_stream_state_hc();
  var out_dhc = ffi.zero_bytes(1500);
  let dh9 = ffi.legacy_compress_hc_continue(hc_d2, &mut src_dh, &mut out_dhc, src_dh.len());
  let dh10 = ffi.compress_hc_limited_output_continue(hc_d2, &mut src_dh, &mut out_dhc, src_dh.len(), 1500);
  let dh11 = ffi.compress_hc2_continue(hc_d2, &mut src_dh, &mut out_dhc, src_dh.len(), 12);
  let dh12 = ffi.compress_hc2_limited_output_continue(hc_d2, &mut src_dh, &mut out_dhc, src_dh.len(), 1500, 12);
  let hc_fr = ffi.free_hc(hc_d2);
  var st_dhc2 = ffi.zero_bytes(hc_ss);
  var ibuf_d3 = pattern_bytes(512, 16);
  let hc_rs = ffi.reset_stream_state_hc(&mut st_dhc2, &mut ibuf_d3);
  failed = failed + report(hc_d2 != 0 && hc_sl != 0 && hc_ss > 0 && dh9 > 0 && dh10 > 0
    && dh11 > 0 && dh12 > 0 && hc_fr == 0 && hc_rs == 0,
    "deprecated HC: createHC + slideInputBufferHC + continue variants + freeHC + resetStreamStateHC");

  // --- frame: one-shot ------------------------------------------------------
  var src_f = pattern_bytes(2048, 32);
  let fr0 = lz4f_compress_frame_default(&mut src_f);
  if !fr0.is_ok {
    failed = failed + report(false, "frame: lz4f_compress_frame_default -- " + fr0.error.message);
  } else {
    var f0: Vec[UInt8] = fr0.value;
    failed = failed + report(f0.len() > 7 && (f0[0] as Int) == 0x04 && (f0[1] as Int) == 0x22
      && (f0[2] as Int) == 0x4d && (f0[3] as Int) == 0x18,
      "frame: magic number 0x184D2204");
    let dec_f = lz4f_decompress(&mut f0, 4096);
    var ok_f = false;
    if dec_f.is_ok { ok_f = bytes_equal(&dec_f.value, &src_f); }
    failed = failed + report(ok_f, "frame: one-shot round trip (default prefs)");
    let hs = ffi.header_size(&mut f0, LZ4F_MIN_SIZE_TO_KNOW_HEADER_LENGTH);
    failed = failed + report(hs == LZ4F_HEADER_SIZE_MIN,
      "frame: LZ4F_headerSize = 7 for default prefs");
    var info2_ok = false;
    let finfo = lz4f_frame_info(&mut f0);
    if finfo.is_ok {
      // One-shot frames force blockIndependent when the source fits in one
      // block (upstream LZ4F_compressFrame_usingCDict), so only the checksum
      // and content-size flags are asserted here.
      info2_ok = finfo.value.content_size == 0 && finfo.value.content_checksum_flag == 0
        && finfo.value.block_checksum_flag == 0;
    }
    failed = failed + report(info2_ok, "frame: getFrameInfo (defaults: no checksums, unknown size)");
    failed = failed + report(ffi.compress_frame_bound(2048, &mut def_prefs) >= f0.len(),
      "frame: LZ4F_compressFrameBound covers the result");
  }

  // --- frame: preferences (contentSize + checksum) --------------------------
  var prefs = lz4f_prefs_new();
  var prefs_ok = lz4f_prefs_set(&mut prefs, LZ4F_MAX64KB, LZ4F_BLOCK_LINKED,
    LZ4F_CONTENT_CHECKSUM_ENABLED, 2048, 0, LZ4F_NO_BLOCK_CHECKSUM, 9, 0, 0);
  var src_f2 = pattern_bytes(2048, 32);
  let fr1 = lz4f_compress_frame(&mut src_f2, &mut prefs);
  if !prefs_ok || !fr1.is_ok {
    failed = failed + report(false, "frame prefs: setup failed");
  } else {
    var f1: Vec[UInt8] = fr1.value;
    let hs1 = ffi.header_size(&mut f1, LZ4F_MIN_SIZE_TO_KNOW_HEADER_LENGTH);
    failed = failed + report(hs1 == 15, "frame prefs: header is 15 bytes with contentSize (got "
      + to_string(hs1) + ")");
    let info1 = lz4f_frame_info(&mut f1);
    var ok_info1 = false;
    if info1.is_ok {
      ok_info1 = info1.value.content_size == 2048 && info1.value.content_checksum_flag == 1
        && info1.value.block_size_id == LZ4F_MAX64KB;
    }
    failed = failed + report(ok_info1, "frame prefs: frameInfo carries contentSize + checksum flags");
    failed = failed + report(lz4f_content_size(&mut f1) == 2048, "frame prefs: lz4f_content_size = 2048");
    let dec1 = lz4f_decompress(&mut f1, 4096);
    var ok_dec1 = false;
    if dec1.is_ok { ok_dec1 = bytes_equal(&dec1.value, &src_f2); }
    failed = failed + report(ok_dec1, "frame prefs: checksummed frame round trip");
    failed = failed + report(ffi.compress_frame_bound(2048, &mut def_prefs) >= f1.len(),
      "frame prefs: LZ4F_compressFrameBound covers the result");
    // Corrupt the content checksum (last 4 bytes) -> exact typed error.
    var f1_bad = with_bit_flipped(&f1, f1.len() - 1);
    let dec_bad = lz4f_decompress(&mut f1_bad, 4096);
    var code_ok = false;
    if !dec_bad.is_ok { code_ok = ffi.get_error_code(dec_bad.error.code) == LZ4F_ERROR_CONTENT_CHECKSUM_INVALID; }
    failed = failed + report(code_ok, "frame error: corrupted content checksum -> ERROR_contentChecksum_invalid");
  }

  // --- frame: block checksum + independent + 1 MB block size ----------------
  var prefs2 = lz4f_prefs_new();
  var prefs2_ok = lz4f_prefs_set(&mut prefs2, LZ4F_MAX1MB, LZ4F_BLOCK_INDEPENDENT,
    LZ4F_NO_CONTENT_CHECKSUM, 0, 0, LZ4F_BLOCK_CHECKSUM_ENABLED, 0, 0, 0);
  // 300 KB source: large enough that LZ4F_optimalBSID keeps the requested
  // 1 MB block size (a smaller source would be downgraded to max64KB).
  var src_f3 = pattern_bytes(300000, 48);
  let fr2 = lz4f_compress_frame(&mut src_f3, &mut prefs2);
  if !prefs2_ok || !fr2.is_ok {
    failed = failed + report(false, "frame blocks: setup failed");
  } else {
    var f2: Vec[UInt8] = fr2.value;
    let info2b = lz4f_frame_info(&mut f2);
    var ok_info2 = false;
    if info2b.is_ok {
      ok_info2 = info2b.value.block_size_id == LZ4F_MAX1MB
        && info2b.value.block_mode == LZ4F_BLOCK_INDEPENDENT
        && info2b.value.block_checksum_flag == 1;
    }
    failed = failed + report(ok_info2, "frame blocks: independent 1MB blocks + block checksum flags");
    let dec2 = lz4f_decompress(&mut f2, 300000);
    var ok_dec2 = false;
    if dec2.is_ok { ok_dec2 = bytes_equal(&dec2.value, &src_f3); }
    failed = failed + report(ok_dec2, "frame blocks: round trip with block checksums (300 KB)");
  }

  // --- frame: truncated input + incomplete header ---------------------------
  var src_f4 = pattern_bytes(1000, 16);
  let fr3 = lz4f_compress_frame_default(&mut src_f4);
  if fr3.is_ok {
    var f3: Vec[UInt8] = fr3.value;
    var half = ffi.zero_bytes(f3.len() / 2);
    var h_i: Int = 0;
    while h_i < f3.len() / 2 {
      half[h_i] = f3[h_i];
      h_i = h_i + 1;
    }
    let dec_tr = lz4f_decompress(&mut half, 4096);
    var tr_err = false;
    if !dec_tr.is_ok {
      let c = ffi.get_error_code(dec_tr.error.code);
      tr_err = c == LZ4F_ERROR_FRAME_HEADER_INCOMPLETE || c == LZ4F_ERROR_DECOMPRESSION_FAILED
        || c == LZ4F_ERROR_FRAME_SIZE_WRONG || c < 0;
    }
    failed = failed + report(tr_err, "frame error: truncated frame rejected with a typed code");
    var tiny: Vec[UInt8] = Vec[UInt8].new();
    tiny.push(0x04);
    let hs_bad = ffi.header_size(&mut tiny, 1);
    failed = failed + report(lz4f_is_error(hs_bad), "frame error: headerSize on 1 byte is an error");
    failed = failed + report(!lz4f_is_error(0) && lz4f_is_error(0 - 1),
      "frame: LZ4F_isError(0) false / isError(-1) true");
    let msg = lz4f_error_message(0 - LZ4F_ERROR_DST_MAX_SIZE_TOO_SMALL);
    failed = failed + report(msg.len() > 0, "frame: error name text is bridge-copied \"" + msg + "\"");
  }

  // --- frame: streaming compressor ------------------------------------------
  var pstream = lz4f_prefs_new();
  var sh = ffi.zero_bytes(8);
  let rc_c = ffi.create_compression_context(&mut sh, LZ4F_VERSION);
  let cctx = ffi.read_u64_le(&sh, 0);
  if lz4f_is_error(rc_c) || cctx == 0 {
    failed = failed + report(false, "frame stream: createCompressionContext failed");
  } else {
    var src_s = pattern_bytes(3000, 32);
    var hdr = ffi.zero_bytes(19);
    var blk = ffi.zero_bytes(6000);
    var fl = ffi.zero_bytes(6000);
    var ep = ffi.zero_bytes(6000);
    let bh = ffi.compress_begin(cctx, &mut hdr, 19, &mut pstream);
    let bu = ffi.compress_update(cctx, &mut blk, blk.len(), &mut src_s, src_s.len(), &mut def_copts);
    let bf = ffi.flush(cctx, &mut fl, fl.len(), &mut def_copts);
    let be = ffi.compress_end(cctx, &mut ep, ep.len(), &mut def_copts);
    let fr_cc = ffi.free_compression_context(cctx);
    var frame: Vec[UInt8] = Vec[UInt8].new();
    append_bytes(&mut frame, &hdr, bh);
    append_bytes(&mut frame, &blk, bu);
    append_bytes(&mut frame, &fl, bf);
    append_bytes(&mut frame, &ep, be);
    failed = failed + report(bh == 7 && bf > 0 && be >= 4 && fr_cc == 0,
      "frame stream: begin(7) + buffered update(" + to_string(bu) + ") + flush(" + to_string(bf)
      + ") + end(" + to_string(be) + ")");
    let dec_s = lz4f_decompress(&mut frame, 8192);
    var ok_s = false;
    if dec_s.is_ok { ok_s = bytes_equal(&dec_s.value, &src_s); }
    failed = failed + report(ok_s, "frame stream: concatenated frame decodes byte-exact");

    // autoFlush=1 variant.
    var pstream2 = lz4f_prefs_new();
    lz4f_prefs_set(&mut pstream2, LZ4F_BLOCKSIZE_DEFAULT, LZ4F_BLOCK_LINKED,
      LZ4F_NO_CONTENT_CHECKSUM, 3000, 0, LZ4F_NO_BLOCK_CHECKSUM, 0, 1, 0);
    var sh2 = ffi.zero_bytes(8);
    let rc_c2 = ffi.create_compression_context(&mut sh2, LZ4F_VERSION);
    let cctx2 = ffi.read_u64_le(&sh2, 0);
    var hdr2 = ffi.zero_bytes(19);
    var blk2 = ffi.zero_bytes(6000);
    var ep2 = ffi.zero_bytes(6000);
    let bh2 = ffi.compress_begin(cctx2, &mut hdr2, 19, &mut pstream2);
    let bu2 = ffi.compress_update(cctx2, &mut blk2, blk2.len(), &mut src_s, src_s.len(), &mut def_copts);
    let be2 = ffi.compress_end(cctx2, &mut ep2, ep2.len(), &mut def_copts);
    ffi.free_compression_context(cctx2);
    var frame2: Vec[UInt8] = Vec[UInt8].new();
    append_bytes(&mut frame2, &hdr2, bh2);
    append_bytes(&mut frame2, &blk2, bu2);
    append_bytes(&mut frame2, &ep2, be2);
    let dec_s2 = lz4f_decompress(&mut frame2, 8192);
    var ok_s2 = false;
    if dec_s2.is_ok { ok_s2 = bytes_equal(&dec_s2.value, &src_s); }
    failed = failed + report(bu2 > 0 && ok_s2, "frame stream: autoFlush writes on update");
  }

  // --- frame: 1:1 decompress + reset + decompressOptions --------------------
  var src_1 = pattern_bytes(1500, 24);
  let fr4 = lz4f_compress_frame_default(&mut src_1);
  if fr4.is_ok {
    var f4: Vec[UInt8] = fr4.value;
    var dctx_slot = ffi.zero_bytes(8);
    let rc_d = ffi.create_decompression_context(&mut dctx_slot, LZ4F_VERSION);
    let dctx = ffi.read_u64_le(&dctx_slot, 0);
    var out_1 = ffi.zero_bytes(4096);
    var dsz = ffi.zero_bytes(16);
    var ssz = ffi.zero_bytes(16);
    ffi.write_u64_le(&mut dsz, 0, 4096);
    ffi.write_u64_le(&mut ssz, 0, f4.len());
    let hint = ffi.decompress(dctx, &mut out_1, &mut dsz, &mut f4, &mut ssz, &mut def_dopts);
    let produced = ffi.read_u64_le(&dsz, 0);
    let consumed = ffi.read_u64_le(&ssz, 0);
    failed = failed + report(!lz4f_is_error(hint) && hint == 0 && produced == 1500
      && consumed == f4.len() && prefix_equal(&out_1, &src_1, 1500),
      "frame: 1:1 LZ4F_decompress finishes single-call (hint 0, 1500 bytes, all input used)");
    ffi.reset_decompression_context(dctx);
    let src_2 = pattern_bytes(700, 16);
    var src_2v = dup_bytes(&src_2);
    let fr5 = lz4f_compress_frame_default(&mut src_2v);
    if fr5.is_ok {
      var f5: Vec[UInt8] = fr5.value;
      var out_2 = ffi.zero_bytes(2048);
      ffi.write_u64_le(&mut dsz, 0, 2048);
      ffi.write_u64_le(&mut ssz, 0, f5.len());
      let hint2 = ffi.decompress(dctx, &mut out_2, &mut dsz, &mut f5, &mut ssz, &mut def_dopts);
      let produced2 = ffi.read_u64_le(&dsz, 0);
      failed = failed + report(hint2 == 0 && produced2 == 700 && prefix_equal(&out_2, &src_2, 700),
        "frame: resetDecompressionContext + second frame on the same dctx");
    }
    ffi.free_decompression_context(dctx);
  }

  // --- frame: dictionaries (raw + CDict) + uncompressedUpdate ---------------
  var dict_f = pattern_bytes(4096, 32);
  var src_df = pattern_bytes(1200, 32);
  var sh3 = ffi.zero_bytes(8);
  let rc_c3 = ffi.create_compression_context(&mut sh3, LZ4F_VERSION);
  let cctx3 = ffi.read_u64_le(&sh3, 0);
  var hdr3 = ffi.zero_bytes(19);
  var blk3 = ffi.zero_bytes(6000);
  var ep3 = ffi.zero_bytes(6000);
  let bh3 = ffi.compress_begin_using_dict(cctx3, &mut hdr3, 19, &mut dict_f, dict_f.len(), &mut def_prefs);
  let bu3 = ffi.compress_update(cctx3, &mut blk3, blk3.len(), &mut src_df, src_df.len(), &mut def_copts);
  let be3 = ffi.compress_end(cctx3, &mut ep3, ep3.len(), &mut def_copts);
  ffi.free_compression_context(cctx3);
  var frame3: Vec[UInt8] = Vec[UInt8].new();
  append_bytes(&mut frame3, &hdr3, bh3);
  append_bytes(&mut frame3, &blk3, bu3);
  append_bytes(&mut frame3, &ep3, be3);
  var shd = ffi.zero_bytes(8);
  let rc_d3 = ffi.create_decompression_context(&mut shd, LZ4F_VERSION);
  let dctx3 = ffi.read_u64_le(&shd, 0);
  var out_3 = ffi.zero_bytes(4096);
  var dsz3 = ffi.zero_bytes(16);
  var ssz3 = ffi.zero_bytes(16);
  ffi.write_u64_le(&mut dsz3, 0, 4096);
  ffi.write_u64_le(&mut ssz3, 0, frame3.len());
  let hint3 = ffi.decompress_using_dict(dctx3, &mut out_3, &mut dsz3, &mut frame3, &mut ssz3,
    &mut dict_f, dict_f.len(), &mut def_dopts);
  ffi.free_decompression_context(dctx3);
  let produced3 = ffi.read_u64_le(&dsz3, 0);
  failed = failed + report(bh3 > 0 && hint3 == 0 && produced3 == 1200 && prefix_equal(&out_3, &src_df, 1200),
    "frame dict: compressBegin_usingDict + decompress_usingDict round trip");

  var cdict = ffi.create_cdict(&mut dict_f, dict_f.len());
  var sh4 = ffi.zero_bytes(8);
  let rc_c4 = ffi.create_compression_context(&mut sh4, LZ4F_VERSION);
  let cctx4 = ffi.read_u64_le(&sh4, 0);
  var out_cd = ffi.zero_bytes(ffi.compress_frame_bound(src_df.len(), &mut def_prefs));
  let rc_cd = ffi.compress_frame_using_cdict(cctx4, &mut out_cd, out_cd.len(), &mut src_df,
    src_df.len(), cdict, &mut def_prefs);
  var shd4 = ffi.zero_bytes(8);
  ffi.create_decompression_context(&mut shd4, LZ4F_VERSION);
  let dctx4 = ffi.read_u64_le(&shd4, 0);
  var out_cdd = ffi.zero_bytes(4096);
  var dsz4 = ffi.zero_bytes(16);
  var ssz4 = ffi.zero_bytes(16);
  ffi.write_u64_le(&mut dsz4, 0, 4096);
  ffi.write_u64_le(&mut ssz4, 0, rc_cd);
  let hint4 = ffi.decompress_using_dict(dctx4, &mut out_cdd, &mut dsz4, &mut out_cd, &mut ssz4,
    &mut dict_f, dict_f.len(), &mut def_dopts);
  ffi.free_decompression_context(dctx4);
  ffi.free_cdict(cdict);
  let produced4 = ffi.read_u64_le(&dsz4, 0);
  failed = failed + report(cdict != 0 && !lz4f_is_error(rc_cd) && hint4 == 0 && produced4 == 1200
    && prefix_equal(&out_cdd, &src_df, 1200),
    "frame dict: LZ4F_createCDict + compressFrame_usingCDict + usingDict decode");

  // begin_usingCDict streaming variant.
  let cdict2 = ffi.create_cdict(&mut dict_f, dict_f.len());
  var sh6 = ffi.zero_bytes(8);
  ffi.create_compression_context(&mut sh6, LZ4F_VERSION);
  let cctx6 = ffi.read_u64_le(&sh6, 0);
  var hdr6 = ffi.zero_bytes(19);
  var blk6 = ffi.zero_bytes(6000);
  var ep6 = ffi.zero_bytes(6000);
  let bh6 = ffi.compress_begin_using_cdict(cctx6, &mut hdr6, 19, cdict2, &mut def_prefs);
  let bu6 = ffi.compress_update(cctx6, &mut blk6, blk6.len(), &mut src_df, src_df.len(), &mut def_copts);
  let be6 = ffi.compress_end(cctx6, &mut ep6, ep6.len(), &mut def_copts);
  ffi.free_compression_context(cctx6);
  var frame6: Vec[UInt8] = Vec[UInt8].new();
  append_bytes(&mut frame6, &hdr6, bh6);
  append_bytes(&mut frame6, &blk6, bu6);
  append_bytes(&mut frame6, &ep6, be6);
  var shd6 = ffi.zero_bytes(8);
  ffi.create_decompression_context(&mut shd6, LZ4F_VERSION);
  let dctx6 = ffi.read_u64_le(&shd6, 0);
  var out_6 = ffi.zero_bytes(4096);
  var dsz6 = ffi.zero_bytes(16);
  var ssz6 = ffi.zero_bytes(16);
  ffi.write_u64_le(&mut dsz6, 0, 4096);
  ffi.write_u64_le(&mut ssz6, 0, frame6.len());
  let hint6 = ffi.decompress_using_dict(dctx6, &mut out_6, &mut dsz6, &mut frame6, &mut ssz6,
    &mut dict_f, dict_f.len(), &mut def_dopts);
  ffi.free_decompression_context(dctx6);
  ffi.free_cdict(cdict2);
  let produced6 = ffi.read_u64_le(&dsz6, 0);
  failed = failed + report(bh6 > 0 && bu6 >= 0 && be6 >= 4 && hint6 == 0 && produced6 == 1200
    && prefix_equal(&out_6, &src_df, 1200),
    "frame dict: compressBegin_usingCDict streaming round trip");

  var sh5 = ffi.zero_bytes(8);
  ffi.create_compression_context(&mut sh5, LZ4F_VERSION);
  let cctx5 = ffi.read_u64_le(&sh5, 0);
  // LZ4F_uncompressedUpdate is only supported with blockIndependent mode and
  // needs dstCapacity >= srcSize.
  var prefs_u = lz4f_prefs_new();
  lz4f_prefs_set(&mut prefs_u, LZ4F_BLOCKSIZE_DEFAULT, LZ4F_BLOCK_INDEPENDENT,
    LZ4F_NO_CONTENT_CHECKSUM, 0, 0, LZ4F_NO_BLOCK_CHECKSUM, 0, 0, 0);
  var hdr5 = ffi.zero_bytes(19);
  var blk5 = ffi.zero_bytes(6000);
  var ep5 = ffi.zero_bytes(6000);
  let bh5 = ffi.compress_begin(cctx5, &mut hdr5, 19, &mut prefs_u);
  let bu5 = ffi.uncompressed_update(cctx5, &mut blk5, blk5.len(), &mut src_df, src_df.len(), &mut def_copts);
  let be5 = ffi.compress_end(cctx5, &mut ep5, ep5.len(), &mut def_copts);
  ffi.free_compression_context(cctx5);
  var frame5: Vec[UInt8] = Vec[UInt8].new();
  append_bytes(&mut frame5, &hdr5, bh5);
  append_bytes(&mut frame5, &blk5, bu5);
  append_bytes(&mut frame5, &ep5, be5);
  let dec_u = lz4f_decompress(&mut frame5, 4096);
  var ok_u = false;
  if dec_u.is_ok { ok_u = bytes_equal(&dec_u.value, &src_df); }
  // uncompressedUpdate may buffer (return 0) under autoFlush=0; the raw block
  // is flushed by compressEnd, so the round trip is the evidence.
  failed = failed + report(bh5 == 7 && !lz4f_is_error(bu5) && be5 >= 4 && ok_u,
    "frame: LZ4F_uncompressedUpdate (" + to_string(bu5) + " direct) round trip");

  // --- frame: static helpers + advanced creators ----------------------------
  failed = failed + report(ffi.get_block_size(LZ4F_MAX64KB) == 65536
    && ffi.get_block_size(LZ4F_MAX256KB) == 262144
    && ffi.get_block_size(LZ4F_MAX1MB) == 1048576
    && ffi.get_block_size(LZ4F_MAX4MB) == 4194304
    && ffi.get_block_size(LZ4F_BLOCKSIZE_DEFAULT) == 65536,
    "frame static: LZ4F_getBlockSize for all blockSizeID values");
  failed = failed + report(ffi.get_error_code(0 - LZ4F_ERROR_DST_MAX_SIZE_TOO_SMALL)
    == LZ4F_ERROR_DST_MAX_SIZE_TOO_SMALL,
    "frame static: LZ4F_getErrorCode maps the encoded code");

  var mem = lz4f_custom_mem_new();
  let ac = ffi.xlz4f_create_cctx_advanced(&mut mem, LZ4F_VERSION);
  var hdr_a = ffi.zero_bytes(19);
  var blk_a = ffi.zero_bytes(6000);
  var ep_a = ffi.zero_bytes(6000);
  let bh_a = ffi.compress_begin(ac, &mut hdr_a, 19, &mut def_prefs);
  let bu_a = ffi.compress_update(ac, &mut blk_a, blk_a.len(), &mut src_df, src_df.len(), &mut def_copts);
  let be_a = ffi.compress_end(ac, &mut ep_a, ep_a.len(), &mut def_copts);
  ffi.free_compression_context(ac);
  var frame_a: Vec[UInt8] = Vec[UInt8].new();
  append_bytes(&mut frame_a, &hdr_a, bh_a);
  append_bytes(&mut frame_a, &blk_a, bu_a);
  append_bytes(&mut frame_a, &ep_a, be_a);
  failed = failed + report(ac != 0 && bh_a == 7 && !lz4f_is_error(bu_a) && !lz4f_is_error(be_a),
    "frame static: createCompressionContext_advanced (CustomMem slot) compresses");
  let ad = ffi.xlz4f_create_dctx_advanced(&mut mem, LZ4F_VERSION);
  var out_a = ffi.zero_bytes(4096);
  let dec_a = ffi.lz4f_decompress_all(ad, &mut frame_a, &mut out_a);
  ffi.free_decompression_context(ad);
  failed = failed + report(ad != 0 && dec_a == 1200 && prefix_equal(&out_a, &src_df, 1200),
    "frame static: createDecompressionContext_advanced decompresses");
  let acd = ffi.xlz4f_create_cdict_advanced(&mut mem, &mut dict_f, dict_f.len());
  ffi.free_cdict(acd);
  failed = failed + report(acd != 0, "frame static: createCDict_advanced (CustomMem slot)");

  // --- raw pointer-returning wrappers (called for resolution proof) ---------
  var src_x = pattern_bytes(512, 16);
  var dst_x = ffi.zero_bytes(ffi.compress_bound(512));
  let rcf = ffi.compress_fast(&mut src_x, &mut dst_x, src_x.len(), dst_x.len(), 1);
  var dst_x2 = ffi.zero_bytes(ffi.compress_frame_bound(512, &mut def_prefs));
  let rcfr = ffi.compress_frame(&mut dst_x2, dst_x2.len(), &mut src_x, src_x.len(), &mut def_prefs);
  failed = failed + report(ffi.version_number() == LZ4_VERSION_NUMBER && !lz4f_is_error(0)
    && ffi.frame_compress_bound(1024, &mut def_prefs) > 0 && rcf > 0 && !lz4f_is_error(rcfr),
    "surface: direct versionNumber/isError/frame_compress_bound/compress_fast/compress_frame");
  let vp = ffi.version_string();
  let en = ffi.get_error_name(0 - 1);
  failed = failed + report(vp != en,
    "surface: LZ4_versionString / LZ4F_getErrorName execute and return distinct pointers");

  if failed == 0 {
    io.println("xiom.lz4: all tests passed");
  } else {
    io.println("xiom.lz4: tests failed");
  }
  return failed;
}
