// XIOM -- xiom.fuzz: deterministic byte and string mutation for fuzzing
// Port task: replace the xiom.fuzz placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic, dependency-free mutation operators over byte buffers and
// strings: a seeded 31-bit generator and five single-step mutators
// (flip_byte, flip_bit, insert_byte, delete_byte, duplicate_range) plus a
// multi-step driver (fuzz_mutate) and a Str wrapper (fuzz_mutate_str).
// Every result is a pure function of (input, seed, mutations): the same
// arguments always yield the same bytes, on every run and platform, so any
// mutated sample is replayable from its seed. There is no clock, environment,
// file or OS randomness source anywhere in this module.
//
// Free functions only (XIOM v0.61.x has no methods). The module returns plain
// Vec[UInt8]/Str values -- no Result channels -- so Ok/Err construction bugs
// cannot arise. Mutators never modify their input; they return a fresh Vec.
// Str mutation is BYTE-LEVEL: bytes -> mutate -> Str, with no UTF-8
// validation, so the result of fuzz_mutate_str may hold non-UTF-8 byte
// sequences when the input is not ASCII-safe under the chosen operation.
//
// PRNG: a 31-bit xorshift-style mixer over the FuzzRng.state field, the
// recipe pinned in xiom.property (deterministic test-grade scramble, not a
// cryptographic generator). Each single-step mutator derives all of its
// choices (positions, masks, lengths, destinations) from that one stream; the
// exact derivation per operation is pinned in SPEC.md and covered by the
// conformance suite.

module xiom.fuzz

use xiom.string;
use xiom.string.builder;

/// Deterministic pseudo-random generator state.
///
/// Construct through `fuzz_rng_new`; advance by passing `&mut r` to
/// `fuzz_next`. `state` is kept in [1, 2^31 - 1] by construction, so a stream
/// can never collapse into the all-zero fixed point.
pub type FuzzRng = {
  state: Int;
}

// Deterministic spread: multiply-xor-shift mix of `v`, result in
// [0, 2^31 - 1]. The left shift operates on non-negative values only (the
// 0x00FFFFFFFFFFFFFF mask clears the sign first), so the result is fully
// defined for every Int input, including negatives.
fn _fuzz_mix(v: Int) -> Int {
  var h = v;
  h = h ^ (h >> 13);
  h = h & 0x00FFFFFFFFFFFFFF;
  h = h ^ (h << 7);
  h = h ^ (h >> 17);
  h = h & 0x7FFFFFFF;
  return h;
}

/// Create a generator from a seed.
/// Params: seed - any Int (negative, zero and huge values are accepted).
/// Returns: fresh FuzzRng with nonzero state in [1, 2^31 - 1].
/// Error case: none.
/// Complexity: O(1).
pub fn fuzz_rng_new(seed: Int) -> FuzzRng {
  var state = _fuzz_mix(seed);
  if state == 0 { state = 0x1F123BB5; }
  return FuzzRng{ state: state; };
}

/// Advance the generator and return the next draw.
/// Params: r - the mutable generator state.
/// Returns: a value in [0, 2^31 - 1] (always non-negative; seed sign is
/// irrelevant). Same state always yields the same draw.
/// Error case: none.
/// Complexity: O(1).
pub fn fuzz_next(r: &mut FuzzRng) -> Int {
  var h = r.state;
  h = h ^ (h >> 13);
  h = h ^ (h << 7);
  h = h ^ (h >> 17);
  h = h & 0x7FFFFFFF;
  if h == 0 { h = 0x1F123BB5; }
  r.state = h;
  return h;
}

// Deterministic per-step seed derivation used by fuzz_mutate: mix(base +
// index * odd-multiplier), so consecutive steps get spread-apart seeds and
// the same (base, index) pair always yields the same seed. Result in
// [0, 2^31 - 1]. The odd multiplier is the golden-ratio constant
// 2654435761 (Knuth).
fn _fuzz_seed_at(base: Int, index: Int) -> Int {
  return _fuzz_mix(base + index * 2654435761);
}

// Fresh copy of `data`; mutators never alias their input.
fn _fuzz_copy(data: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

/// Flip one byte with a non-zero XOR mask.
/// Params: data - input bytes; seed - determines position and mask.
/// Returns: a fresh Vec of the SAME length as `data` in which exactly one
/// byte is XORed with a mask in [1, 255] (so the byte value always changes).
/// An empty input yields an empty Vec.
/// Error case: none.
/// Complexity: O(|data|).
pub fn fuzz_flip_byte(data: &Vec[UInt8], seed: Int) -> Vec[UInt8] {
  var out = _fuzz_copy(data);
  let n = out.len();
  if n == 0 { return out; }
  var r = fuzz_rng_new(seed);
  let pos = fuzz_next(&mut r) % n;
  let mask = (fuzz_next(&mut r) % 255) + 1;
  let cur = out[pos] as Int;
  out[pos] = (cur ^ mask) as UInt8;
  return out;
}

/// Toggle exactly one bit.
/// Params: data - input bytes; seed - determines position and bit index.
/// Returns: a fresh Vec of the same length as `data` in which exactly one
/// bit (of one byte) is toggled. An empty input yields an empty Vec.
/// Error case: none.
/// Complexity: O(|data|).
pub fn fuzz_flip_bit(data: &Vec[UInt8], seed: Int) -> Vec[UInt8] {
  var out = _fuzz_copy(data);
  let n = out.len();
  if n == 0 { return out; }
  var r = fuzz_rng_new(seed);
  let pos = fuzz_next(&mut r) % n;
  let bit = fuzz_next(&mut r) % 8;
  let mask = 1 << bit;
  let cur = out[pos] as Int;
  out[pos] = (cur ^ mask) as UInt8;
  return out;
}

/// Insert one byte at a derived position.
/// Params: data - input bytes; seed - determines position and byte value.
/// Returns: a fresh Vec of length |data| + 1; the inserted byte is placed at
/// position `fuzz_next(seed) % (|data| + 1)` (0..=|data|) and the original
/// bytes keep their relative order. Empty input yields a 1-byte Vec.
/// Error case: none.
/// Complexity: O(|data|).
pub fn fuzz_insert_byte(data: &Vec[UInt8], seed: Int) -> Vec[UInt8] {
  let n = data.len();
  var r = fuzz_rng_new(seed);
  let pos = fuzz_next(&mut r) % (n + 1);
  let value = fuzz_next(&mut r) % 256;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    if i == pos {
      out.push(value as UInt8);
    }
    out.push(data[i]);
    i = i + 1;
  }
  if pos == n {
    out.push(value as UInt8);
  }
  return out;
}

