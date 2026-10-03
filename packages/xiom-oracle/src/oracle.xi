// XIOM -- xiom.oracle: deterministic multi-source oracle feed aggregation
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no clock, no randomness.
//
// A structural model for off-chain data oracles over blockchain systems: a
// round collects one observation per oracle source, then answers the
// questions a consumer asks -- is there a quorum, is the feed fresh, what is
// the aggregate price, and which observations deviate too far from it.
//
// Everything is integer arithmetic at the fixed-point scale 1e-4
// (ORACLE_SCALE = 10000 parts per 1.0), the convention used by the sibling
// chain-family packages. Time is a caller-supplied logical tick counter, not
// wall time. Attestation signing is an explicit non-goal: no key material or
// cryptography lives here.
//
// Language notes (XIOM v0.61.3): free functions only; flat parallel Vecs
// instead of Vec[StructType]; Str equality goes through
// xiom.string.compare.str_compare; every Vec element read is bound to a typed
// local first; Ok/Err are constructed only in the leaf helpers _ok_*/_err_*;
// mutating Vec parameters are passed with an explicit &mut at every call site.

module xiom.oracle

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(r) for Result[OracleRound, Str].
fn _ok_round(r: OracleRound) -> Result[OracleRound, Str] {
  return Ok(r);
}

// Err(m) for Result[OracleRound, Str].
fn _err_round(m: Str) -> Result[OracleRound, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Limits
// --------------------------------------------------

// Fixed-point scale: 10000 parts per 1.0 (one basis point per unit).
const _ORACLE_SCALE: Int = 10000;

// Largest accepted price magnitude (keeps deviation math in range).
const _ORACLE_PRICE_MAX: Int = 1000000000000;

// Largest accepted single observation weight.
const _ORACLE_WEIGHT_MAX: Int = 1000000;

// Largest accepted total weight (overflow guard).
const _ORACLE_WEIGHT_TOTAL_MAX: Int = 1000000000000;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One aggregation round for a feed: the configuration plus the observations
/// collected so far, stored as four index-aligned parallel vectors in
/// arrival order. prices are fixed-point magnitudes (scale 1e-4), ticks are
/// logical timestamps, weights are relative voting weights (>= 1).
pub type OracleRound = {
  feed: Str;
  min_sources: Int;
  max_age_ticks: Int;
  max_deviation_bps: Int;
  sources: Vec[Str];
  prices: Vec[Int];
  ticks: Vec[Int];
  weights: Vec[Int];
}

/// Accessors
// Number of index-aligned observations (the shortest of the four arrays).
fn _oracle_count(r: &OracleRound) -> Int {
  var n = r.sources.len();
  if r.prices.len() < n {
    n = r.prices.len();
  }
  if r.ticks.len() < n {
    n = r.ticks.len();
  }
  if r.weights.len() < n {
    n = r.weights.len();
  }
  return n;
}

// Index of the observation whose source equals `source`, or -1.
fn _oracle_source_index(r: &OracleRound, source: Str) -> Int {
  var i = 0;
  let n = _oracle_count(r);
  while i < n {
    let cur: Str = r.sources[i];
    if compare.str_compare(cur, source) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Absolute value of a non-negative-or-negative Int.
fn _abs(v: Int) -> Int {
  if v < 0 {
    return 0 - v;
  }
  return v;
}

/// A fresh round for a feed.
/// Params: feed - the feed identifier (non-empty); min_sources - how many
/// observations a quorum needs (>= 1); max_age_ticks - how old the newest
/// observation may be before the feed is stale (>= 0); max_deviation_bps -
/// how far an observation may sit from the weighted median, in basis points
/// (0..10000).
/// Returns: Ok(OracleRound  with no observations).
/// Error case: Err("oracle: empty feed"); Err("oracle: bad min sources <n>");
/// Err("oracle: bad max age <n>"); Err("oracle: bad deviation <n>").
/// Complexity: O(1).
pub fn oracle_round_new(feed: Str, min_sources: Int, max_age_ticks: Int, max_deviation_bps: Int) -> Result[OracleRound, Str] {
  if feed.len() == 0 {
    return _err_round("oracle: empty feed");
  }
  if min_sources < 1 {
    return _err_round("oracle: bad min sources " + int_to_string(min_sources));
  }
  if max_age_ticks < 0 {
    return _err_round("oracle: bad max age " + int_to_string(max_age_ticks));
  }
  if max_deviation_bps < 0 || max_deviation_bps > _ORACLE_SCALE {
    return _err_round("oracle: bad deviation " + int_to_string(max_deviation_bps));
  }
  return _ok_round(OracleRound{
    feed: feed;
    min_sources: min_sources;
    max_age_ticks: max_age_ticks;
    max_deviation_bps: max_deviation_bps;
    sources: Vec[Str].new();
    prices: Vec[Int].new();
    ticks: Vec[Int].new();
    weights: Vec[Int].new();
  });
}

/// Record one source's observation. Sources are case-sensitive and unique
/// within a round; a failed call never mutates the round.
/// Params: r - the round to mutate; source - the oracle source id
/// (non-empty); price - the fixed-point price (1..1000000000000); tick - the
/// logical observation time (>= 0); weight - the voting weight
/// (1..1000000).
/// Returns: Ok(count) with the new observation count.
/// Error case: Err("oracle: empty source"); Err("oracle: duplicate source
/// '<s>'"); Err("oracle: bad price <p>"); Err("oracle: bad tick <t>");
/// Err("oracle: bad weight <w>").
/// Complexity: O(observations).
pub fn oracle_observe(r: &mut OracleRound, source: Str, price: Int, tick: Int, weight: Int) -> Result[Int, Str] {
  if source.len() == 0 {
    return _err_int("oracle: empty source");
  }
  if _oracle_source_index(r, source) >= 0 {
    return _err_int("oracle: duplicate source '" + source + "'");
  }
  if price < 1 || price > _ORACLE_PRICE_MAX {
    return _err_int("oracle: bad price " + int_to_string(price));
  }
  if tick < 0 {
    return _err_int("oracle: bad tick " + int_to_string(tick));
  }
  if weight < 1 || weight > _ORACLE_WEIGHT_MAX {
    return _err_int("oracle: bad weight " + int_to_string(weight));
  }
  r.sources.push(source);
  r.prices.push(price);
  r.ticks.push(tick);
  r.weights.push(weight);
  return _ok_int(_oracle_count(r));
}

/// Feed identifier of the round.
/// Params: r - the round.
/// Returns: the feed.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_feed(r: &OracleRound) -> Str {
  let v: Str = r.feed;
  return v;
}

/// Minimum quorum size of the round.
/// Params: r - the round.
/// Returns: min_sources.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_min_sources(r: &OracleRound) -> Int {
  let v: Int = r.min_sources;
  return v;
}

/// Maximum accepted age of the newest observation.
/// Params: r - the round.
/// Returns: max_age_ticks.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_max_age_ticks(r: &OracleRound) -> Int {
  let v: Int = r.max_age_ticks;
  return v;
}

