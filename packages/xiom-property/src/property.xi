// XIOM -- xiom.property: deterministic property-based testing
// Port task: replace the xiom.property placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Seeds, generators, runners and shrinking for property-based testing. The
// engine is fully deterministic: a seed plus a generation rule reproduce the
// exact same value on every run, so a failing property is always replayable
// from its recorded seed. There is no clock, environment or OS randomness
// source anywhere in this module.
//
// Free functions only (XIOM v0.61.x has no methods), and every callback is a
// NAMED top-level function with an explicit `fn(&Int) -> Bool` / `fn(&Str) ->
// Bool` signature: the compiler's function-pointer codegen rejects inline
// lambdas. Concrete monomorphic signatures only (no generics in callbacks).
//
// PRNG: a 31-bit xorshift-style mixer over the `state: Int` field. Every
// operation stays on non-negative values and the result is masked below 2^31,
// so `prop_rng_next` is always >= 0 regardless of the sign of the seed. The
// exact bit recipe is pinned in SPEC.md and covered by the conformance suite.

module xiom.property

use xiom.string;

/// Deterministic pseudo-random generator state.
///
/// Construct through `prop_rng_new`; advance by passing `&mut r` to the
/// generators below. `state` is kept in [1, 2^31 - 1] by construction, so a
/// stream can never collapse into the all-zero fixed point.
pub type Rng = {
  state: Int;
}

/// Outcome of one property run over a seed vector.
///
/// `passed` counts the seeds that were executed before the run stopped;
/// `failed` is 1 when the property failed and 0 otherwise. `first_seed` and
/// `first_value` identify the first counterexample: for the Int runners it is
/// the drawn Int, for `prop_run_str` it is the BYTE LENGTH of the drawn Str
/// (the report has no Str channel). Both are 0 when the run is green.
pub type PropReport = {
  passed: Int;
  failed: Int;
  first_seed: Int;
  first_value: Int;
}

