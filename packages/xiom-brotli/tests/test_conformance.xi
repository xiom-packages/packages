// xiom.brotli conformance suite -- vendored-C path (google/brotli v1.2.0).
//
// Proves the real RFC 7932 binding against the vendored upstream sources
// compiled into the test binary:
//   scripts/port.ps1 -Package xiom.brotli -TimeoutSec 2400
// (port.args.json passes every vendored unit + src/brotli_bridge.c).
//
// Coverage: version pin (decoder == encoder == 1.2.0), compress bound,
// round trips across quality 0..11 (text), binary noise, tiny/empty/large
// inputs, upstream golden vectors decoded byte-identically (tests/fixtures,
// imported from the pinned clone's tests/testdata), chunked streaming decode
// (prefix feeding + tiny output chunks) and streaming encode (byte-equal to
// one-shot; TakeOutput drain path), the raw progress contract, typed errors
// for corrupt/truncated/oversized streams (never crashes), parameter and
// handle misuse, the upstream error-string mapping, and the RFC 9110
// content-coding ("br") HTTP helpers.

module brotli_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.brotli;

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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn copyv(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
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

fn xorbyte(v: &Vec[UInt8], pos: Int, mask: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(((v[i] as Int) ^ mask) as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// n bytes of a 16-symbol cycle starting at `base` (compressible).
fn pattern(n: Int, base: Int) -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((base + i % 16) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// n bytes of printable pseudo-text (compressible, word-like; the built-in
// static dictionary participates on short repeats too).
fn text_bytes(n: Int) -> Vec[UInt8] {
  let words = "the quick brown fox jumps over the lazy dog while brotli encodes the web content and stores it in a compact stream ";
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let c = string.byte_at(words, i % string.byte_count(words));
    v.push(c);
    i = i + 1;
  }
  return v;
}

// n pseudo-random bytes (LCG; incompressible).
fn noise(n: Int, seed0: Int) -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var seed: Int = seed0;
  var i = 0;
  while i < n {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    v.push((seed % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

// Load a fixture (relative to the package dir under port.ps1; the second
// form survives runners that start at the repository root).
fn load_fixture(name: Str) -> Result[Vec[UInt8], Str] {
  let r1 = io.read_file_bytes("tests/fixtures/" + name);
  if r1.is_ok { return Ok(r1.value); }
  let r2 = io.read_file_bytes("packages/xiom-brotli/tests/fixtures/" + name);
  if r2.is_ok { return Ok(r2.value); }
  return Err("fixture not found: " + name);
}

// --------------------------------------------------
//  streaming helpers (public streaming surface only)
// --------------------------------------------------

// Decode with the chunked INPUT discipline: a growing prefix buffer is
// handed to the session each step (unconsumed bytes are re-fed at the carry
// offset), while the output side uses tiny chunks to force
// NEEDS_MORE_OUTPUT traffic.
fn stream_decode_prefix(src: &Vec[UInt8], step: Int, out_chunk: Int) -> Result[Vec[UInt8], Str] {
  let d = brotli_decoder_new();
  if d == 0 { return Err("brotli.decoder: create failed"); }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var feed: Int = 0;
  var carry: Int = 0;
  var failed: Int = 0;
  var failure: Str = "";
  var done: Int = 0;
  var iters: Int = 0;
  while done == 0 {
    iters = iters + 1;
    if iters > 400000 {
      failed = 1;
      failure = "stream decode did not converge";
      done = 1;
    } else {
      if feed < src.len() {
        feed = feed + step;
        if feed > src.len() { feed = src.len(); }
      }
      var buf: Vec[UInt8] = slicev(src, 0, feed);
      let p = brotli_decoder_push(d, &mut buf, carry, &mut out, out_chunk);
      if !p.is_ok {
        failed = 1;
        failure = p.error;
        done = 1;
      } else {
        var prog: BrotliDecodeProgress = p.value;
        carry = carry + prog.consumed;
        if prog.result == BROTLI_DECODER_RESULT_SUCCESS {
          done = 1;
        } elif prog.result == BROTLI_DECODER_RESULT_ERROR {
          failed = 1;
          failure = "brotli.decoder: corrupt stream (" + brotli_decoder_error_string(brotli_decoder_error_code(d)) + ")";
          done = 1;
        } elif prog.result == BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT {
          if feed >= src.len() && prog.consumed == 0 {
            failed = 1;
            failure = "brotli.decoder: truncated stream";
            done = 1;
          }
        }
      }
    }
  }
  brotli_decoder_destroy(d);
  if failed == 1 { return Err(failure); }
  return Ok(out);
}

// Encode with the streaming API: growing-prefix PROCESS feeding with a tiny
// writer chunk (output diverts to the internal buffer), steady TakeOutput
// draining, then a FINISH loop driven by `brotli_encoder_is_finished`.
fn stream_encode_take_output(input: &Vec[UInt8], quality: Int, lgwin: Int, mode: Int, in_step: Int, out_chunk: Int, take_chunk: Int) -> Result[Vec[UInt8], Str] {
  let nr = brotli_encoder_new(quality, lgwin, mode);
  if !nr.is_ok { return Err(nr.error); }
  var e: Int = nr.value;
  var sink: Vec[UInt8] = copyv(input);
  var out: Vec[UInt8] = Vec[UInt8].new();
  // set the size hint through the raw parameter API (before encoding)
  if !brotli_encoder_set_parameter(e, BROTLI_PARAM_SIZE_HINT, sink.len()) {
    brotli_encoder_destroy(e);
    return Err("brotli.encoder: size hint rejected");
  }
  if brotli_encoder_is_finished(e) {
    brotli_encoder_destroy(e);
    return Err("brotli.encoder: fresh session already finished");
  }
  var offset: Int = 0;
  var feed: Int = 0;
  var failed: Int = 0;
  var failure: Str = "";
  var iters: Int = 0;
  var draining = 1;
  // feed phase: PROCESS in growing prefixes
  while offset < sink.len() && failed == 0 {
    iters = iters + 1;
    if iters > 400000 {
      failed = 1;
      failure = "stream encode did not converge";
    } else {
      if feed < offset { feed = offset; }
      feed = feed + in_step;
      if feed > sink.len() { feed = sink.len(); }
      var buf: Vec[UInt8] = slicev(&sink, 0, feed);
      let p = brotli_encoder_push(e, &mut buf, offset, BROTLI_OPERATION_PROCESS, &mut out, out_chunk);
      if !p.is_ok {
        failed = 1;
        failure = p.error;
      } else {
        var prog: BrotliEncodeProgress = p.value;
        if prog.consumed == 0 && prog.written == 0 {
          failed = 1;
          failure = "stream encode made no progress";
        } else {
          offset = offset + prog.consumed;
        }
        draining = 1;
        while draining == 1 {
          let t = brotli_encoder_take_output(e, &mut out, take_chunk);
          if !t.is_ok {
            failed = 1;
            failure = t.error;
            draining = 0;
          } else {
            var n: Int = t.value;
            if n == 0 { draining = 0; }
          }
        }
      }
    }
  }
  // finish phase: zero-input FINISH until the public predicate is true
  var finished = 0;
  iters = 0;
  while finished == 0 && failed == 0 {
    iters = iters + 1;
    if iters > 400000 {
      failed = 1;
      failure = "stream finish did not converge";
    } else {
      let p2 = brotli_encoder_push(e, &mut sink, sink.len(), BROTLI_OPERATION_FINISH, &mut out, out_chunk);
      if !p2.is_ok {
        failed = 1;
        failure = p2.error;
      } else {
        draining = 1;
        while draining == 1 {
          let t2 = brotli_encoder_take_output(e, &mut out, take_chunk);
          if !t2.is_ok {
            failed = 1;
            failure = t2.error;
            draining = 0;
          } else {
            var n2: Int = t2.value;
            if n2 == 0 { draining = 0; }
          }
        }
        if brotli_encoder_is_finished(e) { finished = 1; }
      }
    }
  }
  let final_finished = brotli_encoder_is_finished(e);
  brotli_encoder_destroy(e);
  if failed == 1 { return Err(failure); }
  if !final_finished { return Err("brotli.encoder: session never reported finished"); }
  return Ok(out);
}

fn main() -> Int {
  io.println("=== xiom.brotli conformance tests (vendored brotli v1.2.0) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // ---- version pin ----
  let dv = brotli_decoder_version();
  let ev = brotli_encoder_version();
  failed = failed + report(dv == 16785408 && ev == 16785408,
    "version: decoder == encoder == 1.2.0 (0x01002000)");
  failed = failed + report(str_eq(brotli_version(), "1.2.0"),
    "version: brotli_version() == 1.2.0");

  // ---- compress bound ----
  failed = failed + report(brotli_compress_bound(1000) == 1006 && brotli_compress_bound(0) == 2,
    "bound: MaxCompressedSize(1000) == 1006, (0) == 2");
  failed = failed + report(brotli_compress_bound(-5) == 0,
    "bound: negative sizing loop input is a typed 0");

  // ---- quality sweep 0..11 on text ----
  var text: Vec[UInt8] = text_bytes(16384);
  var qok = true;
  var q = 0;
  while q <= 11 {
    var work: Vec[UInt8] = copyv(&text);
    let cr = brotli_compress(&mut work, q, 22, 0);
    if !cr.is_ok {
      qok = false;
    } else {
      var packed: Vec[UInt8] = cr.value;
      let dr = brotli_decompress_auto(&mut packed);
      if !dr.is_ok {
        qok = false;
      } else {
        var restored: Vec[UInt8] = dr.value;
        if !buffers_equal(&text, &restored) { qok = false; }
      }
    }
    q = q + 1;
  }
  failed = failed + report(qok, "round trips: 16 KiB text at quality 0..11");

  var work11: Vec[UInt8] = copyv(&text);
  let cr11 = brotli_compress(&mut work11, 11, 22, 0);
  var ratio_ok = false;
  var packed11_len: Int = 0;
  if cr11.is_ok {
    var packed11: Vec[UInt8] = cr11.value;
    packed11_len = packed11.len();
    ratio_ok = packed11.len() < 16384 / 4;
  }
  failed = failed + report(ratio_ok,
    "ratio: quality 11 packs 16384 bytes to " + to_string(packed11_len));

  // ---- binary noise round trip ----
  var bin: Vec[UInt8] = noise(4096, 12345);
  var binwork: Vec[UInt8] = copyv(&bin);
  let bcr = brotli_compress(&mut binwork, 5, 22, 0);
  var bok = false;
  if bcr.is_ok {
    var bpacked: Vec[UInt8] = bcr.value;
    let bdr = brotli_decompress_auto(&mut bpacked);
    if bdr.is_ok {
      var brestored: Vec[UInt8] = bdr.value;
      bok = buffers_equal(&bin, &brestored);
    }
  }
  failed = failed + report(bok, "binary: 4096-byte LCG noise round-trips at quality 5");

  // ---- tiny input ----
  var tiny: Vec[UInt8] = Vec[UInt8].new();
  tiny.push(65 as UInt8);
  var tinywork: Vec[UInt8] = copyv(&tiny);
  let tcr = brotli_compress(&mut tinywork, 11, 22, 1);
  var tok = false;
  if tcr.is_ok {
    var tpacked: Vec[UInt8] = tcr.value;
    let tdr = brotli_decompress_auto(&mut tpacked);
    if tdr.is_ok {
      var trestored: Vec[UInt8] = tdr.value;
      tok = buffers_equal(&tiny, &trestored);
    }
  }
  failed = failed + report(tok, "tiny: 1-byte input round-trips at quality 11");

  // ---- empty input ----
  var empty: Vec[UInt8] = Vec[UInt8].new();
  let ecr = brotli_compress(&mut empty, 5, 22, 0);
  var eok = ecr.is_ok;
  if eok {
    var epacked: Vec[UInt8] = ecr.value;
    eok = epacked.len() >= 1;
    let edr = brotli_decompress_auto(&mut epacked);
    if !edr.is_ok {
      eok = false;
    } else {
      var erestored: Vec[UInt8] = edr.value;
      if erestored.len() != 0 { eok = false; }
    }
  }
  failed = failed + report(eok, "empty: 0-byte input produces a stream that decodes to 0 bytes");

  // ---- large input ----
  var large: Vec[UInt8] = pattern(131072, 65);
  var largework: Vec[UInt8] = copyv(&large);
  let lcr = brotli_compress(&mut largework, 5, 22, 0);
  var lok = false;
  var lpacked_len: Int = 0;
  if lcr.is_ok {
    var lpacked: Vec[UInt8] = lcr.value;
    lpacked_len = lpacked.len();
    let ldr = brotli_decompress_auto(&mut lpacked);
    if ldr.is_ok {
      var lrestored: Vec[UInt8] = ldr.value;
      lok = buffers_equal(&large, &lrestored) && lpacked_len < 131072 / 8;
    }
  }
  failed = failed + report(lok,
    "large: 128 KiB pattern round-trips at quality 5 (" + to_string(lpacked_len) + " bytes)");

  // ---- upstream golden vectors (pinned clone tests/testdata) ----
  var vec_names: Vec[Str] = Vec[Str].new();
  vec_names.push("10x10y");
  vec_names.push("64x");
  vec_names.push("empty");
  vec_names.push("quickfox");
  vec_names.push("monkey");
  vec_names.push("ukkonooa");
  vec_names.push("cp852-utf8");
  vec_names.push("x");
  var vok = true;
  var vi = 0;
  while vi < vec_names.len() {
    let name: Str = vec_names[vi];
    let fr = load_fixture(name + ".compressed");
    let gr = load_fixture(name);
    if !fr.is_ok || !gr.is_ok {
      vok = false;
    } else {
      var comp: Vec[UInt8] = fr.value;
      var raw: Vec[UInt8] = gr.value;
      let dr2 = brotli_decompress_auto(&mut comp);
      if !dr2.is_ok {
        vok = false;
      } else {
        var got: Vec[UInt8] = dr2.value;
        if !buffers_equal(&raw, &got) { vok = false; }
      }
    }
    vi = vi + 1;
  }
  failed = failed + report(vok, "vectors: 8 upstream streams decode byte-identically");

  // one-shot API + raw progress contract against the classic vector
  let v1c = load_fixture("10x10y.compressed");
  let v1r = load_fixture("10x10y");
  var v1ok = false;
  var vc: Vec[UInt8] = Vec[UInt8].new();
  var vr: Vec[UInt8] = Vec[UInt8].new();
  if v1c.is_ok && v1r.is_ok {
    vc = v1c.value;
    vr = v1r.value;
    var vc2: Vec[UInt8] = copyv(&vc);
    let od = brotli_decompress_oneshot(&mut vc2, vr.len());
    if od.is_ok {
      var og: Vec[UInt8] = od.value;
      v1ok = buffers_equal(&vr, &og);
    }
  }
  failed = failed + report(v1ok, "vectors: one-shot BrotliDecoderDecompress decodes 10x10y");

  var prog_ok = false;
  if vc.len() == 12 && vr.len() == 20 {
    var prog_dec: Vec[UInt8] = copyv(&vc);
    var prog_out: Vec[UInt8] = Vec[UInt8].new();
    let pd = brotli_decoder_new();
    if pd != 0 {
      let pp = brotli_decoder_push(pd, &mut prog_dec, 0, &mut prog_out, 64);
      if pp.is_ok {
        var pg: BrotliDecodeProgress = pp.value;
        prog_ok = pg.result == BROTLI_DECODER_RESULT_SUCCESS && pg.consumed == 12 && pg.written == 20 && prog_out.len() == 20;
      }
      brotli_decoder_destroy(pd);
    }
  }
  failed = failed + report(prog_ok, "stream: one push reports SUCCESS + consumed 12 + written 20");

  // ---- chunked streaming decode ----
  var sdata: Vec[UInt8] = text_bytes(20000);
  var swork: Vec[UInt8] = copyv(&sdata);
  let scr = brotli_compress(&mut swork, 5, 22, 0);
  var spacked: Vec[UInt8] = Vec[UInt8].new();
  if scr.is_ok { spacked = scr.value; }
  var sok = false;
  if scr.is_ok {
    let sd = stream_decode_prefix(&spacked, 333, 7);
    if sd.is_ok {
      var srestored: Vec[UInt8] = sd.value;
      sok = buffers_equal(&sdata, &srestored);
    }
  }
  failed = failed + report(sok, "stream decode: 333-byte input steps + 7-byte output chunks round-trip");

  // ---- streaming encode: byte-equal to one-shot ----
  var edata: Vec[UInt8] = text_bytes(8000);
  var ework: Vec[UInt8] = copyv(&edata);
  let eshot = brotli_compress(&mut ework, 4, 22, 1);
  var eeq = false;
  if eshot.is_ok {
    var one_shot_bytes: Vec[UInt8] = eshot.value;
    let streamed = stream_encode_take_output(&edata, 4, 22, 1, 700, 8, 64);
    if streamed.is_ok {
      var streamed_bytes: Vec[UInt8] = streamed.value;
      eeq = buffers_equal(&one_shot_bytes, &streamed_bytes);
    }
  }
  failed = failed + report(eeq, "stream encode: PROCESS/FINISH + TakeOutput is byte-equal to one-shot");

  // ---- streaming encode output decodes ----
  var edec_ok = false;
  let streamed2 = stream_encode_take_output(&edata, 9, 22, 1, 512, 16, 128);
  if streamed2.is_ok {
    var streamed2_bytes: Vec[UInt8] = streamed2.value;
    let d2 = brotli_decompress_auto(&mut streamed2_bytes);
    if d2.is_ok {
      var restored2: Vec[UInt8] = d2.value;
      edec_ok = buffers_equal(&edata, &restored2);
    }
  }
  failed = failed + report(edec_ok, "stream encode: quality 9 stream decodes to the original");

  // ---- corrupt stream: typed error with the real upstream code ----
  let mc = load_fixture("monkey.compressed");
  var cbytes: Vec[UInt8] = Vec[UInt8].new();
  if mc.is_ok { cbytes = mc.value; }
  var cok = false;
  if cbytes.len() > 20 {
    var corrupt: Vec[UInt8] = xorbyte(&cbytes, 0, 255);
    let r = brotli_decompress_auto(&mut corrupt);
    cok = err_bytes_is(r, "brotli.decoder: corrupt stream (_ERROR_FORMAT_EXUBERANT_NIBBLE)");
  }
  failed = failed + report(cok, "corrupt: header bit flip is a typed corrupt-stream error");

  // corrupt payload (mid-stream): typed error either way, never a crash
  var mok = false;
  if cbytes.len() > 20 {
    var corrupt2: Vec[UInt8] = xorbyte(&cbytes, cbytes.len() / 2, 255);
    let r2 = brotli_decompress_auto(&mut corrupt2);
    mok = err_bytes_is(r2, "brotli.decoder: corrupt stream (_ERROR_FORMAT_EXUBERANT_NIBBLE)") || err_bytes_is(r2, "brotli.decoder: truncated stream");
  }
  failed = failed + report(mok, "corrupt: mid-payload flip fails typed (corrupt or truncated)");

  // one-shot: corrupt and undersized capacity are typed errors too
  var osko = false;
  if cbytes.len() > 20 {
    var corrupt3: Vec[UInt8] = xorbyte(&cbytes, 0, 255);
    let r3 = brotli_decompress_oneshot(&mut corrupt3, 4096);
    if err_bytes_is(r3, "brotli.decoder: one-shot decompress failed (corrupt input or insufficient output capacity)") {
      var small: Vec[UInt8] = copyv(&cbytes);
      let r4 = brotli_decompress_oneshot(&mut small, 10);
      osko = err_bytes_is(r4, "brotli.decoder: one-shot decompress failed (corrupt input or insufficient output capacity)");
    }
  }
  failed = failed + report(osko, "one-shot: corrupt stream + too-small capacity are typed errors");

  // ---- truncated streams ----
  var tru = false;
  if cbytes.len() > 20 {
    var cut1: Vec[UInt8] = slicev(&cbytes, 0, cbytes.len() - 1);
    var cut2: Vec[UInt8] = slicev(&cbytes, 0, cbytes.len() / 2);
    let r5 = brotli_decompress_auto(&mut cut1);
    let r6 = brotli_decompress_auto(&mut cut2);
    tru = err_bytes_is(r5, "brotli.decoder: truncated stream") && err_bytes_is(r6, "brotli.decoder: truncated stream");
  }
  var empty_in: Vec[UInt8] = Vec[UInt8].new();
  let r7 = brotli_decompress_auto(&mut empty_in);
  tru = tru && err_bytes_is(r7, "brotli.decoder: empty input");
  failed = failed + report(tru, "truncated: last-byte and half cuts are typed, empty input is typed");

  // ---- bounded decompress (caller sizing loop) ----
  var bok2 = false;
  if spacked.len() > 0 {
    var sp2: Vec[UInt8] = copyv(&spacked);
    let ok_exact = brotli_decompress(&mut sp2, 20000);
    if ok_exact.is_ok {
      var got_exact: Vec[UInt8] = ok_exact.value;
      var sp3: Vec[UInt8] = copyv(&spacked);
      let too_small = brotli_decompress(&mut sp3, 19999);
      bok2 = buffers_equal(&sdata, &got_exact) && err_bytes_is(too_small, "brotli.decoder: output exceeds capacity");
    }
  }
  failed = failed + report(bok2, "bounded: exact capacity Ok, one byte short is typed");

  // ---- parameter validation ----
  var pok = false;
  if err_int_is(brotli_encoder_new(12, 22, 0), "brotli.encoder: invalid quality") {
    if err_int_is(brotli_encoder_new(5, 9, 0), "brotli.encoder: invalid lgwin") {
      if err_int_is(brotli_encoder_new(5, 22, 3), "brotli.encoder: invalid mode") {
        var pwork: Vec[UInt8] = pattern(64, 65);
        pok = err_bytes_is(brotli_compress(&mut pwork, 12, 22, 0), "brotli.encoder: invalid quality");
      }
    }
  }
  failed = failed + report(pok, "params: out-of-range quality/lgwin/mode are typed errors");

  // ---- handle misuse ----
  var misuse = true;
  var nullbuf: Vec[UInt8] = pattern(64, 65);
  var null_out: Vec[UInt8] = Vec[UInt8].new();
  let u1 = brotli_decoder_push(0, &mut nullbuf, 0, &mut null_out, 64);
  if u1.is_ok { misuse = false; } else { if !str_eq(u1.error, "brotli.decoder: invalid session") { misuse = false; } }
  let u2 = brotli_encoder_push(0, &mut nullbuf, 0, 0, &mut null_out, 64);
  if u2.is_ok { misuse = false; } else { if !str_eq(u2.error, "brotli.encoder: invalid session") { misuse = false; } }
  let u3 = brotli_encoder_take_output(0, &mut null_out, 8);
  if !err_int_is(u3, "brotli.encoder: invalid session") { misuse = false; }
  brotli_decoder_destroy(0);
  brotli_encoder_destroy(0);
  if brotli_encoder_is_finished(0) { misuse = false; }
  if brotli_encoder_set_parameter(0, 1, 5) { misuse = false; }
  if brotli_decoder_error_code(0) != BROTLI_DECODER_NO_ERROR { misuse = false; }
  failed = failed + report(misuse, "handles: 0-handle misuse and destroy(0) are safe and typed");

  var estr = str_eq(brotli_decoder_error_string(BROTLI_DECODER_ERROR_FORMAT_EXUBERANT_NIBBLE), "_ERROR_FORMAT_EXUBERANT_NIBBLE");
  estr = estr && str_eq(brotli_decoder_error_string(BROTLI_DECODER_NO_ERROR), "_NO_ERROR");
  estr = estr && str_eq(brotli_decoder_error_string(BROTLI_DECODER_ERROR_UNREACHABLE), "_ERROR_UNREACHABLE");
  estr = estr && str_eq(brotli_decoder_error_string(-99), "INVALID");
  failed = failed + report(estr, "errors: upstream error-string mapping (real text, INVALID fallback)");

  // ---- HTTP content-coding helpers ----
  var hok = str_eq(brotli_content_encoding(), "br");
  hok = hok && brotli_is_content_encoding("br");
  hok = hok && brotli_is_content_encoding("BR");
  hok = hok && brotli_is_content_encoding("bR");
  if brotli_is_content_encoding("gzip") { hok = false; }
  if brotli_is_content_encoding("brotli") { hok = false; }
  if brotli_is_content_encoding("") { hok = false; }
  if brotli_is_content_encoding("br x") { hok = false; }
  failed = failed + report(hok, "http: Content-Encoding token helpers (case-insensitive exact)");

  var http_body: Vec[UInt8] = text_bytes(4096);
  var http_work: Vec[UInt8] = copyv(&http_body);
  let hcr = brotli_compress(&mut http_work, 5, 22, 1);
  var http_ok = false;
  if hcr.is_ok {
    var http_enc: Vec[UInt8] = hcr.value;
    if str_eq(brotli_content_encoding(), "br") {
      let hdr2 = brotli_decompress_auto(&mut http_enc);
      if hdr2.is_ok {
        var body2: Vec[UInt8] = hdr2.value;
        http_ok = buffers_equal(&http_body, &body2);
      }
    }
  }
  failed = failed + report(http_ok, "http: response body round-trips under Content-Encoding: br");

  if failed == 0 {
    io.println("xiom.brotli: all tests passed");
  } else {
    io.println("xiom.brotli: tests failed");
  }
  return failed;
}