/// Maximum accepted deviation from the weighted median, in basis points.
/// Params: r - the round.
/// Returns: max_deviation_bps.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_max_deviation_bps(r: &OracleRound) -> Int {
  let v: Int = r.max_deviation_bps;
  return v;
}

/// Number of observations collected.
/// Params: r - the round.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_observation_count(r: &OracleRound) -> Int {
  return _oracle_count(r);
}

/// Source of observation `i`.
/// Params: r - the round; i - the zero-based index.
/// Returns: the source; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_source(r: &OracleRound, i: Int) -> Str {
  if i < 0 || i >= _oracle_count(r) {
    return "";
  }
  let v: Str = r.sources[i];
  return v;
}

/// Price of observation `i`.
/// Params: r - the round; i - the zero-based index.
/// Returns: the price; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_price(r: &OracleRound, i: Int) -> Int {
  if i < 0 || i >= _oracle_count(r) {
    return -1;
  }
  let v: Int = r.prices[i];
  return v;
}

/// Logical time of observation `i`.
/// Params: r - the round; i - the zero-based index.
/// Returns: the tick; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_tick(r: &OracleRound, i: Int) -> Int {
  if i < 0 || i >= _oracle_count(r) {
    return -1;
  }
  let v: Int = r.ticks[i];
  return v;
}

/// Weight of observation `i`.
/// Params: r - the round; i - the zero-based index.
/// Returns: the weight; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_weight(r: &OracleRound, i: Int) -> Int {
  if i < 0 || i >= _oracle_count(r) {
    return -1;
  }
  let v: Int = r.weights[i];
  return v;
}

/// True when the round has at least min_sources observations.
/// Params: r - the round.
/// Returns: the flag.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_quorum_met(r: &OracleRound) -> Bool {
  return _oracle_count(r) >= r.min_sources;
}

