// XIOM -- xiom.zkp conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the embedded BLS12-381 modulus (pinned against
// an independent hex string), Fp/Fp2 canonicality boundaries (zero, p - 1,
// exact p, all-0xff) with byte offsets in truncation errors, big/little
// endian conversion, compressed and uncompressed G1/G2 flag rules and
// infinity encodings, point summaries, Groth16 proof and verification-key
// layouts, the PLONK proof and verification-key profiles, scheme detection
// (including the documented ambiguous lengths), 0x-prefixed hex decoding, and
// a full hex -> proof -> accessors pipeline.
//
// All buffers are built in-test; the modulus expectation is the published
// BLS12-381 p literal decoded by a test-local hex reader (never read back
// from the library under test). All Str equality goes through
// compare.str_compare (BUG 17 discipline); every UInt8 read is widened with
// `(x as Int) & 0xFF`.

module zkp_tests
use xiom.io; use xiom.test; use xiom.zkp;
use xiom.string; use xiom.string.compare; use xiom.convert.int;

// --------------------------------------------------
//  Byte helpers (independent of src/zkp.xi)
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_eq(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if (((a[i] as Int) & 0xFF) != ((b[i] as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

fn zeros(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

fn rep_byte(b: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(b as UInt8);
    i = i + 1;
  }
  return out;
}

// Deterministic byte sequence of length n (covers 0x00 and bytes >= 0x80).
fn seq_bytes(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(((i * 37 + 7) % 256) as UInt8);
    i = i + 1;
  }
  return out;
}

fn hxval(value: Int) -> Int {
  if value >= 48 && value <= 57 {
    return value - 48;
  }
  if value >= 97 && value <= 102 {
    return value - 97 + 10;
  }
  if value >= 65 && value <= 70 {
    return value - 65 + 10;
  }
  return 0;
}

// Test-local hex reader for strings known to be even-length lowercase hex
// (used only for the pinned modulus literal).
fn hex_bytes(h: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i + 1 < h.len() {
    let hv = hxval((string.byte_at(h, i) as Int) & 0xFF);
    let lv = hxval((string.byte_at(h, i + 1) as Int) & 0xFF);
    out.push((hv * 16 + lv) as UInt8);
    i = i + 2;
  }
  return out;
}

fn hex2(b: Int) -> Str {
  let h = int_to_base(b, 16);
  if h.len() == 1 {
    return "0" + h;
  }
  return h;
}

fn hex_encode(v: Vec[UInt8]) -> Str {
  var s = "0x";
  var i = 0;
  while i < v.len() {
    s = s + hex2((v[i] as Int) & 0xFF);
    i = i + 1;
  }
  return s;
}

// --------------------------------------------------
//  Error assertion helpers
// --------------------------------------------------

fn err_bool(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

fn err_int(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

fn err_bytes(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

fn err_str(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

fn err_g16p(r: Result[Groth16Proof, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

fn err_g16vk(r: Result[Groth16Vk, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

fn err_plonkp(r: Result[PlonkProof, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

fn err_plonkvk(r: Result[PlonkVk, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

// --------------------------------------------------
//  Pinned constants and synthetic buffers
// --------------------------------------------------

// BLS12-381 base field modulus p, from the published curve parameters.
fn mod_pin() -> Vec[UInt8] {
  return hex_bytes("1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab");
}

// p - 1 (last byte 0xab -> 0xaa), canonical.
fn mod_minus_one() -> Vec[UInt8] {
  let m = mod_pin();
  var out = Vec[UInt8].new();
  var i = 0;
  while i < m.len() {
    if i == m.len() - 1 {
      let last: Int = ((m[i] as Int) & 0xFF) - 1;
      out.push(last as UInt8);
    } else {
      out.push(m[i]);
    }
    i = i + 1;
  }
  return out;
}

// Small big-endian Fp value in the last byte.
fn small_fp(value: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 48 {
    if i == 47 {
      out.push(value as UInt8);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return out;
}

// 48-byte G1 buffer whose top byte is exactly `flags` and whose x is zero.
fn g1c_flags(flags: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(flags as UInt8);
  var i = 1;
  while i < 48 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

// Compressed G1 with a small x in the last byte, sign flag per `sign`.
fn g1c_small(x: Int, sign: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push((128 + sign * 32) as UInt8);
  var i = 1;
  while i < 47 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  out.push(x as UInt8);
  return out;
}

// Compressed G1 built from a 48-byte Fp value (top flag bits cleared).
fn g1c_from_fp(v: Vec[UInt8], sign: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let b0: Int = ((v[0] as Int) & 0xFF) % 32;
  out.push((128 + sign * 32 + b0) as UInt8);
  var i = 1;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Compressed G1 infinity (0xC0, optionally with the sign bit for negatives).
fn g1c_inf(sign: Int) -> Vec[UInt8] {
  return g1c_flags(192 + sign * 32);
}

// Compressed G1 with the infinity flag and a nonzero x tail.
fn g1c_inf_x(x: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(192 as UInt8);
  var i = 1;
  while i < 47 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  out.push(x as UInt8);
  return out;
}

// Uncompressed G1 with small x and y in the last bytes.
fn g1u_small(x: Int, y: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 96 {
    if i == 47 {
      out.push(x as UInt8);
    } elif i == 95 {
      out.push(y as UInt8);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return out;
}

// Uncompressed G1 with the given top byte, x = 1, y = 1.
fn g1u_top(top: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(top as UInt8);
  var i = 1;
  while i < 96 {
    if i == 47 || i == 95 {
      out.push(1 as UInt8);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return out;
}

// Compressed G2 with small c0/c1 tails and a sign flag.
fn g2c_small(c0: Int, c1: Int, sign: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 96 {
    if i == 0 {
      out.push((128 + sign * 32) as UInt8);
    } elif i == 47 {
      out.push(c0 as UInt8);
    } elif i == 95 {
      out.push(c1 as UInt8);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return out;
}

// Compressed G2 infinity (0xC0, optionally with the sign bit).
fn g2c_inf(sign: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 96 {
    if i == 0 {
      out.push((192 + sign * 32) as UInt8);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return out;
}

// Compressed G2 infinity with a nonzero c1 tail.
fn g2c_inf_c1(c1: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 96 {
    if i == 0 {
      out.push(192 as UInt8);
    } elif i == 95 {
      out.push(c1 as UInt8);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return out;
}

// Compressed G2 built from two 48-byte Fp values.
fn g2c_from_fp(c0v: Vec[UInt8], c1v: Vec[UInt8], sign: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let b0: Int = ((c0v[0] as Int) & 0xFF) % 32;
  out.push((128 + sign * 32 + b0) as UInt8);
  var i = 1;
  while i < c0v.len() {
    out.push(c0v[i]);
    i = i + 1;
  }
  i = 0;
  while i < c1v.len() {
    out.push(c1v[i]);
    i = i + 1;
  }
  return out;
}

// Uncompressed G2 with small limb tails.
fn g2u_small(c0: Int, c1: Int, c2: Int, c3: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 192 {
    if i == 47 {
      out.push(c0 as UInt8);
    } elif i == 95 {
      out.push(c1 as UInt8);
    } elif i == 143 {
      out.push(c2 as UInt8);
    } elif i == 191 {
      out.push(c3 as UInt8);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return out;
}

// Uncompressed G2 with the given top byte and a nonzero tail.
fn g2u_top(top: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 192 {
    if i == 0 {
      out.push(top as UInt8);
    } elif i == 191 {
      out.push(1 as UInt8);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  return out;
}

// Groth16 proof: A (G1) || B (G2) || C (G1), all structurally valid.
fn groth16_blob() -> Vec[UInt8] {
  let a = g1c_small(1, 0);
  let b = g2c_small(3, 4, 1);
  let c = g1c_inf(0);
  return cat(cat(a, b), c);
}

// Groth16 verification key with `ic_count` synthetic IC points.
fn groth16_vk_blob(ic_count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out = cat(out, g1c_small(1, 0));
  out = cat(out, g2c_small(2, 3, 0));
  out = cat(out, g2c_small(4, 5, 1));
  out = cat(out, g2c_small(6, 7, 0));
  var i = 0;
  while i < ic_count {
    out = cat(out, g1c_small(i + 8, i % 2));
    i = i + 1;
  }
  return out;
}

// PLONK proof: 9 compressed G1 points then 3 x 32-byte evaluations.
fn plonk_blob_at(bad_index: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 9 {
    if i == bad_index {
      out = cat(out, g1c_flags(7));
    } else {
      out = cat(out, g1c_small(i + 1, 0));
    }
    i = i + 1;
  }
  out = cat(out, seq_bytes(96));
  return out;
}

fn plonk_blob() -> Vec[UInt8] {
  return plonk_blob_at(-1);
}

// PLONK verification key, structurally valid (n8 = 1024).
fn plonk_vk_blob() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(0 as UInt8);
  out.push(4 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out = cat(out, mod_minus_one());
  out = cat(out, small_fp(1));
  out = cat(out, small_fp(2));
  out = cat(out, g2c_small(5, 6, 0));
  var i = 0;
  while i < 7 {
    out = cat(out, g1c_small(i + 1, 0));
    i = i + 1;
  }
  return out;
}

// PLONK verification key with omega = p (non-canonical).
fn plonk_vk_blob_bad_omega() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(0 as UInt8);
  out.push(4 as UInt8);
  out.push(0 as UInt8);
  out.push(0 as UInt8);
  out = cat(out, mod_pin());
  out = cat(out, small_fp(1));
  out = cat(out, small_fp(2));
  out = cat(out, g2c_small(5, 6, 0));
  var i = 0;
  while i < 7 {
    out = cat(out, g1c_small(i + 1, 0));
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  let m = zkp_bls12_381_modulus();
  var ok = m.len() == 48;
  if zkp_fp_len() != 48 { ok = false; }
  if !bytes_eq(m, mod_pin()) { ok = false; }
  return assert(ok, "modulus pin: 48 bytes and equal to the published BLS12-381 p");
}

fn t2() -> TestResult {
  var ok = true;
  let z = zeros(48);
  let r0 = zkp_fp_validate(&z, 0);
  if !r0.is_ok { ok = false; } else { let v: Bool = r0.value; if !v { ok = false; } }
  let pm1 = mod_minus_one();
  let r1 = zkp_fp_validate(&pm1, 0);
  if !r1.is_ok { ok = false; } else { let v: Bool = r1.value; if !v { ok = false; } }
  let mp = mod_pin();
  let r2 = zkp_fp_validate(&mp, 0);
  if !r2.is_ok { ok = false; } else { let v: Bool = r2.value; if v { ok = false; } }
  let ff = rep_byte(255, 48);
  let r3 = zkp_fp_validate(&ff, 0);
  if !r3.is_ok { ok = false; } else { let v: Bool = r3.value; if v { ok = false; } }
  let short = zeros(47);
  if !err_bool(zkp_fp_validate(&short, 0), "zkp: fp needs 48 bytes at offset 0, have 47") { ok = false; }
  if !err_bool(zkp_fp_validate(&mp, 1), "zkp: fp needs 48 bytes at offset 1, have 47") { ok = false; }
  return assert(ok, "fp canonicality: zero and p-1 pass, exact p and 0xff..ff fail, offsets shown");
}

fn t3() -> TestResult {
  var ok = true;
  let z = zeros(48);
  let c0 = zkp_fp_compare_modulus(&z, 0);
  if !c0.is_ok { ok = false; } else { let v: Int = c0.value; if v != -1 { ok = false; } }
  let mp = mod_pin();
  let c1 = zkp_fp_compare_modulus(&mp, 0);
  if !c1.is_ok { ok = false; } else { let v: Int = c1.value; if v != 0 { ok = false; } }
  let ff = rep_byte(255, 48);
  let c2 = zkp_fp_compare_modulus(&ff, 0);
  if !c2.is_ok { ok = false; } else { let v: Int = c2.value; if v != 1 { ok = false; } }
  let im = zkp_fp_is_modulus(&mp, 0);
  if !im.is_ok { ok = false; } else { let v: Bool = im.value; if !v { ok = false; } }
  let im2 = zkp_fp_is_modulus(&z, 0);
  if !im2.is_ok { ok = false; } else { let v: Bool = im2.value; if v { ok = false; } }
  return assert(ok, "fp compare: -1/0/1 around p; is_modulus true only for the exact modulus");
}

fn t4() -> TestResult {
  var ok = true;
  let be = seq_bytes(48);
  let lr = zkp_fp_be_to_le(&be);
  if !lr.is_ok { ok = false; } else {
    let le: Vec[UInt8] = lr.value;
    if le.len() != 48 { ok = false; }
    let back = zkp_fp_le_to_be(&le);
    if !back.is_ok { ok = false; } else {
      let b2: Vec[UInt8] = back.value;
      if !bytes_eq(b2, be) { ok = false; }
    }
    let le0: Int = (le[0] as Int) & 0xFF;
    let be47: Int = (be[47] as Int) & 0xFF;
    if le0 != be47 { ok = false; }
  }
  let mp = mod_pin();
  let mle = zkp_fp_be_to_le(&mp);
  if !mle.is_ok { ok = false; } else {
    let m2: Vec[UInt8] = mle.value;
    let lastb: Int = (m2[47] as Int) & 0xFF;
    if lastb != 26 { ok = false; }
  }
  let short = zeros(47);
  if !err_bytes(zkp_fp_be_to_le(&short), "zkp: fp endian conversion needs 48 bytes, have 47") { ok = false; }
  return assert(ok, "fp endian: reversal round-trips, LE modulus starts with 0x1a movement, length pinned");
}

fn t5() -> TestResult {
  var ok = true;
  let pm1 = mod_minus_one();
  let z = zeros(48);
  let good = cat(pm1, z);
  let rg = zkp_fp2_validate(&good, 0);
  if !rg.is_ok { ok = false; } else { let v: Bool = rg.value; if !v { ok = false; } }
  let mp = mod_pin();
  let bad = cat(z, mp);
  let rb = zkp_fp2_validate(&bad, 0);
  if !rb.is_ok { ok = false; } else { let v: Bool = rb.value; if v { ok = false; } }
  let short = zeros(95);
  if !err_bool(zkp_fp2_validate(&short, 0), "zkp: fp2 needs 96 bytes at offset 0, have 95") { ok = false; }
  if !err_bool(zkp_fp2_validate(&good, 1), "zkp: fp2 needs 96 bytes at offset 1, have 95") { ok = false; }
  let be = seq_bytes(96);
  let lr = zkp_fp2_be_to_le(&be);
  if !lr.is_ok { ok = false; } else {
    let le: Vec[UInt8] = lr.value;
    if le.len() != 96 { ok = false; }
    let l0: Int = (le[0] as Int) & 0xFF;
    let b47: Int = (be[47] as Int) & 0xFF;
    if l0 != b47 { ok = false; }
    let l48: Int = (le[48] as Int) & 0xFF;
    let b95: Int = (be[95] as Int) & 0xFF;
    if l48 != b95 { ok = false; }
  }
  if !err_bytes(zkp_fp2_be_to_le(&short), "zkp: fp2 endian conversion needs 96 bytes, have 95") { ok = false; }
  return assert(ok, "fp2: c0||c1 canonicality and limb-wise little-endian conversion");
}

fn t6() -> TestResult {
  var ok = true;
  let p1 = g1c_small(7, 0);
  let r1 = zkp_g1_compressed_validate(&p1, 0);
  if !r1.is_ok { ok = false; } else { let v: Bool = r1.value; if !v { ok = false; } }
  let p2 = g1c_small(7, 1);
  let r2 = zkp_g1_compressed_validate(&p2, 0);
  if !r2.is_ok { ok = false; } else { let v: Bool = r2.value; if !v { ok = false; } }
  let p3 = g1c_flags(7);
  let r3 = zkp_g1_compressed_validate(&p3, 0);
  if !r3.is_ok { ok = false; } else { let v: Bool = r3.value; if v { ok = false; } }
  let mp = mod_pin();
  let p4 = g1c_from_fp(mp, 0);
  let r4 = zkp_g1_compressed_validate(&p4, 0);
  if !r4.is_ok { ok = false; } else { let v: Bool = r4.value; if v { ok = false; } }
  let pm1 = mod_minus_one();
  let p5 = g1c_from_fp(pm1, 0);
  let r5 = zkp_g1_compressed_validate(&p5, 0);
  if !r5.is_ok { ok = false; } else { let v: Bool = r5.value; if !v { ok = false; } }
  let short = zeros(47);
  if !err_bool(zkp_g1_compressed_validate(&short, 0), "zkp: g1 compressed needs 48 bytes at offset 0, have 47") { ok = false; }
  if !err_bool(zkp_g1_compressed_validate(&mp, 1), "zkp: g1 compressed needs 48 bytes at offset 1, have 47") { ok = false; }
  return assert(ok, "g1 compressed: canonical x under flags; x=p rejected, x=p-1 accepted; compression required");
}

fn t7() -> TestResult {
  var ok = true;
  let infok = g1c_inf(0);
  let r1 = zkp_g1_compressed_validate(&infok, 0);
  if !r1.is_ok { ok = false; } else { let v: Bool = r1.value; if !v { ok = false; } }
  let infsign = g1c_inf(1);
  let r2 = zkp_g1_compressed_validate(&infsign, 0);
  if !r2.is_ok { ok = false; } else { let v: Bool = r2.value; if v { ok = false; } }
  let infx = g1c_inf_x(1);
  let r3 = zkp_g1_compressed_validate(&infx, 0);
  if !r3.is_ok { ok = false; } else { let v: Bool = r3.value; if v { ok = false; } }
  let inftop = g1c_flags(193);
  let r4 = zkp_g1_compressed_validate(&inftop, 0);
  if !r4.is_ok { ok = false; } else { let v: Bool = r4.value; if v { ok = false; } }
  let xzero = g1c_small(0, 0);
  let r5 = zkp_g1_compressed_validate(&xzero, 0);
  if !r5.is_ok { ok = false; } else { let v: Bool = r5.value; if !v { ok = false; } }
  return assert(ok, "g1 compressed infinity: flag plus zero x; sign, x tail and masked top rejected");
}

fn t8() -> TestResult {
  var ok = true;
  let u = g1u_small(1, 2);
  let r1 = zkp_g1_uncompressed_validate(&u, 0);
  if !r1.is_ok { ok = false; } else { let v: Bool = r1.value; if !v { ok = false; } }
  let uz = zeros(96);
  let r2 = zkp_g1_uncompressed_validate(&uz, 0);
  if !r2.is_ok { ok = false; } else { let v: Bool = r2.value; if !v { ok = false; } }
  let uflag = g1u_top(128);
  let r3 = zkp_g1_uncompressed_validate(&uflag, 0);
  if !r3.is_ok { ok = false; } else { let v: Bool = r3.value; if v { ok = false; } }
  let mp = mod_pin();
  let uxp = cat(mp, small_fp(2));
  let r4 = zkp_g1_uncompressed_validate(&uxp, 0);
  if !r4.is_ok { ok = false; } else { let v: Bool = r4.value; if v { ok = false; } }
  let pm1 = mod_minus_one();
  let uok = cat(pm1, small_fp(2));
  let r5 = zkp_g1_uncompressed_validate(&uok, 0);
  if !r5.is_ok { ok = false; } else { let v: Bool = r5.value; if !v { ok = false; } }
  let short = zeros(95);
  if !err_bool(zkp_g1_uncompressed_validate(&short, 0), "zkp: g1 uncompressed needs 96 bytes at offset 0, have 95") { ok = false; }
  return assert(ok, "g1 uncompressed: flags cleared, all-zero infinity, x and y canonical");
}

fn t9() -> TestResult {
  var ok = true;
  let g = g2c_small(9, 10, 1);
  let r1 = zkp_g2_compressed_validate(&g, 0);
  if !r1.is_ok { ok = false; } else { let v: Bool = r1.value; if !v { ok = false; } }
  let gi = g2c_inf(0);
  let r2 = zkp_g2_compressed_validate(&gi, 0);
  if !r2.is_ok { ok = false; } else { let v: Bool = r2.value; if !v { ok = false; } }
  let gis = g2c_inf(1);
  let r3 = zkp_g2_compressed_validate(&gis, 0);
  if !r3.is_ok { ok = false; } else { let v: Bool = r3.value; if v { ok = false; } }
  let gic = g2c_inf_c1(1);
  let r4 = zkp_g2_compressed_validate(&gic, 0);
  if !r4.is_ok { ok = false; } else { let v: Bool = r4.value; if v { ok = false; } }
  let mp = mod_pin();
  let gc0 = g2c_from_fp(mp, small_fp(1), 0);
  let r5 = zkp_g2_compressed_validate(&gc0, 0);
  if !r5.is_ok { ok = false; } else { let v: Bool = r5.value; if v { ok = false; } }
  let gc1 = g2c_from_fp(small_fp(1), mp, 0);
  let r6 = zkp_g2_compressed_validate(&gc1, 0);
  if !r6.is_ok { ok = false; } else { let v: Bool = r6.value; if v { ok = false; } }
  let pm1 = mod_minus_one();
  let gok = g2c_from_fp(pm1, pm1, 1);
  let r7 = zkp_g2_compressed_validate(&gok, 0);
  if !r7.is_ok { ok = false; } else { let v: Bool = r7.value; if !v { ok = false; } }
  let short = zeros(95);
  if !err_bool(zkp_g2_compressed_validate(&short, 0), "zkp: g2 compressed needs 96 bytes at offset 0, have 95") { ok = false; }
  if !err_bool(zkp_g2_compressed_validate(&g, 1), "zkp: g2 compressed needs 96 bytes at offset 1, have 95") { ok = false; }
  return assert(ok, "g2 compressed: both limbs canonical; infinity requires flag, zero limbs and no sign");
}

fn t10() -> TestResult {
  var ok = true;
  let u = g2u_small(1, 2, 3, 4);
  let r1 = zkp_g2_uncompressed_validate(&u, 0);
  if !r1.is_ok { ok = false; } else { let v: Bool = r1.value; if !v { ok = false; } }
  let uz = zeros(192);
  let r2 = zkp_g2_uncompressed_validate(&uz, 0);
  if !r2.is_ok { ok = false; } else { let v: Bool = r2.value; if !v { ok = false; } }
  let uflag = g2u_top(128);
  let r3 = zkp_g2_uncompressed_validate(&uflag, 0);
  if !r3.is_ok { ok = false; } else { let v: Bool = r3.value; if v { ok = false; } }
  let mp = mod_pin();
  let ubad = cat(cat(small_fp(1), mp), cat(small_fp(1), small_fp(2)));
  let r4 = zkp_g2_uncompressed_validate(&ubad, 0);
  if !r4.is_ok { ok = false; } else { let v: Bool = r4.value; if v { ok = false; } }
  let short = zeros(191);
  if !err_bool(zkp_g2_uncompressed_validate(&short, 0), "zkp: g2 uncompressed needs 192 bytes at offset 0, have 191") { ok = false; }
  return assert(ok, "g2 uncompressed: flags cleared, all-zero infinity, all four limbs canonical");
}

fn t11() -> TestResult {
  var ok = true;
  if zkp_point_length(0) != 48 { ok = false; }
  if zkp_point_length(1) != 96 { ok = false; }
  if zkp_point_length(2) != 96 { ok = false; }
  if zkp_point_length(3) != 192 { ok = false; }
  if zkp_point_length(99) != -1 { ok = false; }
  if !streq(zkp_point_kind_name(0), "G1 compressed") { ok = false; }
  if !streq(zkp_point_kind_name(1), "G1 uncompressed") { ok = false; }
  if !streq(zkp_point_kind_name(2), "G2 compressed") { ok = false; }
  if !streq(zkp_point_kind_name(3), "G2 uncompressed") { ok = false; }
  if !streq(zkp_point_kind_name(99), "") { ok = false; }
  let f1 = g1c_flags(128);
  let r1 = zkp_point_flags(0, &f1, 0);
  if !r1.is_ok { ok = false; } else { let v: Int = r1.value; if v != 4 { ok = false; } }
  let f2 = g1c_flags(192);
  let r2 = zkp_point_flags(0, &f2, 0);
  if !r2.is_ok { ok = false; } else { let v: Int = r2.value; if v != 6 { ok = false; } }
  let f3 = g1c_flags(160);
  let r3 = zkp_point_flags(0, &f3, 0);
  if !r3.is_ok { ok = false; } else { let v: Int = r3.value; if v != 5 { ok = false; } }
  let f4 = g1c_flags(224);
  let r4 = zkp_point_flags(0, &f4, 0);
  if !r4.is_ok { ok = false; } else { let v: Int = r4.value; if v != 7 { ok = false; } }
  let z1 = zeros(1);
  if !err_int(zkp_point_flags(99, &z1, 0), "zkp: unknown point kind 99") { ok = false; }
  if !err_int(zkp_point_flags(1, &f1, 0), "zkp: G1 uncompressed needs 96 bytes at offset 0, have 48") { ok = false; }
  return assert(ok, "point lengths, kind names and packed flag extraction (divisor/modulo only)");
}

fn t12() -> TestResult {
  var ok = true;
  let s1 = zkp_point_summary(0, &g1c_flags(160), 0);
  if !s1.is_ok { ok = false; } else { let v: Str = s1.value; if !streq(v, "G1 compressed compression=1 infinity=0 sign=1") { ok = false; } }
  let z192 = zeros(192);
  let s2 = zkp_point_summary(3, &z192, 0);
  if !s2.is_ok { ok = false; } else { let v: Str = s2.value; if !streq(v, "G2 uncompressed compression=0 infinity=0 sign=0") { ok = false; } }
  let s3 = zkp_point_summary(2, &g2c_inf(0), 0);
  if !s3.is_ok { ok = false; } else { let v: Str = s3.value; if !streq(v, "G2 compressed compression=1 infinity=1 sign=0") { ok = false; } }
  let z1 = zeros(1);
  if !err_str(zkp_point_summary(42, &z1, 0), "zkp: unknown point kind 42") { ok = false; }
  let g2 = g2c_inf(0);
  let rv = zkp_point_validate(2, &g2, 0);
  if !rv.is_ok { ok = false; } else { let v: Bool = rv.value; if !v { ok = false; } }
  let rv2 = zkp_point_validate(1, &g2, 0);
  if !rv2.is_ok { ok = false; } else { let v: Bool = rv2.value; if v { ok = false; } }
  if !err_bool(zkp_point_validate(99, &z1, 0), "zkp: unknown point kind 99") { ok = false; }
  return assert(ok, "point summary strings and kind dispatch through zkp_point_validate");
}

fn t13() -> TestResult {
  var ok = true;
  let blob = groth16_blob();
  if blob.len() != 192 { ok = false; }
  if zkp_groth16_proof_len() != 192 { ok = false; }
  let d = zkp_groth16_proof_decode(&blob);
  if !d.is_ok { ok = false; } else {
    let p: Groth16Proof = d.value;
    let a = zkp_groth16_proof_a(&p);
    let b = zkp_groth16_proof_b(&p);
    let c = zkp_groth16_proof_c(&p);
    if a.len() != 48 { ok = false; }
    if b.len() != 96 { ok = false; }
    if c.len() != 48 { ok = false; }
    if !bytes_eq(cat(cat(a, b), c), blob) { ok = false; }
  }
  let z191 = zeros(191);
  let z193 = zeros(193);
  if !err_g16p(zkp_groth16_proof_decode(&z191), "zkp: groth16 proof needs 192 bytes at offset 0, have 191") { ok = false; }
  if !err_g16p(zkp_groth16_proof_decode(&z193), "zkp: groth16 proof needs 192 bytes at offset 0, have 193") { ok = false; }
  let v = zkp_groth16_proof_validate(&blob);
  if !v.is_ok { ok = false; } else { let bv: Bool = v.value; if !bv { ok = false; } }
  return assert(ok, "groth16 proof: 192-byte A||B||C decode, accessors round-trip, lengths pinned");
}

fn t14() -> TestResult {
  var ok = true;
  let badc = cat(cat(g1c_small(1, 0), g2c_small(3, 4, 1)), g1c_flags(7));
  let v1 = zkp_groth16_proof_validate(&badc);
  if !v1.is_ok { ok = false; } else { let v: Bool = v1.value; if v { ok = false; } }
  let badb = cat(cat(g1c_small(1, 0), g2c_inf(1)), g1c_inf(0));
  let v2 = zkp_groth16_proof_validate(&badb);
  if !v2.is_ok { ok = false; } else { let v: Bool = v2.value; if v { ok = false; } }
  let mp = mod_pin();
  let bada = cat(cat(g1c_from_fp(mp, 0), g2c_small(3, 4, 1)), g1c_inf(0));
  let v3 = zkp_groth16_proof_validate(&bada);
  if !v3.is_ok { ok = false; } else { let v: Bool = v3.value; if v { ok = false; } }
  let z190 = zeros(190);
  if !err_bool(zkp_groth16_proof_validate(&z190), "zkp: groth16 proof needs 192 bytes at offset 0, have 190") { ok = false; }
  return assert(ok, "groth16 validate: corrupted A/B/C are Ok(false), wrong total length is Err");
}

fn t15() -> TestResult {
  var ok = true;
  if zkp_groth16_vk_len(0) != 336 { ok = false; }
  if zkp_groth16_vk_len(2) != 432 { ok = false; }
  if zkp_groth16_vk_len(-1) != -1 { ok = false; }
  let blob = groth16_vk_blob(2);
  if blob.len() != 432 { ok = false; }
  let d = zkp_groth16_vk_decode(&blob, 2);
  if !d.is_ok { ok = false; } else {
    let vk: Groth16Vk = d.value;
    if zkp_groth16_vk_ic_count(&vk) != 2 { ok = false; }
    if zkp_groth16_vk_alpha(&vk).len() != 48 { ok = false; }
    if zkp_groth16_vk_beta(&vk).len() != 96 { ok = false; }
    if zkp_groth16_vk_gamma(&vk).len() != 96 { ok = false; }
    if zkp_groth16_vk_delta(&vk).len() != 96 { ok = false; }
    let ic0 = zkp_groth16_vk_ic_point(&vk, 0);
    if !ic0.is_ok { ok = false; } else { let v: Vec[UInt8] = ic0.value; if !bytes_eq(v, g1c_small(8, 0)) { ok = false; } }
    let ic1 = zkp_groth16_vk_ic_point(&vk, 1);
    if !ic1.is_ok { ok = false; } else { let v: Vec[UInt8] = ic1.value; if !bytes_eq(v, g1c_small(9, 1)) { ok = false; } }
    if !err_bytes(zkp_groth16_vk_ic_point(&vk, 2), "zkp: groth16 vk ic index 2 out of range (count 2)") { ok = false; }
    if !err_bytes(zkp_groth16_vk_ic_point(&vk, -1), "zkp: groth16 vk ic index -1 out of range (count 2)") { ok = false; }
  }
  let v = zkp_groth16_vk_validate(&blob, 2);
  if !v.is_ok { ok = false; } else { let bv: Bool = v.value; if !bv { ok = false; } }
  let mp = mod_pin();
  var bad = groth16_vk_blob(1);
  bad = cat(bad, g1c_from_fp(mp, 0));
  let vb = zkp_groth16_vk_validate(&bad, 2);
  if !vb.is_ok { ok = false; } else { let bv: Bool = vb.value; if bv { ok = false; } }
  if !err_g16vk(zkp_groth16_vk_decode(&blob, -1), "zkp: groth16 vk ic count -1 is negative") { ok = false; }
  if !err_g16vk(zkp_groth16_vk_decode(&blob, 3), "zkp: groth16 vk with 3 ic points needs 480 bytes at offset 0, have 432") { ok = false; }
  return assert(ok, "groth16 vk: fixed part plus caller-supplied IC count, accessors and validation");
}

fn t16() -> TestResult {
  var ok = true;
  let blob = plonk_blob();
  if blob.len() != 528 { ok = false; }
  if zkp_plonk_proof_len() != 528 { ok = false; }
  let d = zkp_plonk_proof_decode(&blob);
  if !d.is_ok { ok = false; } else {
    let p: PlonkProof = d.value;
    let g0 = zkp_plonk_proof_g1(&p, 0);
    if !g0.is_ok { ok = false; } else { let v: Vec[UInt8] = g0.value; if !bytes_eq(v, g1c_small(1, 0)) { ok = false; } }
    let g8 = zkp_plonk_proof_g1(&p, 8);
    if !g8.is_ok { ok = false; } else { let v: Vec[UInt8] = g8.value; if !bytes_eq(v, g1c_small(9, 0)) { ok = false; } }
    let e2 = zkp_plonk_proof_eval(&p, 2);
    if !e2.is_ok { ok = false; } else { let v: Vec[UInt8] = e2.value; if v.len() != 32 { ok = false; } }
    if !err_bytes(zkp_plonk_proof_g1(&p, 9), "zkp: plonk g1 index 9 out of range 0..8") { ok = false; }
    if !err_bytes(zkp_plonk_proof_eval(&p, 3), "zkp: plonk eval index 3 out of range 0..2") { ok = false; }
  }
  if !streq(zkp_plonk_proof_point_name(0), "A") { ok = false; }
  if !streq(zkp_plonk_proof_point_name(8), "W2") { ok = false; }
  if !streq(zkp_plonk_proof_point_name(9), "") { ok = false; }
  if !streq(zkp_plonk_proof_eval_name(0), "a") { ok = false; }
  if !streq(zkp_plonk_proof_eval_name(2), "c") { ok = false; }
  if !streq(zkp_plonk_proof_eval_name(3), "") { ok = false; }
  let v = zkp_plonk_proof_validate(&blob);
  if !v.is_ok { ok = false; } else { let bv: Bool = v.value; if !bv { ok = false; } }
  let z527 = zeros(527);
  if !err_bool(zkp_plonk_proof_validate(&z527), "zkp: plonk proof needs 528 bytes at offset 0, have 527") { ok = false; }
  let bad = plonk_blob_at(4);
  let vb = zkp_plonk_proof_validate(&bad);
  if !vb.is_ok { ok = false; } else { let bv: Bool = vb.value; if bv { ok = false; } }
  let db = zkp_plonk_proof_decode(&bad);
  if !db.is_ok { ok = false; } else {
    let pp: PlonkProof = db.value;
    if pp.points.len() != 432 { ok = false; }
    if pp.evals.len() != 96 { ok = false; }
  }
  return assert(ok, "plonk proof: 9 G1 + 3 evals layout, accessors, names, validation");
}

fn t17() -> TestResult {
  var ok = true;
  let blob = plonk_vk_blob();
  if blob.len() != 580 { ok = false; }
  if zkp_plonk_vk_len() != 580 { ok = false; }
  let d = zkp_plonk_vk_decode(&blob);
  if !d.is_ok { ok = false; } else {
    let vk: PlonkVk = d.value;
    if zkp_plonk_vk_n8(&vk) != 1024 { ok = false; }
    if zkp_plonk_vk_omega(&vk).len() != 48 { ok = false; }
    if zkp_plonk_vk_k1(&vk).len() != 48 { ok = false; }
    if zkp_plonk_vk_k2(&vk).len() != 48 { ok = false; }
    if zkp_plonk_vk_x2(&vk).len() != 96 { ok = false; }
    let g6 = zkp_plonk_vk_g1(&vk, 6);
    if !g6.is_ok { ok = false; } else { let v: Vec[UInt8] = g6.value; if !bytes_eq(v, g1c_small(7, 0)) { ok = false; } }
    if !err_bytes(zkp_plonk_vk_g1(&vk, 7), "zkp: plonk vk g1 index 7 out of range 0..6") { ok = false; }
  }
  if !streq(zkp_plonk_vk_point_name(0), "Qm") { ok = false; }
  if !streq(zkp_plonk_vk_point_name(6), "S2") { ok = false; }
  if !streq(zkp_plonk_vk_point_name(7), "") { ok = false; }
  let v = zkp_plonk_vk_validate(&blob);
  if !v.is_ok { ok = false; } else { let bv: Bool = v.value; if !bv { ok = false; } }
  let bad = plonk_vk_blob_bad_omega();
  let vb = zkp_plonk_vk_validate(&bad);
  if !vb.is_ok { ok = false; } else { let bv: Bool = vb.value; if bv { ok = false; } }
  let z579 = zeros(579);
  if !err_plonkvk(zkp_plonk_vk_decode(&z579), "zkp: plonk vk needs 580 bytes at offset 0, have 579") { ok = false; }
  return assert(ok, "plonk vk: n8 prefix, omega/k1/k2/X_2/7 G1 profile, accessors, validation");
}

fn t18() -> TestResult {
  var ok = true;
  let z192 = zeros(192);
  let z528 = zeros(528);
  let z96 = zeros(96);
  if zkp_scheme_detect(&z192) != 1 { ok = false; }
  if zkp_scheme_detect(&z528) != 2 { ok = false; }
  if zkp_scheme_detect(&z96) != 0 { ok = false; }
  if !streq(zkp_scheme_name(1), "groth16") { ok = false; }
  if !streq(zkp_scheme_name(2), "plonk") { ok = false; }
  if !streq(zkp_scheme_name(0), "unknown") { ok = false; }
  if !streq(zkp_scheme_name(77), "unknown") { ok = false; }
  if zkp_scheme_expected_len(1) != 192 { ok = false; }
  if zkp_scheme_expected_len(2) != 528 { ok = false; }
  if zkp_scheme_expected_len(0) != -1 { ok = false; }
  let z100 = zeros(100);
  if !err_bool(zkp_blob_validate(&z100), "zkp: unknown scheme for length 100 (expected 192 groth16 or 528 plonk)") { ok = false; }
  let vg = zkp_blob_validate(&groth16_blob());
  if !vg.is_ok { ok = false; } else { let bv: Bool = vg.value; if !bv { ok = false; } }
  let vp = zkp_blob_validate(&plonk_blob());
  if !vp.is_ok { ok = false; } else { let bv: Bool = vp.value; if !bv { ok = false; } }
  let vz = zkp_blob_validate(&z192);
  if !vz.is_ok { ok = false; } else { let bv: Bool = vz.value; if bv { ok = false; } }
  return assert(ok, "scheme detection by length (192 groth16, 528 plonk, ambiguous lengths unknown)");
}

fn t19() -> TestResult {
  var ok = true;
  let r1 = zkp_proof_hex_decode("0x00ff107f");
  if !r1.is_ok { ok = false; } else {
    let v: Vec[UInt8] = r1.value;
    let expect = cat(cat(cat(rep_byte(0, 1), rep_byte(255, 1)), rep_byte(16, 1)), rep_byte(127, 1));
    if !bytes_eq(v, expect) { ok = false; }
    if v.len() != 4 { ok = false; }
    let x0: Int = (v[0] as Int) & 0xFF;
    let x1: Int = (v[1] as Int) & 0xFF;
    let x2: Int = (v[2] as Int) & 0xFF;
    let x3: Int = (v[3] as Int) & 0xFF;
    if x0 != 0 || x1 != 255 || x2 != 16 || x3 != 127 { ok = false; }
  }
  let r2 = zkp_proof_hex_decode("0XAbCd");
  if !r2.is_ok { ok = false; } else {
    let v: Vec[UInt8] = r2.value;
    if v.len() != 2 { ok = false; }
    let y0: Int = (v[0] as Int) & 0xFF;
    let y1: Int = (v[1] as Int) & 0xFF;
    if y0 != 171 || y1 != 205 { ok = false; }
  }
  let r3 = zkp_proof_hex_decode("0x");
  if !r3.is_ok { ok = false; } else { let v: Vec[UInt8] = r3.value; if v.len() != 0 { ok = false; } }
  if !err_bytes(zkp_proof_hex_decode("00ff"), "zkp: hex text must start with 0x") { ok = false; }
  if !err_bytes(zkp_proof_hex_decode("0"), "zkp: hex text must start with 0x") { ok = false; }
  if !err_bytes(zkp_proof_hex_decode("0xabc"), "zkp: hex payload length 3 is odd") { ok = false; }
  if !err_bytes(zkp_proof_hex_decode("0xg0"), "zkp: hex invalid character at offset 2 (byte 103)") { ok = false; }
  if !err_bytes(zkp_proof_hex_decode("0x12G4"), "zkp: hex invalid character at offset 4 (byte 71)") { ok = false; }
  return assert(ok, "hex decode: 0x/0X prefix, mixed case, odd payload and bad digits carry offsets");
}

fn t20() -> TestResult {
  var ok = true;
  let blob = groth16_blob();
  let text = hex_encode(blob);
  let d = zkp_proof_hex_decode(text);
  if !d.is_ok { ok = false; } else {
    let raw: Vec[UInt8] = d.value;
    if !bytes_eq(raw, blob) { ok = false; }
    if zkp_scheme_detect(&raw) != 1 { ok = false; }
    let v = zkp_groth16_proof_validate(&raw);
    if !v.is_ok { ok = false; } else { let bv: Bool = v.value; if !bv { ok = false; } }
    let dp = zkp_groth16_proof_decode(&raw);
    if !dp.is_ok { ok = false; } else {
      let p: Groth16Proof = dp.value;
      let a = zkp_groth16_proof_a(&p);
      let b = zkp_groth16_proof_b(&p);
      let c = zkp_groth16_proof_c(&p);
      if !bytes_eq(cat(cat(a, b), c), blob) { ok = false; }
    }
  }
  return assert(ok, "pipeline: hex text -> bytes -> scheme -> decode -> accessors reconstruct the blob");
}

fn main() -> Int {
  io.println("=== xiom.zkp conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.zkp: all tests passed");
  } else {
    io.println("xiom.zkp: tests failed");
  }
  return failed;
}
