// XIOM -- xiom.optimizer: deterministic single-variable integer optimizers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Grid search, hill climbing with step halving, random-restart hill
// climbing, and simulated annealing over ONE integer variable. Pure engine:
// no I/O, no clock, no environment, no threads, no global state.
//
// Free functions only (XIOM v0.61.x has no methods) and every objective is a
// NAMED top-level `fn(&Int) -> Int` callback passed as a function pointer --
// the compiler's function-pointer codegen rejects inline lambdas, so callers
// must declare their objective at module scope (same convention as
// xiom.property and xiom.option). Strictly larger scores are better; every
// function maximizes.
//
// Randomness: a local xorshift-style PRNG carried in a plain `var rng: Int`.
// `_opt_rng_next(state)` returns the NEXT state, and callers use the
// returned state itself as the draw (post-advance output). There are no
// references, no structs and no `&mut` parameters anywhere in this module:
// the v0.61.3 `&mut Int` calling convention miscompiles simple write-through
// updates, so the engine avoids it entirely. The PRNG is deterministic, not
// cryptographic: the same seed reproduces the same run on a platform.
//
// All algorithms are total. Degenerate inputs (empty ranges, non-positive
// counts, non-positive steps) return a documented sentinel instead of
// failing; none of the functions panic.

module xiom.optimizer

/// Iteration budget for each restart climb in opt_random_restart_int.
const _OPT_RESTART_MAX_STEPS: Int = 64;

// Absolute value of v. Like every Int operation in this module it wraps on
// the extreme Int min value instead of trapping.
fn _opt_abs(v: Int) -> Int {
  if v < 0 { return 0 - v; }
  return v;
}

// Clamp x into [lo, hi]. Callers must pass lo <= hi.
fn _opt_clamp(x: Int, lo: Int, hi: Int) -> Int {
  if x < lo { return lo; }
  if x > hi { return hi; }
  return x;
}

// Advance the PRNG one step. Params: state - current state (any Int; the
// seed is mixed first, and a zero state is repaired). Returns: the next
// state, in [1, 2^31 - 1], which the caller also uses as the draw.
// The shifts that run on values that may be negative are masked to 56 bits
// before the left shift, so the result is fully defined for any Int input
// and always non-negative.
fn _opt_rng_next(state: Int) -> Int {
  var h = state;
  h = h ^ (h >> 13);
  h = h & 0x00FFFFFFFFFFFFFF;
  h = h ^ (h << 7);
  h = h ^ (h >> 17);
  h = h & 0x7FFFFFFF;
  if h == 0 { h = 0x1F123BB5; }
  return h;
}

// Deterministic per-restart state: restart `index` (0-based) of a sequence
// rooted at `base`. Consecutive indices are spread far apart by the odd
// multiplier before mixing.
fn _opt_seed_at(base: Int, index: Int) -> Int {
  return _opt_rng_next(base + (index + 1) * 2654435761);
}

/// Evenly spaced integer points from `lo` to `hi`, endpoints inclusive.
/// Params: lo - first point; hi - last point; n - number of points.
/// Returns: when n >= 2 and hi >= lo, a Vec[Int] of length n with
/// out[i] = lo + ((hi - lo) * i) / (n - 1) for i in [0, n - 1]; integer
/// division truncates toward zero and hi >= lo keeps the product
/// non-negative, so the result is non-decreasing and out[n-1] == hi.
/// n == 1 yields [lo]; n < 1 or hi < lo yield an empty vector.
/// Error case: none.
/// Complexity: O(n).
pub fn opt_linspace_int(lo: Int, hi: Int, n: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if n < 1 { return out; }
  if hi < lo { return out; }
  if n == 1 {
    out.push(lo);
    return out;
  }
  var i = 0;
  while i < n {
    out.push(lo + ((hi - lo) * i) / (n - 1));
    i = i + 1;
  }
  return out;
}

/// Exhaustive grid search for the best integer point in [lo, hi].
/// Params: lo - first grid point; hi - inclusive upper bound; step - grid
/// spacing; f - named objective (strictly larger is better).
/// Returns: the point x in {lo, lo + step, lo + 2*step, ...} with x <= hi
/// that maximizes f. The scan runs upward and only a strictly larger score
/// replaces the incumbent, so ties keep the SMALLEST x.
/// step < 1 or hi < lo return lo (no scan; f is then evaluated once).
/// Error case: none.
/// Complexity: O(1 + (hi - lo) / step) calls to f.
pub fn opt_grid_best_int(lo: Int, hi: Int, step: Int, f: fn(&Int) -> Int) -> Int {
  if step < 1 { return lo; }
  if hi < lo { return lo; }
  let first = lo;
  var best_x = lo;
  var best_v = f(&first);
  var x = lo + step;
  while x <= hi {
    let v = f(&x);
    if v > best_v {
      best_v = v;
      best_x = x;
    }
    x = x + step;
  }
  return best_x;
}