/// Delete one byte at a derived position.
/// Params: data - input bytes; seed - determines the position.
/// Returns: a fresh Vec of length |data| - 1 with the byte at
/// `fuzz_next(seed) % |data|` removed. An empty input yields an empty Vec.
/// Error case: none.
/// Complexity: O(|data|).
pub fn fuzz_delete_byte(data: &Vec[UInt8], seed: Int) -> Vec[UInt8] {
  let n = data.len();
  var out = Vec[UInt8].new();
  if n == 0 { return out; }
  var r = fuzz_rng_new(seed);
  let pos = fuzz_next(&mut r) % n;
  var i = 0;
  while i < n {
    if i != pos {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

/// Duplicate a derived non-empty subrange.
/// Params: data - input bytes; seed - determines start, length and destination.
/// Returns: a fresh Vec of length |data| + len with a copy of
/// `data[start .. start + len]` inserted at position
/// `dest = fuzz_next(seed) % (|data| + 1)`; `start = fuzz_next(seed) % |data|`
/// and `len = 1 + fuzz_next(seed) % (|data| - start)`, so `len >= 1` and the
/// subrange is in bounds. The original bytes keep their relative order. An
/// empty input yields an empty Vec.
/// Error case: none.
/// Complexity: O(|data|).
pub fn fuzz_duplicate_range(data: &Vec[UInt8], seed: Int) -> Vec[UInt8] {
  let n = data.len();
  var out = Vec[UInt8].new();
  if n == 0 { return out; }
  var r = fuzz_rng_new(seed);
  let start = fuzz_next(&mut r) % n;
  let span = n - start;
  let len = 1 + (fuzz_next(&mut r) % span);
  let dest = fuzz_next(&mut r) % (n + 1);
  var i = 0;
  while i < n {
    if i == dest {
      var k = 0;
      while k < len {
        out.push(data[start + k]);
        k = k + 1;
      }
    }
    out.push(data[i]);
    i = i + 1;
  }
  if dest == n {
    var m = 0;
    while m < len {
      out.push(data[start + m]);
      m = m + 1;
    }
  }
  return out;
}

/// Apply `mutations` deterministic mutation steps.
/// Params: data - input bytes; seed - base seed; mutations - number of steps.
/// For step i (0-based): the operation is chosen as
/// `op = fuzz_next(r) % 5` from a generator `r = fuzz_rng_new(seed)` that
/// advances once per step, and the step seed is `_fuzz_seed_at(seed, i)`
/// (mix of `seed + i * 2654435761`). Op 0/1/2/3/4 maps to flip_byte,
/// flip_bit, insert_byte, delete_byte, duplicate_range respectively.
/// Returns: the accumulated bytes. `mutations <= 0` returns an unchanged copy
/// of `data`. Same (data, seed, mutations) always yields the same Vec.
/// Error case: none.
/// Complexity: O(mutations * |data|).
pub fn fuzz_mutate(data: &Vec[UInt8], seed: Int, mutations: Int) -> Vec[UInt8] {
  var out = _fuzz_copy(data);
  if mutations <= 0 { return out; }
  var r = fuzz_rng_new(seed);
  var i = 0;
  while i < mutations {
    let step_seed = _fuzz_seed_at(seed, i);
    let op = fuzz_next(&mut r) % 5;
    if op == 0 {
      out = fuzz_flip_byte(&out, step_seed);
    } elif op == 1 {
      out = fuzz_flip_bit(&out, step_seed);
    } elif op == 2 {
      out = fuzz_insert_byte(&out, step_seed);
    } elif op == 3 {
      out = fuzz_delete_byte(&out, step_seed);
    } else {
      out = fuzz_duplicate_range(&out, step_seed);
    }
    i = i + 1;
  }
  return out;
}

/// Mutate the BYTES of a string.
/// Params: s - input string; seed - base seed; mutations - number of steps.
/// Returns: `fuzz_mutate` over the UTF-8 bytes of `s`, materialized back into
/// a Str with the xiom.string builder. The transformation is byte-level: the
/// result may NOT be valid UTF-8 (a mutated lead or continuation byte can
/// produce an invalid sequence), and it is not validated or repaired. For
/// ASCII input the byte-level round-trip is exact; the conformance suite
/// pins that invariant. `mutations <= 0` returns `s` unchanged byte-for-byte.
/// Error case: none.
/// Complexity: O(|s| + mutations * |s|).
pub fn fuzz_mutate_str(s: Str, seed: Int, mutations: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    bytes.push(string.byte_at(s, i));
    i = i + 1;
  }
  let mutated = fuzz_mutate(&bytes, seed, mutations);
  return builder.sb_to_str(&mutated);
}