/// Newest observation tick.
/// Params: r - the round.
/// Returns: the maximum tick; -1 when there are no observations.
/// Error case: none.
/// Complexity: O(observations).
pub fn oracle_latest_tick(r: &OracleRound) -> Int {
  var best = -1;
  var i = 0;
  let n = _oracle_count(r);
  while i < n {
    let t: Int = r.ticks[i];
    if t > best {
      best = t;
    }
    i = i + 1;
  }
  return best;
}

/// Age of the newest observation at logical time `now_tick`.
/// Params: r - the round; now_tick - the consumer's logical time.
/// Returns: now_tick - latest_tick; -1 when there are no observations. A
/// `now_tick` below the newest tick yields a negative age (an observation
/// from the future is not stale).
/// Error case: none.
/// Complexity: O(observations).
pub fn oracle_age_ticks(r: &OracleRound, now_tick: Int) -> Int {
  let latest = oracle_latest_tick(r);
  if latest < 0 {
    return -1;
  }
  return now_tick - latest;
}

/// True when the round has no observations or its newest observation is
/// older than max_age_ticks.
/// Params: r - the round; now_tick - the consumer's logical time.
/// Returns: the flag.
/// Error case: none.
/// Complexity: O(observations).
pub fn oracle_is_stale(r: &OracleRound, now_tick: Int) -> Bool {
  if _oracle_count(r) == 0 {
    return true;
  }
  let age = oracle_age_ticks(r, now_tick);
  return age > r.max_age_ticks;
}

// --------------------------------------------------
//  Aggregation
// --------------------------------------------------

// Insertion-sort two parallel arrays by ascending price.
fn _sort_pairs(prices: &mut Vec[Int], weights: &mut Vec[Int]) {
  let n = prices.len();
  var i = 1;
  while i < n {
    let p: Int = prices[i];
    let w: Int = weights[i];
    var j = i;
    while j > 0 {
      let pj: Int = prices[j - 1];
      if pj <= p {
        break;
      }
      prices[j] = pj;
      let wj: Int = weights[j - 1];
      weights[j] = wj;
      j = j - 1;
    }
    prices[j] = p;
    weights[j] = w;
    i = i + 1;
  }
}

// Weighted median of two equal-length arrays: sort by price, then return the
// price at the first position whose cumulative weight reaches half of the
// total (ties resolve to the lowest such price).
fn _weighted_median_parts(prices: &mut Vec[Int], weights: &mut Vec[Int]) -> Result[Int, Str] {
  let n = prices.len();
  if n == 0 {
    return _err_int("oracle: no observations");
  }
  _sort_pairs(prices, weights);
  var total = 0;
  var i = 0;
  while i < n {
    let w: Int = weights[i];
    if total > _ORACLE_WEIGHT_TOTAL_MAX - w {
      return _err_int("oracle: weight overflow");
    }
    total = total + w;
    i = i + 1;
  }
  var acc = 0;
  i = 0;
  while i < n {
    let w: Int = weights[i];
    acc = acc + w;
    if acc * 2 >= total {
      let p: Int = prices[i];
      return _ok_int(p);
    }
    i = i + 1;
  }
  let last: Int = prices[n - 1];
  return _ok_int(last);
}

// Copy the observations of `r` into fresh arrays.
fn _copy_prices(r: &OracleRound, out: &mut Vec[Int]) {
  var i = 0;
  let n = _oracle_count(r);
  while i < n {
    let p: Int = r.prices[i];
    out.push(p);
    i = i + 1;
  }
}

// Copy the weights of `r` into fresh arrays (same order as _copy_prices).
fn _copy_weights(r: &OracleRound, out: &mut Vec[Int]) {
  var i = 0;
  let n = _oracle_count(r);
  while i < n {
    let w: Int = r.weights[i];
    out.push(w);
    i = i + 1;
  }
}

/// Unweighted median of the observation prices: the middle price for an odd
/// count, the floored average of the two middle prices for an even count.
/// Params: r - the round.
/// Returns: Ok(price).
/// Error case: Err("oracle: no observations").
/// Complexity: O(n^2) insertion sort.
pub fn oracle_median(r: &OracleRound) -> Result[Int, Str] {
  let n = _oracle_count(r);
  if n == 0 {
    return _err_int("oracle: no observations");
  }
  var ps = Vec[Int].new();
  _copy_prices(r, &mut ps);
  // sort a single array
  var i = 1;
  while i < n {
    let p: Int = ps[i];
    var j = i;
    while j > 0 {
      let pj: Int = ps[j - 1];
      if pj <= p {
        break;
      }
      ps[j] = pj;
      j = j - 1;
    }
    ps[j] = p;
    i = i + 1;
  }
  if n % 2 == 0 {
    // n is even: floor average of the two middle prices
    let a: Int = ps[n / 2 - 1];
    let b: Int = ps[n / 2];
    return _ok_int((a + b) / 2);
  }
  let mid: Int = ps[n / 2];
  return _ok_int(mid);
}