/// Hill climb with adaptive step halving.
/// Params: start - initial point; step - initial step size; max_steps -
/// iteration budget; f - named objective (strictly larger is better).
/// Each iteration evaluates the current point x and the two neighbours
/// x - step and x + step, and moves to the best of the three only when it
/// scores strictly higher than the current point (ties keep x). On a stall
/// (no strict improvement) the step is halved with integer division, so a
/// step of 1 halves to 0 and terminates the loop. The loop stops when the
/// step reaches 0 or after max_steps iterations, whichever comes first.
/// Returns: the final point; start when step < 1 or max_steps < 1.
/// The score never decreases: every move is a strict improvement.
/// Error case: none.
/// Complexity: O(max_steps) calls to f (at most 3 per iteration).
pub fn opt_hill_climb_int(start: Int, step: Int, max_steps: Int, f: fn(&Int) -> Int) -> Int {
  var x = start;
  var s = step;
  var i = 0;
  while i < max_steps && s >= 1 {
    let cur = f(&x);
    var best_x = x;
    var best_v = cur;
    let left = x - s;
    let lv = f(&left);
    if lv > best_v {
      best_v = lv;
      best_x = left;
    }
    let right = x + s;
    let rv = f(&right);
    if rv > best_v {
      best_v = rv;
      best_x = right;
    }
    if best_x != x {
      x = best_x;
    } else {
      s = s / 2;
    }
    i = i + 1;
  }
  return x;
}

/// Random-restart hill climbing, fully deterministic.
/// Params: lo - inclusive lower bound for the sampled starts; hi - inclusive
/// upper bound; restarts - number of climbs; step - hill-climb step size;
/// seed - PRNG root; f - named objective (strictly larger is better).
/// Each restart draws a start x0 in [lo, hi] from the local xorshift PRNG
/// (per-restart states are mixed as _opt_seed_at(seed, index)) and then runs
/// the opt_hill_climb_int algorithm from x0 with an internal budget of
/// _OPT_RESTART_MAX_STEPS = 64 iterations. The running best is seeded with
/// f(lo) before the first climb.
/// Returns: the point with the highest score among the climbs and lo; ties
/// keep the earliest best. restarts < 1 or hi < lo return lo. Same inputs
/// always return the same point on a platform.
/// Error case: none.
/// Complexity: O(restarts * _OPT_RESTART_MAX_STEPS) calls to f.
pub fn opt_random_restart_int(lo: Int, hi: Int, restarts: Int, step: Int, seed: Int, f: fn(&Int) -> Int) -> Int {
  if hi < lo { return lo; }
  if restarts < 1 { return lo; }
  let first = lo;
  var best_x = lo;
  var best_v = f(&first);
  let span = hi - lo + 1;
  var i = 0;
  while i < restarts {
    let x0 = lo + (_opt_seed_at(seed, i) % span);
    let cand = opt_hill_climb_int(x0, step, _OPT_RESTART_MAX_STEPS, f);
    let cv = f(&cand);
    if cv > best_v {
      best_v = cv;
      best_x = cand;
    }
    i = i + 1;
  }
  return best_x;
}

/// Integer simulated annealing, fully deterministic.
/// Params: start - initial point (clamped into [lo, hi]); lo, hi - inclusive
/// bounds; steps - number of proposals; seed - PRNG root; temp_start -
/// starting temperature (clamped to >= 1); f - named objective (strictly
/// larger is better).
/// Temperature schedule: at 0-based step i of `steps` the temperature is
/// temp_i = temp_start - ((temp_start - 1) * i) / (steps - 1) when
/// steps > 1 (integer division truncates; temp_start is clamped to >= 1 and
/// every temp_i is clamped to >= 1), so it decays linearly from temp_start
/// to 1 across the steps; with steps == 1 the single step runs at
/// temp_start.
/// Proposal: delta = (rng % 17) - 8, i.e. delta in [-8, 8]; the candidate
/// x + delta is clamped into [lo, hi].
/// Acceptance: a candidate that improves f is always accepted; otherwise it
/// is accepted when rng % (temp + 1) > |f(candidate) - f(x)| -- the
/// documented integer approximation of exp(-cost / temp). The second draw
/// happens only when the candidate does not improve.
/// Returns: the best point SEEN during the walk (the walk itself may end
/// elsewhere); ties keep the earliest best. steps < 1 returns the clamped
/// start; hi < lo returns start unchanged. Same seed and inputs reproduce
/// the exact same walk on a platform.
/// Error case: none.
/// Complexity: O(steps) calls to f (at most 2 per step).
pub fn opt_anneal_int(start: Int, lo: Int, hi: Int, steps: Int, seed: Int, temp_start: Int, f: fn(&Int) -> Int) -> Int {
  if hi < lo { return start; }
  var x = _opt_clamp(start, lo, hi);
  if steps < 1 { return x; }
  var t0 = temp_start;
  if t0 < 1 { t0 = 1; }
  var best_x = x;
  var best_v = f(&x);
  var rng = _opt_rng_next(seed);
  var i = 0;
  while i < steps {
    var temp = t0;
    if steps > 1 {
      temp = t0 - ((t0 - 1) * i) / (steps - 1);
    }
    if temp < 1 { temp = 1; }
    rng = _opt_rng_next(rng);
    let delta = (rng % 17) - 8;
    var nx = x + delta;
    if nx < lo { nx = lo; }
    if nx > hi { nx = hi; }
    let cur = f(&x);
    let cand = f(&nx);
    var accept = false;
    if cand > cur {
      accept = true;
    } else {
      rng = _opt_rng_next(rng);
      if rng % (temp + 1) > _opt_abs(cand - cur) {
        accept = true;
      }
    }
    if accept {
      x = nx;
      if cand > best_v {
        best_v = cand;
        best_x = x;
      }
    }
    i = i + 1;
  }
  return best_x;
}

/// Inclusive bounds check: true exactly when lo <= x <= hi.
/// An empty range (hi < lo) is always false.
/// Error case: none.
/// Complexity: O(1).
pub fn opt_bounds_ok(x: Int, lo: Int, hi: Int) -> Bool {
  return x >= lo && x <= hi;
}
