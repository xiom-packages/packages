// xiom.zstd conformance suite -- vendored amalgamation path.
//
// Proves the real binding against the vendored single-file zstd (v1.5.7)
// compiled into the test binary:
//   scripts/port.ps1 -Package xiom.zstd
// (port.args.json passes `--c-source vendor/zstd.c`).
//
// Coverage: version pin, compressBound sanity, compressible round-trip with
// a real ratio, frame content size, auto-size decompression, incompressible
// round-trip, invalid-frame rejection; plus the 0.3.0 ZSTC container framing
// surface: multi-frame write/open round-trips, out-of-order and repeated
// random access, seek-by-index byte ranges, the append+finalize builder, the
// empty container, the empty frame, and typed (never-crashing) errors for
// corrupt magic/version/flags, truncated buffers, corrupt index entries,
// corrupt frame payloads and index size fraud.

module zstd_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.zstd;

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

fn buffers_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  var same = true;
  while i < a.len() {
    if (a[i] as Int) != (b[i] as Int) { same = false; }
    i = i + 1;
  }
  return same;
}

// --------------------------------------------------
//  Container test helpers (independent of zstd.xi)
// --------------------------------------------------

// Fresh copy of a byte buffer.
fn copyv(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// n compressible bytes: (base, base+1, ..., base+15) repeating.
fn pattern(n: Int, base: Int) -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((base + i % 16) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn slicev(v: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = start;
  while i < end && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Copy of `v` with byte `pos` replaced (no-op when `pos` is out of range).
fn setbyte(v: &Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(b as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// Little-endian u32 field read (the caller guarantees the bounds).
fn u32le(v: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (v[pos] as Int) & 255;
  let b1: Int = (v[pos + 1] as Int) & 255;
  let b2: Int = (v[pos + 2] as Int) & 255;
  let b3: Int = (v[pos + 3] as Int) & 255;
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

fn push_u32le(v: &mut Vec[UInt8], val: Int) {
  v.push((val % 256) as UInt8);
  v.push((val / 256 % 256) as UInt8);
  v.push((val / 65536 % 256) as UInt8);
  v.push((val / 16777216 % 256) as UInt8);
}

fn push_all(v: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    v.push(src[i]);
    i = i + 1;
  }
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_cont_is(r: Result[ZstdContainer, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

// Empty ZstdContainer value (fallback holder; never read when open failed).
fn empty_cc() -> ZstdContainer {
  return ZstdContainer{
    frame_offsets: Vec[Int].new();
    frame_sizes: Vec[Int].new();
    frame_out_sizes: Vec[Int].new();
    index_offset: 0;
    total_size: 0;
  };
}

// Hand-built ZSTC container (bytes assembled in the test, not by zstd.xi):
// header + frames + index, with the caller's decompressed sizes.
fn mk_container(frames: &Vec[Vec[UInt8]], outs: &Vec[Int]) -> Vec[UInt8] {
  let n: Int = frames.len();
  var body: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let f: Vec[UInt8] = frames[i];
    push_all(&mut body, &f);
    i = i + 1;
  }
  let index_offset: Int = 16 + body.len();
  var out: Vec[UInt8] = Vec[UInt8].new();
  out.push(90 as UInt8);
  out.push(83 as UInt8);
  out.push(84 as UInt8);
  out.push(67 as UInt8);
  out.push(1 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  push_u32le(&mut out, n);
  push_u32le(&mut out, index_offset);
  push_all(&mut out, &body);
  var off: Int = 16;
  i = 0;
  while i < n {
    let f2: Vec[UInt8] = frames[i];
    let os: Int = outs[i];
    push_u32le(&mut out, off);
    push_u32le(&mut out, f2.len());
    push_u32le(&mut out, os);
    off = off + f2.len();
    i = i + 1;
  }
  return out;
}


fn main() -> Int {
  io.println("=== xiom.zstd conformance tests (vendored amalgamation) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // Version pin.
  let v = zstd_version_number();
  failed = failed + report(v >= 10500, "version: zstd " + zstd_version() + " (" + to_string(v) + ")");
  failed = failed + report(zstd_compress_bound(1000) >= 1000, "compressBound(1000) >= 1000");

  // Compressible round-trip with a real ratio.
  var data: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 8192 {
    data.push(((i % 16) + 65) as UInt8);
    i = i + 1;
  }
  let cr = zstd_compress(&mut data, 3);
  if !cr.is_ok {
    failed = failed + report(false, "compress failed -- " + cr.error);
  } else {
    var packed: Vec[UInt8] = cr.value;
    failed = failed + report(packed.len() < data.len(),
      "compress: 8192 -> " + to_string(packed.len()) + " bytes at level 3");
    let fcs = zstd_frame_content_size(&mut packed);
    failed = failed + report(fcs == 8192, "frame content size = " + to_string(fcs));

    let dr = zstd_decompress(&mut packed, 8192);
    if !dr.is_ok {
      failed = failed + report(false, "decompress failed -- " + dr.error);
    } else {
      var restored: Vec[UInt8] = dr.value;
      failed = failed + report(buffers_equal(&data, &restored), "round-trip: restored bytes are identical");
    }

    let ar = zstd_decompress_auto(&mut packed);
    if !ar.is_ok {
      failed = failed + report(false, "auto decompress failed -- " + ar.error);
    } else {
      var restored2: Vec[UInt8] = ar.value;
      failed = failed + report(buffers_equal(&data, &restored2), "auto-size decompress: identical");
    }
  }

  // Incompressible round-trip (LCG bytes).
  var noise: Vec[UInt8] = Vec[UInt8].new();
  var seed: Int = 12345;
  var n: Int = 0;
  while n < 2048 {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    noise.push((seed % 256) as UInt8);
    n = n + 1;
  }
  let nr = zstd_compress(&mut noise, 1);
  if !nr.is_ok {
    failed = failed + report(false, "noise compress failed -- " + nr.error);
  } else {
    var np: Vec[UInt8] = nr.value;
    let nd = zstd_decompress_auto(&mut np);
    if !nd.is_ok {
      failed = failed + report(false, "noise decompress failed -- " + nd.error);
    } else {
      var nr2: Vec[UInt8] = nd.value;
      failed = failed + report(buffers_equal(&noise, &nr2), "incompressible: 2048-byte round-trip identical");
    }
  }

  // Invalid frame rejection.
  var garbage: Vec[UInt8] = Vec[UInt8].new();
  var g: Int = 0;
  while g < 32 {
    garbage.push(170 as UInt8);
    g = g + 1;
  }
  let bad = zstd_decompress_auto(&mut garbage);
  if bad.is_ok {
    failed = failed + report(false, "invalid frame unexpectedly decompressed");
  } else {
    failed = failed + report(true, "invalid frame rejected (" + bad.error + ")");
  }

  // ---- ZSTC container framing (0.3.0) ----

  // Three independently compressed frames (compressible payloads so the
  // stored frames stay small and the ratios are real).
  var cra: Vec[UInt8] = pattern(1500, 65);
  var crb: Vec[UInt8] = pattern(700, 97);
  var crc: Vec[UInt8] = pattern(300, 48);
  let cz0 = zstd_compress(&mut cra, 3);
  let cz1 = zstd_compress(&mut crb, 3);
  let cz2 = zstd_compress(&mut crc, 3);
  var cframes: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  var cf0: Vec[UInt8] = Vec[UInt8].new();
  var cf1: Vec[UInt8] = Vec[UInt8].new();
  var cf2: Vec[UInt8] = Vec[UInt8].new();
  var czok = cz0.is_ok && cz1.is_ok && cz2.is_ok;
  if czok {
    cf0 = cz0.value;
    cf1 = cz1.value;
    cf2 = cz2.value;
    cframes.push(copyv(&cf0));
    cframes.push(copyv(&cf1));
    cframes.push(copyv(&cf2));
  }
  failed = failed + report(czok, "container: three test frames compressed");

  // One-shot write: header + frame region + index, exact layout.
  let cframe_bytes: Int = cf0.len() + cf1.len() + cf2.len();
  let cwr = zstd_container_write(&cframes);
  var ccont: Vec[UInt8] = Vec[UInt8].new();
  var cwrite_ok = cwr.is_ok;
  if cwrite_ok {
    ccont = cwr.value;
    cwrite_ok = ccont.len() == 16 + cframe_bytes + 36;
    if cwrite_ok { cwrite_ok = u32le(&ccont, 8) == 3; }
    if cwrite_ok { cwrite_ok = u32le(&ccont, 12) == 16 + cframe_bytes; }
    if cwrite_ok { cwrite_ok = (ccont[0] as Int) == 90; }
    if cwrite_ok { cwrite_ok = (ccont[1] as Int) == 83; }
    if cwrite_ok { cwrite_ok = (ccont[2] as Int) == 84; }
    if cwrite_ok { cwrite_ok = (ccont[3] as Int) == 67; }
  }
  failed = failed + report(cwrite_ok, "container write: header + frame region + index layout");

  // Open: frame count and index accessors.
  let cop = zstd_container_open(&ccont);
  var copen_ok = cop.is_ok;
  var cc: ZstdContainer = empty_cc();
  if copen_ok {
    cc = cop.value;
    copen_ok = zstd_container_frame_count(&cc) == 3;
    if copen_ok { copen_ok = zstd_container_frame_offset(&cc, 0) == 16; }
    if copen_ok { copen_ok = zstd_container_frame_size(&cc, 0) == cf0.len(); }
    if copen_ok { copen_ok = zstd_container_frame_out_size(&cc, 0) == 1500; }
    if copen_ok { copen_ok = zstd_container_index_offset(&cc) == 16 + cframe_bytes; }
    if copen_ok { copen_ok = zstd_container_total_size(&cc) == ccont.len(); }
  }
  failed = failed + report(copen_ok, "container open: frame_count and index accessors");

  // In-order multi-frame round trip.
  var c4ok = copen_ok;
  if c4ok {
    var k = 0;
    while k < 3 {
      let fr = zstd_container_frame_at(&ccont, &cc, k);
      if !fr.is_ok {
        c4ok = false;
      } else {
        var got: Vec[UInt8] = fr.value;
        if k == 0 && !buffers_equal(&cra, &got) { c4ok = false; }
        if k == 1 && !buffers_equal(&crb, &got) { c4ok = false; }
        if k == 2 && !buffers_equal(&crc, &got) { c4ok = false; }
      }
      k = k + 1;
    }
  }
  failed = failed + report(c4ok, "multi-frame: every frame round-trips in order");

  // Out-of-order and repeated random access.
  var c5ok = copen_ok;
  if c5ok {
    let q2 = zstd_container_frame_at(&ccont, &cc, 2);
    if !q2.is_ok {
      c5ok = false;
    } else {
      var g2: Vec[UInt8] = q2.value;
      if !buffers_equal(&crc, &g2) { c5ok = false; }
    }
    let q0 = zstd_container_frame_at(&ccont, &cc, 0);
    if !q0.is_ok {
      c5ok = false;
    } else {
      var g0: Vec[UInt8] = q0.value;
      if !buffers_equal(&cra, &g0) { c5ok = false; }
    }
    let q1a = zstd_container_frame_at(&ccont, &cc, 1);
    let q1b = zstd_container_frame_at(&ccont, &cc, 1);
    if !q1a.is_ok || !q1b.is_ok {
      c5ok = false;
    } else {
      var g1a: Vec[UInt8] = q1a.value;
      var g1b: Vec[UInt8] = q1b.value;
      if !buffers_equal(&crb, &g1a) { c5ok = false; }
      if !buffers_equal(&g1a, &g1b) { c5ok = false; }
    }
  }
  failed = failed + report(c5ok, "random access: out-of-order and repeated frame_at");

  // Seek-by-index: offsets and stored byte ranges.
  var c6ok = copen_ok;
  if c6ok {
    let s0 = zstd_container_seek(&cc, 0);
    let s1 = zstd_container_seek(&cc, 1);
    let s2 = zstd_container_seek(&cc, 2);
    if !s0.is_ok || !s1.is_ok || !s2.is_ok {
      c6ok = false;
    } else {
      let o0: Int = s0.value;
      let o1: Int = s1.value;
      let o2: Int = s2.value;
      if o0 != 16 { c6ok = false; }
      if o1 != 16 + cf0.len() { c6ok = false; }
      if o2 != 16 + cf0.len() + cf1.len() { c6ok = false; }
      var sl0 = slicev(&ccont, o0, o0 + cf0.len());
      var sl1 = slicev(&ccont, o1, o1 + cf1.len());
      var sl2 = slicev(&ccont, o2, o2 + cf2.len());
      if !buffers_equal(&cf0, &sl0) { c6ok = false; }
      if !buffers_equal(&cf1, &sl1) { c6ok = false; }
      if !buffers_equal(&cf2, &sl2) { c6ok = false; }
    }
  }
  failed = failed + report(c6ok, "seek-by-index: resolves stored frame byte ranges");

  // Out-of-range accessors and typed errors.
  var c7ok = copen_ok;
  if c7ok {
    let b1 = zstd_container_frame_at(&ccont, &cc, 3);
    let b2 = zstd_container_frame_at(&ccont, &cc, -1);
    let b3 = zstd_container_seek(&cc, 3);
    let b4 = zstd_container_seek(&cc, -1);
    if b1.is_ok || b2.is_ok || b3.is_ok || b4.is_ok { c7ok = false; }
    if !err_bytes_is(b1, "zstd.container: frame out of range") { c7ok = false; }
    if !err_bytes_is(b2, "zstd.container: frame out of range") { c7ok = false; }
    if !err_int_is(b3, "zstd.container: frame out of range") { c7ok = false; }
    if !err_int_is(b4, "zstd.container: frame out of range") { c7ok = false; }
    if zstd_container_frame_offset(&cc, 3) != -1 { c7ok = false; }
    if zstd_container_frame_offset(&cc, -1) != -1 { c7ok = false; }
    if zstd_container_frame_size(&cc, 9) != -1 { c7ok = false; }
    if zstd_container_frame_out_size(&cc, 3) != -1 { c7ok = false; }
  }
  failed = failed + report(c7ok, "accessors: out-of-range is typed, never a crash");

  // Empty container: 16 bytes, zero frames, typed access errors.
  var cempty: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  let cwr0 = zstd_container_write(&cempty);
  var c8ok = cwr0.is_ok;
  var cont0: Vec[UInt8] = Vec[UInt8].new();
  if c8ok {
    cont0 = cwr0.value;
    c8ok = cont0.len() == 16;
  }
  let cop0 = zstd_container_open(&cont0);
  if c8ok {
    if !cop0.is_ok {
      c8ok = false;
    } else {
      let e0: ZstdContainer = cop0.value;
      if zstd_container_frame_count(&e0) != 0 { c8ok = false; }
      if zstd_container_total_size(&e0) != 16 { c8ok = false; }
      if zstd_container_index_offset(&e0) != 16 { c8ok = false; }
      let ef = zstd_container_frame_at(&cont0, &e0, 0);
      let es = zstd_container_seek(&e0, 0);
      if ef.is_ok || es.is_ok { c8ok = false; }
      if !err_bytes_is(ef, "zstd.container: frame out of range") { c8ok = false; }
      if !err_int_is(es, "zstd.container: frame out of range") { c8ok = false; }
    }
  }
  failed = failed + report(c8ok, "empty container: zero frames, typed access errors");

  // Streaming-ish builder: append + finalize == one-shot write.
  var cb = zstd_container_builder_new();
  var c9ok = zstd_container_builder_count(&cb) == 0;
  let ba0 = zstd_container_builder_append(&mut cb, &cf0);
  let ba1 = zstd_container_builder_append(&mut cb, &cf1);
  let ba2 = zstd_container_builder_append(&mut cb, &cf2);
  if !ba0.is_ok || !ba1.is_ok || !ba2.is_ok { c9ok = false; }
  if zstd_container_builder_count(&cb) != 3 { c9ok = false; }
  let cbf = zstd_container_builder_finalize(&mut cb);
  if !cbf.is_ok {
    c9ok = false;
  } else {
    var bbytes: Vec[UInt8] = cbf.value;
    if !buffers_equal(&bbytes, &ccont) { c9ok = false; }
  }
  failed = failed + report(c9ok, "builder: append + finalize equals one-shot write");

  // Builder validation: bad frames rejected, state intact.
  var cb2 = zstd_container_builder_new();
  var junk: Vec[UInt8] = pattern(64, 170);
  let bj = zstd_container_builder_append(&mut cb2, &junk);
  var c10ok = err_unit_is(bj, "zstd.container: not a zstd frame");
  var cempty_frame: Vec[UInt8] = Vec[UInt8].new();
  let be = zstd_container_builder_append(&mut cb2, &cempty_frame);
  if !err_unit_is(be, "zstd.container: empty frame") { c10ok = false; }
  if zstd_container_builder_count(&cb2) != 0 { c10ok = false; }
  let bg = zstd_container_builder_append(&mut cb2, &cf0);
  if !bg.is_ok { c10ok = false; }
  if zstd_container_builder_count(&cb2) != 1 { c10ok = false; }
  failed = failed + report(c10ok, "builder: invalid frames rejected, state intact");

  // Corrupt magic / version / flags.
  var cm = setbyte(&ccont, 0, 0);
  var cv = setbyte(&ccont, 4, 2);
  var cflags = setbyte(&ccont, 6, 1);
  var cjunk: Vec[UInt8] = pattern(64, 170);
  var c11ok = err_cont_is(zstd_container_open(&cm), "zstd.container: bad magic");
  if !err_cont_is(zstd_container_open(&cjunk), "zstd.container: bad magic") { c11ok = false; }
  if !err_cont_is(zstd_container_open(&cv), "zstd.container: unsupported version") { c11ok = false; }
  if !err_cont_is(zstd_container_open(&cflags), "zstd.container: unsupported flags") { c11ok = false; }
  failed = failed + report(c11ok, "corrupt container: magic, version and flags are typed errors");

  // Truncated container: header and index truncations.
  var czero: Vec[UInt8] = Vec[UInt8].new();
  var cten: Vec[UInt8] = slicev(&ccont, 0, 10);
  var chalf: Vec[UInt8] = slicev(&ccont, 0, ccont.len() / 2);
  var cminus: Vec[UInt8] = slicev(&ccont, 0, ccont.len() - 1);
  var c12ok = err_cont_is(zstd_container_open(&czero), "zstd.container: truncated header");
  if !err_cont_is(zstd_container_open(&cten), "zstd.container: truncated header") { c12ok = false; }
  if !err_cont_is(zstd_container_open(&chalf), "zstd.container: truncated index") { c12ok = false; }
  if !err_cont_is(zstd_container_open(&cminus), "zstd.container: truncated index") { c12ok = false; }
  failed = failed + report(c12ok, "truncated container: typed errors, no crash");

  // Corrupt index entries: size field and frame count.
  let cioff: Int = 16 + cframe_bytes;
  var csz = setbyte(&ccont, cioff + 4, 255);
  var ccount = setbyte(&ccont, 8, 255);
  var c13ok = err_cont_is(zstd_container_open(&csz), "zstd.container: bad frame index");
  if !err_cont_is(zstd_container_open(&ccount), "zstd.container: truncated index") { c13ok = false; }
  failed = failed + report(c13ok, "corrupt index: typed error");

  // Corrupt frame payload: frame_at fails typed; sibling frames unaffected.
  var cpay = setbyte(&ccont, 16, 0);
  let cppo = zstd_container_open(&cpay);
  var c14ok = cppo.is_ok;
  if c14ok {
    let cpc: ZstdContainer = cppo.value;
    let p0 = zstd_container_frame_at(&cpay, &cpc, 0);
    let p1 = zstd_container_frame_at(&cpay, &cpc, 1);
    let p2 = zstd_container_frame_at(&cpay, &cpc, 2);
    if p0.is_ok { c14ok = false; }
    if !err_bytes_is(p0, "zstd.container: decompress failed (Unknown frame descriptor)") { c14ok = false; }
    if !p1.is_ok { c14ok = false; }
    if !p2.is_ok { c14ok = false; }
    if p1.is_ok {
      var q1: Vec[UInt8] = p1.value;
      if !buffers_equal(&crb, &q1) { c14ok = false; }
    }
  }
  failed = failed + report(c14ok, "corrupt frame payload: typed error, siblings still readable");

  // Index size fraud: a valid frame whose real size differs from the index.
  var crd: Vec[UInt8] = pattern(333, 77);
  let czd = zstd_compress(&mut crd, 3);
  var c15ok = false;
  if czd.is_ok && copen_ok {
    var cd: Vec[UInt8] = czd.value;
    var fraud_frames: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
    var fraud_outs: Vec[Int] = Vec[Int].new();
    fraud_frames.push(copyv(&cd));
    fraud_frames.push(copyv(&cf1));
    fraud_frames.push(copyv(&cf2));
    fraud_outs.push(1500);
    fraud_outs.push(700);
    fraud_outs.push(300);
    var cfraud = mk_container(&fraud_frames, &fraud_outs);
    let fpo = zstd_container_open(&cfraud);
    c15ok = fpo.is_ok;
    if c15ok {
      let fc: ZstdContainer = fpo.value;
      let f0r = zstd_container_frame_at(&cfraud, &fc, 0);
      let f1r = zstd_container_frame_at(&cfraud, &fc, 1);
      if f0r.is_ok { c15ok = false; }
      if !err_bytes_is(f0r, "zstd.container: frame size mismatch") { c15ok = false; }
      if !f1r.is_ok { c15ok = false; }
    }
  }
  failed = failed + report(c15ok, "index size fraud: frame_at detects decompressed size mismatch");

  // Empty frame: zero-length content compresses and round-trips via the index.
  var cebuf: Vec[UInt8] = Vec[UInt8].new();
  let cez = zstd_compress(&mut cebuf, 3);
  var c16ok = cez.is_ok;
  if c16ok {
    var ef0: Vec[UInt8] = cez.value;
    var eframes: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
    eframes.push(copyv(&ef0));
    let ewr = zstd_container_write(&eframes);
    if !ewr.is_ok {
      c16ok = false;
    } else {
      var econt: Vec[UInt8] = ewr.value;
      let eop = zstd_container_open(&econt);
      if !eop.is_ok {
        c16ok = false;
      } else {
        let ec: ZstdContainer = eop.value;
        let ef = zstd_container_frame_at(&econt, &ec, 0);
        if !ef.is_ok {
          c16ok = false;
        } else {
          var efb: Vec[UInt8] = ef.value;
          if efb.len() != 0 { c16ok = false; }
        }
      }
    }
  }
  failed = failed + report(c16ok, "empty frame: zero-length content round-trips");

  if failed == 0 {
    io.println("xiom.zstd: all tests passed");
  } else {
    io.println("xiom.zstd: tests failed");
  }
  return failed;
}
