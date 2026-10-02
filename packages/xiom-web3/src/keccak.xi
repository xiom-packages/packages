// XIOM -- xiom.web3.keccak: pure-XIOM Keccak-256
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Original Keccak padding (domain byte 0x01), NOT NIST SHA3-256 (0x06).
// Rate 136 bytes, 32-byte digest, 24 rounds of Keccak-f[1600] over 25 signed
// 64-bit Int lanes. The logical rotate follows the stdlib SHA-512/BLAKE2b
// idiom (floor-division right shift + wrapping left multiply); the context is
// per-module so it never collides with the stdlib helpers.
//
// Verified vectors: keccak256("") = c5d24601..., "abc" = 4e03657a...,
// the fox sentence = 4d741b6f..., "transfer(address,uint256)" = a9059cbb....

module xiom.web3.keccak

use xiom.encoding.hex;

// 2^n for n in 0..64 by repeated multiplication; the last step wraps to the
// correct two's-complement bit pattern for 2^63.
fn _kc_pow2(n: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < n {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

// Logical right shift of a signed 64-bit value: high bits zero-fill, so
// negative operands use floor division. The general formula below divides by
// 2^n, but 2^63 does not fit a positive Int (it IS Int64_MIN), and
// x / Int64_MIN turns positive for negative x -- so n = 63 is special-cased
// (the result is exactly the sign bit). NOTE: the same idiom in
// xiom.crypto.hash (_u64_lshr / _u64_shr) lacks this guard; it is only safe
// there because those callers never shift by 63.
fn _kc_lshr(x: Int, n: Int) -> Int {
  if n <= 0 { return x; }
  if n >= 64 { return 0; }
  if n == 63 {
    if x < 0 { return 1; }
    return 0;
  }
  let p: Int = _kc_pow2(n);
  if x >= 0 { return x / p; }
  var q = x / p;
  if (x % p) != 0 {
    q = q - 1;
  }
  return q + _kc_pow2(64 - n);
}

// Rotate right (logical) by n bits, 0..63.
fn _kc_rotr(x: Int, n: Int) -> Int {
  if n <= 0 { return x; }
  if n >= 64 { return x; }
  let right: Int = _kc_lshr(x, n);
  let left: Int = x * _kc_pow2(64 - n);
  return right | left;
}

// Rotate left by n bits (0..63): rotr by 64 - n; rotr(x, 64) returns x.
fn _kc_rotl(x: Int, n: Int) -> Int {
  return _kc_rotr(x, 64 - n);
}

// The 24 Keccak-f[1600] round constants (iota).
fn _kc_rc_table() -> Vec[Int] {
  var rc = Vec[Int].new();
  rc.push(0x0000000000000001); rc.push(0x0000000000008082);
  rc.push(0x800000000000808a); rc.push(0x8000000080008000);
  rc.push(0x000000000000808b); rc.push(0x0000000080000001);
  rc.push(0x8000000080008081); rc.push(0x8000000000008009);
  rc.push(0x000000000000008a); rc.push(0x0000000000000088);
  rc.push(0x0000000080008009); rc.push(0x000000008000000a);
  rc.push(0x000000008000808b); rc.push(0x800000000000008b);
  rc.push(0x8000000000008089); rc.push(0x8000000000008003);
  rc.push(0x8000000000008002); rc.push(0x8000000000000080);
  rc.push(0x000000000000800a); rc.push(0x800000008000000a);
  rc.push(0x8000000080008081); rc.push(0x8000000000008080);
  rc.push(0x0000000080000001); rc.push(0x8000000080008008);
  return rc;
}

// Rho rotation offsets indexed by lane x + 5*y.
fn _kc_rho_table() -> Vec[Int] {
  var r = Vec[Int].new();
  r.push(0); r.push(1); r.push(62); r.push(28); r.push(27);
  r.push(36); r.push(44); r.push(6); r.push(55); r.push(20);
  r.push(3); r.push(10); r.push(43); r.push(25); r.push(39);
  r.push(41); r.push(45); r.push(15); r.push(21); r.push(8);
  r.push(18); r.push(2); r.push(61); r.push(56); r.push(14);
  return r;
}

// The 25-lane all-zero permutation state.
fn _kc_state_new() -> Vec[Int] {
  var st = Vec[Int].new();
  var i = 0;
  while i < 25 {
    st.push(0);
    i = i + 1;
  }
  return st;
}

// One Keccak-f[1600] permutation: theta, rho+pi, chi, iota, 24 rounds.
// State is 25 lanes, lane index x + 5*y; every scalar is 64-bit (Int).
fn _kc_f1600(st: &mut Vec[Int]) {
  let rc = _kc_rc_table();
  let rho = _kc_rho_table();
  var round = 0;
  while round < 24 {
    // theta
    var c: [5]Int;
    var x = 0;
    while x < 5 {
      let a0: Int = st[x];
      let a1: Int = st[x + 5];
      let a2: Int = st[x + 10];
      let a3: Int = st[x + 15];
      let a4: Int = st[x + 20];
      c[x] = a0 ^ a1 ^ a2 ^ a3 ^ a4;
      x = x + 1;
    }
    x = 0;
    while x < 5 {
      let cm: Int = c[(x + 4) % 5];
      let cp: Int = c[(x + 1) % 5];
      let d: Int = cm ^ _kc_rotl(cp, 1);
      var y = 0;
      while y < 5 {
        let cur: Int = st[x + 5 * y];
        st[x + 5 * y] = cur ^ d;
        y = y + 1;
      }
      x = x + 1;
    }
    // rho + pi: B[y + 5*((2x+3y) mod 5)] = rotl(A[x + 5y], rho[x + 5y])
    var b: [25]Int;
    x = 0;
    while x < 5 {
      var y = 0;
      while y < 5 {
        let src = x + 5 * y;
        let a: Int = st[src];
        let off: Int = rho[src];
        let dst = y + 5 * ((2 * x + 3 * y) % 5);
        b[dst] = _kc_rotl(a, off);
        y = y + 1;
      }
      x = x + 1;
    }
    // chi
    x = 0;
    while x < 5 {
      var y = 0;
      while y < 5 {
        let bi: Int = b[x + 5 * y];
        let b1: Int = b[((x + 1) % 5) + 5 * y];
        let b2: Int = b[((x + 2) % 5) + 5 * y];
        st[x + 5 * y] = bi ^ ((~b1) & b2);
        y = y + 1;
      }
      x = x + 1;
    }
    // iota
    let s0: Int = st[0];
    let r: Int = rc[round];
    st[0] = s0 ^ r;
    round = round + 1;
  }
}

// XOR one 136-byte rate block (17 little-endian lanes) into the state.
fn _kc_absorb(data: &Vec[UInt8], off: Int, st: &mut Vec[Int]) {
  var lane = 0;
  while lane < 17 {
    var v: Int = 0;
    var j = 7;
    while j >= 0 {
      let b: UInt8 = data[off + lane * 8 + j];
      v = v * 256 + ((b as Int) & 0xFF);
      j = j - 1;
    }
    let cur: Int = st[lane];
    st[lane] = cur ^ v;
    lane = lane + 1;
  }
}

// First 32 digest bytes: lanes 0..3 little-endian (low byte first).
fn _kc_squeeze(st: &Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var lane = 0;
  while lane < 4 {
    var x: Int = st[lane];
    var k = 0;
    while k < 8 {
      out.push((x & 0xFF) as UInt8);
      x = x >> 8;
      k = k + 1;
    }
    lane = lane + 1;
  }
  return out;
}

/// Keccak-256 (Ethereum's hash, pad byte 0x01) of `data`; 32 bytes.
pub fn keccak256(data: &Vec[UInt8]) -> Vec[UInt8] {
  let rate = 136;
  var padded = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i < n {
    let b: UInt8 = data[i];
    padded.push(b);
    i = i + 1;
  }
  padded.push(0x01 as UInt8);
  while padded.len() % rate != 0 {
    padded.push(0 as UInt8);
  }
  let last = padded.len() - 1;
  let lb: UInt8 = padded[last];
  padded[last] = ((lb as Int) | 0x80) as UInt8;
  var st = _kc_state_new();
  let blocks = padded.len() / rate;
  var bi = 0;
  while bi < blocks {
    _kc_absorb(&padded, bi * rate, &mut st);
    _kc_f1600(&mut st);
    bi = bi + 1;
  }
  return _kc_squeeze(&st);
}

/// Lowercase hex of the Keccak-256 digest (64 digits, no 0x prefix).
pub fn keccak256_hex(data: &Vec[UInt8]) -> Str {
  let h = keccak256(data);
  return hex.hex_encode(&h);
}
