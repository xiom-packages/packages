// XIOM -- xiom.vault.unseal: GF(256) Shamir sharing and unseal progress
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM secret-sharing and unseal-progress MODEL, matching the shape of a
// vault unseal ceremony:
//
//   * GF(256) arithmetic modulo the AES polynomial x^8 + x^4 + x^3 + x + 1
//     (0x11B): multiplication (Russian peasant, no shifts), inverse by
//     exhaustive search (a * inv(a) == 1), division.
//   * Shamir split: secret bytes are the polynomial constant terms, each
//     share carries the x coordinate (1..255) followed by f(x) for every
//     secret byte. Coefficients are caller-supplied (known-answer tests) or
//     derived deterministically from a seed (xorshift-style stream).
//   * Shamir combine: Lagrange interpolation at x = 0 over the supplied
//     distinct, non-zero share coordinates. At least two shares are required;
//     the reconstruction is byte-exact.
//   * Unseal progress: a threshold counter where a rejected share resets the
//     progress to zero and reaching the threshold completes the unseal.
//     Scalar state is threaded through RETURNS (v0.62.2 drops `&mut Int`
//     writes).
//
// Limits (rejected with errors, never a crash): secret 1..1024 bytes, shares
// 2..255, threshold 2..shares, coefficient count exactly
// (threshold - 1) * secret length.
//
// v0.62.2 notes: free functions only; Ok/Err only in the `_ok_*`/`_err_*`
// leaves; every Vec[UInt8] element read widened with `(x as Int) & 0xFF`;
// division is integer division (GF(256) values are never negative); loops are
// bounded by the size caps.

module xiom.vault.unseal

