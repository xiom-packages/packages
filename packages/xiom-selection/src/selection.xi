// XIOM -- xiom.selection: deterministic selection operators for evolutionary loops
// Port task: replace the xiom.selection placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Roulette-wheel, tournament, elite and rank selection over Int weight and
// fitness vectors. Everything is deterministic: every operator is a pure
// function of its inputs (weights/fitness plus, where randomness is needed, an
// explicit seed), so a run replays exactly. There is no clock, environment or
// OS randomness source anywhere in this module.
//
// Negative weights count as 0 in every operator (sel_sum and everything built
// on it); ties always resolve toward the earlier (smaller) index.
//
// Free functions only (XIOM v0.61.x has no methods). Vec[Int] element reads are
// bound with an explicitly typed `let` (e.g. `let w: Int = weights[i];`) to
// avoid inference drift. Nothing here uses match, Ok/Err or FFI.
//
// PRNG: a 31-bit xorshift-style mixer over a plain Int state. The exact bit
// recipe is pinned in SPEC.md section 3 and covered by the conformance suite.
// `_sel_seed_state` mixes the seed into a nonzero starting state in
// [1, 2^31 - 1]; `_sel_rng_next` advances the state and returns the new state,
// which doubles as the draw. Both are total on signed 64-bit Int: the result
// is always non-negative and below 2^31, including for negative seeds.

module xiom.selection

// --- deterministic PRNG -----------------------------------------------------

// Seed mix: spread the seed over the 31-bit domain. The 0x00FFFFFFFFFFFFFF
// mask is taken before the left shift, so the shift can never overflow for any
// Int input (including the Int minimum). Result in [0, 2^31 - 1].
fn _sel_mix(v: Int) -> Int {
  var h = v;
  h = h ^ (h >> 13);
  h = h & 0x00FFFFFFFFFFFFFF;
  h = h ^ (h << 7);
  h = h ^ (h >> 17);
  h = h & 0x7FFFFFFF;
  return h;
}

// Starting state for a seed: mix(seed) with the all-zero fixed point excluded.
// Result in [1, 2^31 - 1], so a stream can never collapse.
fn _sel_seed_state(seed: Int) -> Int {
  var state = _sel_mix(seed);
  if state == 0 { state = 0x1F123BB5; }
  return state;
}

// Advance the state one step and return the new state (the draw). The state is
// already masked below 2^31, so the left shift stays below 2^38 and cannot
// overflow. Result in [1, 2^31 - 1]: same state always yields the same draw.
fn _sel_rng_next(state: Int) -> Int {
  var h = state;
  h = h ^ (h >> 13);
  h = h ^ (h << 7);
  h = h ^ (h >> 17);
  h = h & 0x7FFFFFFF;
  if h == 0 { h = 0x1F123BB5; }
  return h;
}

// --- weights ----------------------------------------------------------------

/// Sum the usable roulette weights.
/// Params: weights - the weight vector; negative entries count as 0.
/// Returns: sum of max(weights[i], 0); 0 for an empty (or all-negative) vector.
/// Error case: none.
/// Complexity: O(n). Precondition (documented): the sum fits in an Int.
pub fn sel_sum(weights: &Vec[Int]) -> Int {
  var total = 0;
  var i = 0;
  while i < weights.len() {
    let w: Int = weights[i];
    if w > 0 { total = total + w; }
    i = i + 1;
  }
  return total;
}

// --- roulette ---------------------------------------------------------------

/// Map an explicit roulette draw to a weight index (deterministic core).
/// Params: weights - the weight vector (negative entries count as 0);
/// draw - the ticket to resolve, expected in [0, sel_sum(weights)).
/// Returns: the first index whose cumulative positive weight exceeds `draw`,
/// i.e. the bucket [previous cumulative, cumulative) that contains the draw.
/// Returns -1 when draw < 0, when draw is at or beyond the total (including an
/// empty or all-zero vector), so out-of-range draws are Err-free and total.
/// Error case: none.
/// Complexity: O(n).
pub fn sel_roulette_index(weights: &Vec[Int], draw: Int) -> Int {
  if draw < 0 { return -1; }
  var cumulative = 0;
  var i = 0;
  while i < weights.len() {
    let w: Int = weights[i];
    if w > 0 {
      cumulative = cumulative + w;
      if draw < cumulative { return i; }
    }
    i = i + 1;
  }
  return -1;
}

/// Roulette-wheel selection: draw one index with probability proportional to
/// the (non-negative) weights.
/// Params: weights - the weight vector (negative entries count as 0);
/// seed - any Int (negative, zero and huge values are accepted).
/// Returns: sel_roulette_index(weights, draw) where draw is the first PRNG
/// output of `seed` reduced modulo sel_sum(weights). -1 when the total is 0
/// (empty or all-zero vector) and no draw is consumed then.
/// Error case: none.
/// Complexity: O(n).
pub fn sel_roulette(weights: &Vec[Int], seed: Int) -> Int {
  let total = sel_sum(weights);
  if total <= 0 { return -1; }
  let state = _sel_seed_state(seed);
  let draw = _sel_rng_next(state) % total;
  return sel_roulette_index(weights, draw);
}