// Deterministic spread: multiply-xor-shift mix of `v`, result in
// [0, 2^31 - 1]. The left shift operates on non-negative values only, so the
// result is fully defined for every Int input, including negatives.
fn _prop_mix(v: Int) -> Int {
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
/// Returns: fresh Rng with nonzero state in [1, 2^31 - 1].
/// Error case: none.
/// Complexity: O(1).
pub fn prop_rng_new(seed: Int) -> Rng {
  var state = _prop_mix(seed);
  if state == 0 { state = 0x1F123BB5; }
  return Rng{ state: state; };
}

/// Advance the generator and return the next draw.
/// Params: r - the mutable generator state.
/// Returns: a value in [0, 2^31 - 1] (always non-negative; seed sign is
/// irrelevant). Same state always yields the same draw.
/// Error case: none.
/// Complexity: O(1).
pub fn prop_rng_next(r: &mut Rng) -> Int {
  var h = r.state;
  h = h ^ (h >> 13);
  h = h ^ (h << 7);
  h = h ^ (h >> 17);
  h = h & 0x7FFFFFFF;
  if h == 0 { h = 0x1F123BB5; }
  r.state = h;
  return h;
}

/// Draw a boolean (one bit from the mixed stream).
/// Params: r - the mutable generator state.
/// Returns: true or false, roughly balanced for typical seeds.
/// Error case: none.
/// Complexity: O(1).
pub fn prop_rng_bool(r: &mut Rng) -> Bool {
  let v = prop_rng_next(r);
  return v % 2 == 0;
}

/// Draw an Int uniformly from the inclusive range [lo, hi].
/// Params: r - the mutable generator state; lo, hi - inclusive bounds.
/// Returns: lo + (next(r) mod (hi - lo + 1)); when hi < lo the function
/// returns lo and does NOT consume a draw. Precondition (documented): hi - lo
/// + 1 must fit in an Int.
/// Error case: none.
/// Complexity: O(1).
pub fn prop_rng_range(r: &mut Rng, lo: Int, hi: Int) -> Int {
  if hi < lo { return lo; }
  let span = hi - lo + 1;
  let v = prop_rng_next(r);
  return lo + (v % span);
}

/// Draw a string of at most `len` characters, each taken from `alphabet`.
/// Params: r - the mutable generator state; len - upper bound on the number of
/// characters (<= 0 yields ""); alphabet - the source characters (valid UTF-8;
/// the empty alphabet yields "").
/// Returns: "" when len <= 0 or the alphabet is empty; otherwise a string with
/// a random character count in [0, len] (drawn with prop_rng_range), each
/// character a uniformly chosen alphabet character, concatenated in draw
/// order. The alphabet is scanned once at real UTF-8 boundaries, so multi-byte
/// characters are copied whole and never split.
/// Error case: none.
/// Complexity: O(|alphabet| + result length).
pub fn prop_rng_string(r: &mut Rng, len: Int, alphabet: Str) -> Str {
  if len <= 0 { return ""; }
  let alen = alphabet.len();
  if alen == 0 { return ""; }
  var starts = Vec[Int].new();
  var widths = Vec[Int].new();
  var i = 0;
  while i < alen {
    let lead = string.byte_at(alphabet, i) as Int;
    var width = 1;
    if lead >= 0xC0 && lead <= 0xDF {
      width = 2;
    } elif lead >= 0xE0 && lead <= 0xEF {
      width = 3;
    } elif lead >= 0xF0 {
      width = 4;
    }
    if i + width > alen { width = alen - i; }
    starts.push(i);
    widths.push(width);
    i = i + width;
  }
  let chars = starts.len();
  let count = prop_rng_range(r, 0, len);
  var out = Vec[UInt8].new();
  var k = 0;
  while k < count {
    let pick = prop_rng_range(r, 0, chars - 1);
    let start: Int = starts[pick];
    let width: Int = widths[pick];
    var j = 0;
    while j < width {
      out.push(string.byte_at(alphabet, start + j));
      j = j + 1;
    }
    k = k + 1;
  }
  return Str::from_utf8(out);
}

// Deterministic seed derivation: mix(base + index * odd-multiplier), so
// consecutive indices are spread far apart and the same (base, index) pair
// always yields the same seed. Result in [0, 2^31 - 1].
fn _prop_seed_at(base: Int, index: Int) -> Int {
  var h = base + index * 2654435761;
  h = h ^ (h >> 13);
  h = h & 0x00FFFFFFFFFFFFFF;
  h = h ^ (h << 7);
  h = h ^ (h >> 17);
  h = h & 0x7FFFFFFF;
  return h;
}

/// Derive `count` deterministic seeds from a base value.
/// Params: count - how many seeds to derive (<= 0 yields an empty vector);
/// base - caller-chosen origin; the same (count, base) pair always yields the
/// same vector.
/// Returns: a Vec[Int] of length max(count, 0) with non-negative entries that
/// look unrelated for nearby indices (they are not guaranteed to be pairwise
/// distinct for arbitrary inputs).
/// Error case: none.
/// Complexity: O(count).
pub fn prop_seeds(count: Int, base: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < count {
    out.push(_prop_seed_at(base, i));
    i = i + 1;
  }
  return out;
}

/// Run an Int property over a seed vector.
/// Params: f - named predicate callback; seeds - the seeds to try.
/// For each seed (in order): create a generator, draw a value in
/// [-1000, 1000] and call f on it. On the first failure the run stops
/// immediately.
/// Returns: PropReport with passed = number of seeds that passed before the
/// stop, failed = 1 and (first_seed, first_value) set to the counterexample;
/// on full success passed = seeds.len(), failed = 0, first_seed = first_value
/// = 0.
/// Error case: none.
/// Complexity: O(seeds * cost of f).
pub fn prop_run_int(f: fn(&Int) -> Bool, seeds: &Vec[Int]) -> PropReport {
  var pass_count = 0;
  var fail_count = 0;
  var fail_seed = 0;
  var fail_value = 0;
  var i = 0;
  while i < seeds.len() {
    let seed: Int = seeds[i];
    var rng = prop_rng_new(seed);
    let value = prop_rng_range(&mut rng, -1000, 1000);
    if f(&value) {
      pass_count = pass_count + 1;
    } else {
      fail_count = 1;
      fail_seed = seed;
      fail_value = value;
      break;
    }
    i = i + 1;
  }
  return PropReport{ passed: pass_count; failed: fail_count; first_seed: fail_seed; first_value: fail_value; };
}

/// Run an Int property over a seed vector with explicit bounds.
/// Params: f - named predicate callback; seeds - the seeds to try; lo, hi -
/// inclusive draw bounds (hi < lo makes every draw lo).
/// Returns: PropReport exactly like prop_run_int; a failing run records the
/// first counterexample draw as first_value.
/// Error case: none.
/// Complexity: O(seeds * cost of f).
pub fn prop_run_range(f: fn(&Int) -> Bool, seeds: &Vec[Int], lo: Int, hi: Int) -> PropReport {
  var pass_count = 0;
  var fail_count = 0;
  var fail_seed = 0;
  var fail_value = 0;
  var i = 0;
  while i < seeds.len() {
    let seed: Int = seeds[i];
    var rng = prop_rng_new(seed);
    let value = prop_rng_range(&mut rng, lo, hi);
    if f(&value) {
      pass_count = pass_count + 1;
    } else {
      fail_count = 1;
      fail_seed = seed;
      fail_value = value;
      break;
    }
    i = i + 1;
  }
  return PropReport{ passed: pass_count; failed: fail_count; first_seed: fail_seed; first_value: fail_value; };
}

/// Run a Str property over a seed vector.
/// Params: f - named predicate callback; seeds - the seeds to try; max_len -
/// upper bound on the generated string length in characters; alphabet - the
/// character source.
/// Returns: PropReport like prop_run_int, with one documented difference: a
/// Str cannot travel through the Int `first_value` field, so a failing run
/// records the BYTE LENGTH of the first counterexample string instead. The
/// counterexample itself is reproducible: rebuild it with
/// prop_rng_new(first_seed) and prop_rng_string.
/// Error case: none.
/// Complexity: O(seeds * cost of f).
pub fn prop_run_str(f: fn(&Str) -> Bool, seeds: &Vec[Int], max_len: Int, alphabet: Str) -> PropReport {
  var pass_count = 0;
  var fail_count = 0;
  var fail_seed = 0;
  var fail_value = 0;
  var i = 0;
  while i < seeds.len() {
    let seed: Int = seeds[i];
    var rng = prop_rng_new(seed);
    let value = prop_rng_string(&mut rng, max_len, alphabet);
    if f(&value) {
      pass_count = pass_count + 1;
    } else {
      fail_count = 1;
      fail_seed = seed;
      fail_value = value.len();
      break;
    }
    i = i + 1;
  }
  return PropReport{ passed: pass_count; failed: fail_count; first_seed: fail_seed; first_value: fail_value; };
}

/// True when the run recorded no failure. Complexity: O(1).
pub fn prop_report_ok(r: &PropReport) -> Bool {
  return r.failed == 0;
}

/// Shrink a failing Int counterexample toward zero by repeated halving.
/// Params: value - the failing input to start from; f - the same predicate the
/// runner used.
/// Returns: value unchanged when f(value) is true (nothing to shrink). When
/// f(value) is false, walks the chain value, value/2, value/4, ... (Int
/// division truncates toward zero) and keeps the LAST chain element that is
/// still false, stopping when the next candidate is 0 or f(candidate) becomes
/// true. That element has the smallest magnitude in the chain for which the
/// property still fails.
/// Error case: none.
/// Complexity: O(log |value| * cost of f).
pub fn prop_shrink_int(value: Int, f: fn(&Int) -> Bool) -> Int {
  var current = value;
  if !f(&current) {
    loop {
      let candidate = current / 2;
      if candidate == 0 { break; }
      if f(&candidate) { break; }
      current = candidate;
    }
  }
  return current;
}