use xiom.vault.core;
use xiom.string;
use xiom.string.builder;
use xiom.encoding.hex;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// The AES reduction polynomial 0x11B (283) used by GF(256).
pub const VAULT_GF_POLY: Int = 283;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// Unseal progress: how many accepted shares the current attempt has.
pub type VaultUnseal = {
  threshold: Int;
  progress: Int;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _ok_unseal(v: VaultUnseal) -> Result[VaultUnseal, Str] {
  return Ok(v);
}

fn _err_unseal(m: Str) -> Result[VaultUnseal, Str] {
  return Err(m);
}

// --------------------------------------------------
//  GF(256) arithmetic
// --------------------------------------------------

// Carry-less product modulo 0x11B; callers pass values in 0..255.
fn _gf_mul(a: Int, b: Int) -> Int {
  var r = 0;
  var x = a;
  var y = b;
  var i = 0;
  while i < 8 {
    if (y & 1) == 1 {
      r = r ^ x;
    }
    y = y / 2;
    x = x * 2;
    if x >= 256 {
      x = x ^ VAULT_GF_POLY;
    }
    i = i + 1;
  }
  return r;
}

// Multiplicative inverse in GF(256) by exhaustive search; 0 for zero.
fn _gf_inv(a: Int) -> Int {
  var i = 1;
  while i < 256 {
    if _gf_mul(a, i) == 1 {
      return i;
    }
    i = i + 1;
  }
  return 0;
}

// Division in GF(256); callers guarantee b != 0.
fn _gf_div(a: Int, b: Int) -> Int {
  return _gf_mul(a, _gf_inv(b));
}

/// GF(256) product of two bytes (0..255) modulo 0x11B.
/// Params: a, b - byte values in 0..255.
/// Returns: Ok(product in 0..255).
/// Error case: Err("vault: gf byte out of range: N") for negative or
/// greater-than-255 inputs.
/// Complexity: O(8).
pub fn vault_gf_mul(a: Int, b: Int) -> Result[Int, Str] {
  if a < 0 || a > 255 {
    return _err_int(core.vault_err("gf byte out of range: " + core.vault_int_str(a)));
  }
  if b < 0 || b > 255 {
    return _err_int(core.vault_err("gf byte out of range: " + core.vault_int_str(b)));
  }
  return _ok_int(_gf_mul(a, b));
}

/// Multiplicative inverse in GF(256): x with a * x == 1.
/// Params: a - a byte value in 0..255 (0 has no inverse).
/// Returns: Ok(inverse in 1..255).
/// Error case: Err("vault: gf has no inverse for zero") or
/// Err("vault: gf byte out of range: N").
/// Complexity: O(256 * 8).
pub fn vault_gf_inv(a: Int) -> Result[Int, Str] {
  if a < 0 || a > 255 {
    return _err_int(core.vault_err("gf byte out of range: " + core.vault_int_str(a)));
  }
  if a == 0 {
    return _err_int(core.vault_err("gf has no inverse for zero"));
  }
  return _ok_int(_gf_inv(a));
}

/// Bytes per share for a secret of `secret_len` bytes: one x coordinate byte
/// plus the secret length. 0 when the length is outside 1..1024.
/// Params: secret_len - the secret length in bytes. Returns: the share size.
/// Error case: none. Complexity: O(1).
pub fn vault_shamir_share_len(secret_len: Int) -> Int {
  if secret_len < 1 || secret_len > core.VAULT_MAX_SECRET {
    return 0;
  }
  return secret_len + 1;
}

// --------------------------------------------------
//  Shamir split / combine
// --------------------------------------------------

// Validate the sizes shared by both split entry points; returns the number of
// coefficients required by the threshold.
fn _split_sizes(secret_len: Int, shares: Int, threshold: Int) -> Result[Int, Str] {
  if secret_len < 1 || secret_len > core.VAULT_MAX_SECRET {
    return _err_int(core.vault_err("shamir secret length out of range: " + core.vault_int_str(secret_len)));
  }
  if shares < 2 || shares > core.VAULT_MAX_SHARES {
    return _err_int(core.vault_err("shamir share count out of range: " + core.vault_int_str(shares)));
  }
  if threshold < 2 || threshold > shares {
    return _err_int(core.vault_err("shamir threshold out of range: " + core.vault_int_str(threshold)));
  }
  return _ok_int((threshold - 1) * secret_len);
}

/// Split a secret with explicitly supplied polynomial coefficients (one row
/// of `secret_len` bytes per degree 1..threshold-1, in degree-then-byte
/// order). Deterministic: identical inputs always produce identical shares.
/// Params: secret - 1..1024 bytes; shares - 2..255; threshold - 2..shares;
/// coeffs - exactly (threshold - 1) * secret.len() bytes.
/// Returns: Ok(flat share bytes): share i is
/// [x = i + 1, f(x) for each secret byte], shares * (secret.len() + 1) bytes
/// in total in share order.
/// Error case: Err("vault: shamir secret length out of range: N"),
/// Err("vault: shamir share count out of range: N"),
/// Err("vault: shamir threshold out of range: N"),
/// Err("vault: shamir coefficient count mismatch: N (want M)").
/// Complexity: O(shares * threshold * secret_len).
pub fn vault_shamir_split_with_coeffs(secret: &Vec[UInt8], shares: Int, threshold: Int, coeffs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let slen = secret.len();
  let sr = _split_sizes(slen, shares, threshold);
  if !sr.is_ok {
    return _err_bytes(sr.error);
  }
  let need: Int = sr.value;
  if coeffs.len() != need {
    return _err_bytes(core.vault_err("shamir coefficient count mismatch: " + core.vault_int_str(coeffs.len()) + " (want " + core.vault_int_str(need) + ")"));
  }
  var out = Vec[UInt8].new();
  var x = 1;
  while x <= shares {
    out.push(x as UInt8);
    var j = 0;
    while j < slen {
      let sbyte: Int = (secret[j] as Int) & 0xFF;
      var yv: Int = sbyte;
      var xp = x;
      var c = 1;
      while c < threshold {
        let cv: Int = (coeffs[(c - 1) * slen + j] as Int) & 0xFF;
        yv = yv ^ _gf_mul(cv, xp);
        xp = _gf_mul(xp, x);
        c = c + 1;
      }
      out.push(yv as UInt8);
      j = j + 1;
    }
    x = x + 1;
  }
  return _ok_bytes(out);
}

// Deterministic xorshift-style stream step over 63-bit non-negative state.
fn _rng_next(s: Int) -> Int {
  let mask = 9223372036854775807;
  var x = s;
  x = (x ^ ((x * 8192) & mask)) & mask;
  x = (x ^ (x / 128)) & mask;
  x = (x ^ ((x * 131072) & mask)) & mask;
  return x;
}

/// Split a secret with coefficients derived deterministically from `seed`
/// (xorshift-style stream, one byte per coefficient). Same inputs -> same
/// shares, for reproducible tests.
/// Params: secret - 1..1024 bytes; shares - 2..255; threshold - 2..shares;
/// seed - any Int (non-positive seeds use a fixed default).
/// Returns: Ok(flat share bytes) in the vault_shamir_split_with_coeffs
/// layout. Error case: the vault_shamir_split_with_coeffs catalog.
/// Complexity: O(shares * threshold * secret_len).
pub fn vault_shamir_split(secret: &Vec[UInt8], shares: Int, threshold: Int, seed: Int) -> Result[Vec[UInt8], Str] {
  let slen = secret.len();
  let sr = _split_sizes(slen, shares, threshold);
  if !sr.is_ok {
    return _err_bytes(sr.error);
  }
  let need: Int = sr.value;
  var state = seed;
  if state <= 0 {
    state = 88172645463325252;
  }
  var coeffs = Vec[UInt8].new();
  while coeffs.len() < need {
    state = _rng_next(state);
    coeffs.push(((state / 8192) % 256) as UInt8);
  }
  return vault_shamir_split_with_coeffs(secret, shares, threshold, &coeffs);
}

/// Reconstruct a secret from share bytes produced by the split helpers
/// (Lagrange interpolation at x = 0). Shares may be given in any order; at
/// least two distinct non-zero coordinates are required.
/// Params: shares - flat share bytes, length must be a multiple of
/// secret_len + 1; secret_len - the original secret length (1..1024).
/// Returns: Ok(reconstructed secret bytes).
/// Error case: Err("vault: shamir secret length out of range: N"),
/// Err("vault: shamir share data length mismatch: N"),
/// Err("vault: shamir needs at least two shares"),
/// Err("vault: shamir has too many shares"),
/// Err("vault: shamir share x coordinate is zero at share N"),
/// Err("vault: shamir duplicate share x coordinate at share N").
/// Complexity: O(k^2 * secret_len) for k shares.
pub fn vault_shamir_combine(shares: &Vec[UInt8], secret_len: Int) -> Result[Vec[UInt8], Str] {
  if secret_len < 1 || secret_len > core.VAULT_MAX_SECRET {
    return _err_bytes(core.vault_err("shamir secret length out of range: " + core.vault_int_str(secret_len)));
  }
  let share_len = secret_len + 1;
  let total = shares.len();
  if total == 0 || total % share_len != 0 {
    return _err_bytes(core.vault_err("shamir share data length mismatch: " + core.vault_int_str(total)));
  }
  let k = total / share_len;
  if k < 2 {
    return _err_bytes(core.vault_err("shamir needs at least two shares"));
  }
  if k > core.VAULT_MAX_SHARES {
    return _err_bytes(core.vault_err("shamir has too many shares"));
  }
  var xs = Vec[Int].new();
  var i = 0;
  while i < k {
    let x: Int = (shares[i * share_len] as Int) & 0xFF;
    if x == 0 {
      return _err_bytes(core.vault_err("shamir share x coordinate is zero at share " + core.vault_int_str(i)));
    }
    var j = 0;
    while j < xs.len() {
      let xj: Int = xs[j];
      if xj == x {
        return _err_bytes(core.vault_err("shamir duplicate share x coordinate at share " + core.vault_int_str(i)));
      }
      j = j + 1;
    }
    xs.push(x);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  var b = 0;
  while b < secret_len {
    var acc = 0;
    var a = 0;
    while a < k {
      let xi: Int = xs[a];
      var num = 1;
      var den = 1;
      var m = 0;
      while m < k {
        if m != a {
          let xm: Int = xs[m];
          num = _gf_mul(num, xm);
          den = _gf_mul(den, xm ^ xi);
        }
        m = m + 1;
      }
      let li = _gf_div(num, den);
      let yv: Int = (shares[a * share_len + 1 + b] as Int) & 0xFF;
      acc = acc ^ _gf_mul(yv, li);
      a = a + 1;
    }
    out.push(acc as UInt8);
    b = b + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Hex rendering (secrets stay byte-oriented; hex is for display)
// --------------------------------------------------

/// Lowercase hex rendering of share/secret bytes.
/// Params: data - the bytes. Returns: the hex text.
/// Error case: none. Complexity: O(data.len()).
pub fn vault_shamir_to_hex(data: &Vec[UInt8]) -> Str {
  return hex.hex_encode(data);
}

/// Decode lowercase/uppercase hex into bytes.
/// Params: s - the hex text (even length).
/// Returns: Ok(bytes).
/// Error case: Err("vault: shamir invalid hex") for odd length or non-hex
/// characters.
/// Complexity: O(s.len()).
pub fn vault_shamir_from_hex(s: Str) -> Result[Vec[UInt8], Str] {
  let r = hex.hex_decode(s);
  if !r.is_ok {
    return _err_bytes("vault: shamir invalid hex");
  }
  let v: Vec[UInt8] = r.value;
  return _ok_bytes(v);
}

// --------------------------------------------------
//  Unseal progress
// --------------------------------------------------

/// Start an unseal attempt with the given share threshold (1..255).
/// Params: threshold - the number of accepted shares needed.
/// Returns: Ok(progress at zero).
/// Error case: Err("vault: unseal threshold out of range: N").
/// Complexity: O(1).
pub fn vault_unseal_new(threshold: Int) -> Result[VaultUnseal, Str] {
  if threshold < 1 || threshold > core.VAULT_MAX_SHARES {
    return _err_unseal(core.vault_err("unseal threshold out of range: " + core.vault_int_str(threshold)));
  }
  return _ok_unseal(VaultUnseal{ threshold: threshold; progress: 0 });
}

/// Submit one share result: an accepted share advances the progress, a
/// rejected share resets it to zero, and a completed attempt stays complete.
/// Params: u - the current progress; share_ok - whether the share was valid.
/// Returns: the next progress (never mutates u).
/// Error case: none. Complexity: O(1).
pub fn vault_unseal_submit(u: &VaultUnseal, share_ok: Bool) -> VaultUnseal {
  if u.progress >= u.threshold {
    return VaultUnseal{ threshold: u.threshold; progress: u.progress };
  }
  if share_ok {
    return VaultUnseal{ threshold: u.threshold; progress: u.progress + 1 };
  }
  return VaultUnseal{ threshold: u.threshold; progress: 0 };
}

/// True when the unseal attempt reached its threshold.
/// Params: u - the progress. Returns: the predicate.
/// Error case: none. Complexity: O(1).
pub fn vault_unseal_complete(u: &VaultUnseal) -> Bool {
  if u.progress >= u.threshold {
    return true;
  }
  return false;
}

/// Accepted shares still needed to complete the unseal.
/// Params: u - the progress. Returns: the remaining count (>= 0).
/// Error case: none. Complexity: O(1).
pub fn vault_unseal_remaining(u: &VaultUnseal) -> Int {
  if u.progress >= u.threshold {
    return 0;
  }
  return u.threshold - u.progress;
}

/// Reset an unseal attempt to zero progress.
/// Params: u - the progress. Returns: progress at zero.
/// Error case: none. Complexity: O(1).
pub fn vault_unseal_reset(u: &VaultUnseal) -> VaultUnseal {
  return VaultUnseal{ threshold: u.threshold; progress: 0 };
}