// --- tournament -------------------------------------------------------------

/// Tournament selection: sample k contenders with the PRNG, highest fitness
/// wins; ties keep the earlier (smaller) index.
/// Params: fitness - the fitness vector; k - the number of contenders, clamped
/// to [1, len(fitness)] (so k <= 0 means one contender and k > len means all
/// len positions worth of draws); seed - any Int.
/// Returns: the winning index; -1 for an empty vector (no draw is consumed).
/// Sampling: contender c (0-based) is `rng_next^c(seed_state) % len`, i.e. each
/// contender is one draw of the stream, with replacement. A strictly higher
/// fitness replaces the current best; equal fitness replaces it only when the
/// new index is smaller, so ties resolve to the smallest sampled index.
/// Error case: none.
/// Complexity: O(k + n) (k draws, one fitness read per contender).
pub fn sel_tournament_index(fitness: &Vec[Int], k: Int, seed: Int) -> Int {
  let n = fitness.len();
  if n == 0 { return -1; }
  var contenders = k;
  if contenders < 1 { contenders = 1; }
  if contenders > n { contenders = n; }
  var state = _sel_seed_state(seed);
  var best = -1;
  var best_fitness = 0;
  var c = 0;
  while c < contenders {
    state = _sel_rng_next(state);
    let pick = state % n;
    let f: Int = fitness[pick];
    if best < 0 {
      best = pick;
      best_fitness = f;
    } elif f > best_fitness {
      best = pick;
      best_fitness = f;
    } elif f == best_fitness && pick < best {
      best = pick;
    }
    c = c + 1;
  }
  return best;
}

// --- elite ------------------------------------------------------------------

/// Elite selection: the k best indices of the population.
/// Params: fitness - the fitness vector; k - how many elites to return, clamped
/// to len(fitness) (k <= 0 yields an empty vector).
/// Returns: indices ordered by fitness descending, ties earlier index first
/// (stable). Built by insertion sort over indices with the key (fitness desc,
/// index asc): the scan is stable, so equal keys keep ascending index order.
/// Error case: none.
/// Complexity: O(n^2) worst case (insertion sort; near-sorted inputs are O(n)).
pub fn sel_elite_indices(fitness: &Vec[Int], k: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = fitness.len();
  if k <= 0 || n == 0 { return out; }
  var order = Vec[Int].new();
  var i = 0;
  while i < n {
    order.push(i);
    i = i + 1;
  }
  var a = 1;
  while a < n {
    let key: Int = order[a];
    let key_fitness: Int = fitness[key];
    var b = a;
    while b > 0 {
      let prev: Int = order[b - 1];
      let prev_fitness: Int = fitness[prev];
      if prev_fitness >= key_fitness { break; }
      order[b] = prev;
      b = b - 1;
    }
    order[b] = key;
    a = a + 1;
  }
  var take = k;
  if take > n { take = n; }
  var t = 0;
  while t < take {
    let idx: Int = order[t];
    out.push(idx);
    t = t + 1;
  }
  return out;
}

/// Best fitness index (first occurrence on ties).
/// Params: fitness - the fitness vector.
/// Returns: the smallest index attaining the maximum fitness; -1 when empty.
/// Error case: none.
/// Complexity: O(n).
pub fn sel_best_index(fitness: &Vec[Int]) -> Int {
  let n = fitness.len();
  if n == 0 { return -1; }
  var best = 0;
  var best_fitness: Int = fitness[0];
  var i = 1;
  while i < n {
    let f: Int = fitness[i];
    if f > best_fitness {
      best = i;
      best_fitness = f;
    }
    i = i + 1;
  }
  return best;
}

/// Worst fitness index (first occurrence on ties).
/// Params: fitness - the fitness vector.
/// Returns: the smallest index attaining the minimum fitness; -1 when empty.
/// Error case: none.
/// Complexity: O(n).
pub fn sel_worst_index(fitness: &Vec[Int]) -> Int {
  let n = fitness.len();
  if n == 0 { return -1; }
  var worst = 0;
  var worst_fitness: Int = fitness[0];
  var i = 1;
  while i < n {
    let f: Int = fitness[i];
    if f < worst_fitness {
      worst = i;
      worst_fitness = f;
    }
    i = i + 1;
  }
  return worst;
}

// --- rank -------------------------------------------------------------------

/// Linear rank weights: rank i gets weight n - i.
/// Params: n - the population size.
/// Returns: [n, n - 1, ..., 1]; an empty vector when n < 1.
/// Error case: none.
/// Complexity: O(n).
pub fn sel_rank_weights(n: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if n < 1 { return out; }
  var i = 0;
  while i < n {
    out.push(n - i);
    i = i + 1;
  }
  return out;
}