/// Weighted median of the observation prices (see _weighted_median_parts).
/// Params: r - the round.
/// Returns: Ok(price); ties resolve to the lowest price whose cumulative
/// weight reaches half of the total weight.
/// Error case: Err("oracle: no observations"); Err("oracle: weight
/// overflow") when the total weight exceeds 1000000000000.
/// Complexity: O(n^2) insertion sort.
pub fn oracle_weighted_median(r: &OracleRound) -> Result[Int, Str] {
  var ps = Vec[Int].new();
  var ws = Vec[Int].new();
  _copy_prices(r, &mut ps);
  _copy_weights(r, &mut ws);
  return _weighted_median_parts(&mut ps, &mut ws);
}

/// Number of observations whose distance from the weighted median exceeds
/// max_deviation_bps: floor(|price - median| * 10000 / median) > bps.
/// Params: r - the round.
/// Returns: Ok(count).
/// Error case: the errors of oracle_weighted_median.
/// Complexity: O(n^2).
pub fn oracle_deviation_rejects(r: &OracleRound) -> Result[Int, Str] {
  let wm = oracle_weighted_median(r);
  var median = 0;
  match wm {
    Ok(v) => { median = v; },
    Err(e) => { return _err_int(e); },
  }
  var rejects = 0;
  var i = 0;
  let n = _oracle_count(r);
  while i < n {
    let p: Int = r.prices[i];
    let diff = _abs(p - median) * _ORACLE_SCALE;
    let bps = diff / median;
    if bps > r.max_deviation_bps {
      rejects = rejects + 1;
    }
    i = i + 1;
  }
  return _ok_int(rejects);
}

/// Full aggregation pipeline for a consumer at logical time `now_tick`:
/// quorum check, freshness check, weighted median, deviation filter and a
/// second weighted median over the accepted observations, which must still
/// form a quorum.
/// Params: r - the round; now_tick - the consumer's logical time.
/// Returns: Ok(aggregate price).
/// Error case: Err("oracle: no observations"); Err("oracle: quorum not met")
/// when fewer than min_sources observations exist; Err("oracle: stale feed")
/// when the newest observation is older than max_age_ticks; Err("oracle:
/// quorum lost after deviation filter") when too few observations remain;
/// Err("oracle: weight overflow") on a huge total weight.
/// Complexity: O(n^2).
pub fn oracle_aggregate(r: &OracleRound, now_tick: Int) -> Result[Int, Str] {
  let n = _oracle_count(r);
  if n == 0 {
    return _err_int("oracle: no observations");
  }
  if n < r.min_sources {
    return _err_int("oracle: quorum not met");
  }
  if oracle_is_stale(r, now_tick) {
    return _err_int("oracle: stale feed");
  }
  let wm = oracle_weighted_median(r);
  var median = 0;
  match wm {
    Ok(v) => { median = v; },
    Err(e) => { return _err_int(e); },
  }
  var fs = Vec[Str].new();
  var fp = Vec[Int].new();
  var fw = Vec[Int].new();
  var i = 0;
  while i < n {
    let p: Int = r.prices[i];
    let diff = _abs(p - median) * _ORACLE_SCALE;
    let bps = diff / median;
    if bps <= r.max_deviation_bps {
      let s: Str = r.sources[i];
      let w: Int = r.weights[i];
      fs.push(s);
      fp.push(p);
      fw.push(w);
    }
    i = i + 1;
  }
  if fp.len() < r.min_sources {
    return _err_int("oracle: quorum lost after deviation filter");
  }
  return _weighted_median_parts(&mut fp, &mut fw);
}

/// Clear the observations of `r`, keeping the round configuration.
/// Params: r - the round to reset.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn oracle_reset(r: &mut OracleRound) {
  r.sources = Vec[Str].new();
  r.prices = Vec[Int].new();
  r.ticks = Vec[Int].new();
  r.weights = Vec[Int].new();
}
