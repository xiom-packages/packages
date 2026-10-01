// XIOM -- xiom.defi: deterministic integer DeFi pool models
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM, FFI-free building blocks for two canonical DeFi pool models:
// a constant-product automated market maker (x*y=k) and a share-index
// lending pool. All state is integer; there is no floating point.
//
// Fixed-point convention: DEFI_SCALE = 10000 parts per 1.0 (scale 1e-4), so
// one basis point is exactly one scale unit. Fees (`fee_bps`), per-tick
// interest (`rate_bps`), liquidation thresholds, close factors and bonuses
// all cross the API in parts per 10000. Indexes start at DEFI_SCALE (1.0)
// and are monotone non-decreasing.
//
// Rounding (single documented convention): every native Int `/` truncates
// toward zero. For the non-negative magnitudes used here that is a floor, so
// swap outputs, share credits, index increments, repayment amounts and
// liquidation repayment all round in the pool's favor; the only ceiling
// divisions (`_defi_ceil_div`) are the amount-in quote for a desired output
// and the seizure amount including the liquidation bonus.
//
// Overflow guards: every product goes through `_defi_mul_sat` and every sum
// through `_defi_add_sat`. Both saturate at core.INT_MAX instead of wrapping,
// so extreme inputs stay deterministic; the guards are exercised by tests.
//
// Language notes (XIOM v0.62.2): free functions only (no methods/self); no
// Vec[StructType], no lambdas, no fn tables; Result leaves use the
// _defi_ok/_defi_err helpers; no Vec[Str].push; every loop advances its
// counter and the suite terminates in O(ticks) work.

module xiom.defi

use xiom.core;

// --- fixed-point constants --------------------------------------------------

/// Fixed-point scale: 10000 parts per 1.0 (scale 1e-4). One basis point is
/// one scale unit, and an index of DEFI_SCALE means 1.0.
pub const DEFI_SCALE: Int = 10000;

/// Highest accepted basis-point value (100%): fee_bps, rate_bps, thresholds,
/// close factors and bonuses are clamped into [0, DEFI_BPS].
pub const DEFI_BPS: Int = 10000;

// --- internal helpers -------------------------------------------------------

// Leaf Ok(v) for Result[Int, Str] (leaf helpers are required on v0.62.2).
fn _defi_ok(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Leaf Err(m) for Result[Int, Str].
fn _defi_err(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Clamp `v` into [0, DEFI_BPS]. Negative values become 0, values above
// 10000 become 10000.
fn _defi_clamp_bps(v: Int) -> Int {
  if v < 0 {
    return 0;
  }
  if v > DEFI_BPS {
    return DEFI_BPS;
  }
  return v;
}

// Saturating product of two non-negative values: min(a * b, INT_MAX),
// computed without overflowing. A non-positive operand yields 0, so the
// public API (which rejects negative amounts) never multiplies negatives.
fn _defi_mul_sat(a: Int, b: Int) -> Int {
  if a <= 0 || b <= 0 {
    return 0;
  }
  if a > core.INT_MAX / b {
    return core.INT_MAX;
  }
  return a * b;
}

// Saturating sum of two non-negative values: min(a + b, INT_MAX), computed
// without overflowing. Negative operands are treated as 0 and zero is the
// identity, so a pool field can be seeded from 0.
fn _defi_add_sat(a: Int, b: Int) -> Int {
  var x = a;
  var y = b;
  if x < 0 {
    x = 0;
  }
  if y < 0 {
    y = 0;
  }
  if x > core.INT_MAX - y {
    return core.INT_MAX;
  }
  return x + y;
}

// ceil(a / b) for a >= 0 and b > 0, using the native truncating division:
// for a > 0 a non-zero remainder is one below the ceiling, and for a == 0
// truncation is already the ceiling. Returns 0 when b <= 0.
fn _defi_ceil_div(a: Int, b: Int) -> Int {
  if b <= 0 {
    return 0;
  }
  var q = a / b;
  if a > 0 {
    if a % b != 0 {
      q = q + 1;
    }
  }
  return q;
}

// floor(sqrt(n)) for n >= 0 via integer Newton iteration: x starts at
// n/2 + 1 >= sqrt(n) and strictly decreases while next < x, so the loop
// terminates. Returns 0 for n <= 0. Hand-rolled to keep the package free of
// the xiom.math import tree (which the standard library also exposes as
// xiom.math.roots.integer_sqrt).
fn _defi_isqrt(n: Int) -> Int {
  if n <= 0 {
    return 0;
  }
  if n < 2 {
    return n;
  }
  var x = n / 2 + 1;
  while true {
    let next = (x + n / x) / 2;
    if next >= x {
      return x;
    }
    x = next;
  }
}

// ============================================================================
//  Constant-product AMM (x * y = k)
// ============================================================================

/// Constant-product liquidity pool state.
/// `reserve_a` and `reserve_b` are the pool's token balances in base units,
/// `lp_total` is the outstanding LP share count, and `fee_bps` is the swap
/// fee in parts per 10000 (clamped to [0, 10000] by the constructors).
pub type AmmPool = {
  reserve_a: Int;
  reserve_b: Int;
  lp_total: Int;
  fee_bps: Int;
}

/// New constant-product pool seeded with `reserve_a` / `reserve_b`.
/// Negative reserves are clamped to 0; `fee_bps` is clamped to [0, 10000].
/// Initial LP shares are floor(sqrt(reserve_a * reserve_b)) (the geometric
/// mean), so a pool seeded 100000/400000 starts with 200000 shares; when both
/// reserves are positive but the geometric mean truncates to 0, one seed
/// share is minted so the pool is never share-less. A pool with a zero
/// reserve starts with 0 shares and is bootstrapped by the first `amm_mint`.
/// Params: reserve_a - token A base units; reserve_b - token B base units;
///         fee_bps - swap fee in parts per 10000.
/// Returns: the pool.
/// Error case: none (inputs are clamped).
/// Complexity: O(log(reserve_a * reserve_b)).
pub fn amm_new(reserve_a: Int, reserve_b: Int, fee_bps: Int) -> AmmPool {
  var ra = reserve_a;
  var rb = reserve_b;
  if ra < 0 {
    ra = 0;
  }
  if rb < 0 {
    rb = 0;
  }
  var shares = _defi_isqrt(_defi_mul_sat(ra, rb));
  if shares <= 0 && ra > 0 && rb > 0 {
    shares = 1;
  }
  return AmmPool{
    reserve_a: ra;
    reserve_b: rb;
    lp_total: shares;
    fee_bps: _defi_clamp_bps(fee_bps);
  };
}

/// Swap fee taken from `amount_in`: floor(amount_in * fee_bps / 10000).
/// The floor rounds the fee down (in the trader's favor by less than one
/// base unit). Non-positive amounts and a 0 fee yield 0.
/// Params: amount_in - input amount; fee_bps - fee in parts per 10000.
/// Returns: the fee in the same units as `amount_in`.
/// Error case: none.
/// Complexity: O(1).
pub fn amm_fee_amount(amount_in: Int, fee_bps: Int) -> Int {
  if amount_in <= 0 {
    return 0;
  }
  return _defi_mul_sat(amount_in, _defi_clamp_bps(fee_bps)) / DEFI_SCALE;
}

/// Output of a constant-product swap for a given input.
/// Derivation: `in_with_fee = amount_in - amm_fee_amount(...)` and
/// `out = in_with_fee * reserve_out / (reserve_in + in_with_fee)`, the exact
/// integer form of x*y=k with the fee applied to the input. The division
/// truncates toward zero (floor), so the pool keeps the rounding dust and
/// output is at or below the exact rational value. `out` is capped at
/// `reserve_out` so a saturating numerator can never drain the pool.
/// Params: reserve_in - input-side reserve; reserve_out - output-side
///         reserve; amount_in - input amount; fee_bps - fee per 10000.
/// Returns: output amount; 0 when an input is non-positive, either reserve is
///          non-positive, or the fee is 100% (zero net input).
/// Error case: none.
/// Complexity: O(1).
pub fn amm_get_amount_out(reserve_in: Int, reserve_out: Int, amount_in: Int, fee_bps: Int) -> Int {
  if amount_in <= 0 || reserve_in <= 0 || reserve_out <= 0 {
    return 0;
  }
  let fee = _defi_clamp_bps(fee_bps);
  let amount_in_with_fee = amount_in - amm_fee_amount(amount_in, fee);
  if amount_in_with_fee <= 0 {
    return 0;
  }
  let numerator = _defi_mul_sat(amount_in_with_fee, reserve_out);
  let denominator = _defi_add_sat(reserve_in, amount_in_with_fee);
  if denominator <= 0 {
    return 0;
  }
  var out = numerator / denominator;
  if out > reserve_out {
    out = reserve_out;
  }
  return out;
}

/// Input required to receive `amount_out` from a constant-product swap.
/// Inverts `amm_get_amount_out` with two ceiling divisions so the quoted
/// input is always sufficient: `without_fee = ceil(reserve_in * amount_out /
/// (reserve_out - amount_out))` and then `in = ceil(without_fee * 10000 /
/// (10000 - fee_bps))`. A 100% fee and an `amount_out` at or above the
/// output reserve cannot be served and return 0.
/// Params: reserve_in - input-side reserve; reserve_out - output-side
///         reserve; amount_out - desired output; fee_bps - fee per 10000.
/// Returns: required input amount; 0 when unserviceable.
/// Error case: none.
/// Complexity: O(1).
pub fn amm_get_amount_in(reserve_in: Int, reserve_out: Int, amount_out: Int, fee_bps: Int) -> Int {
  if amount_out <= 0 || reserve_in <= 0 || reserve_out <= 0 {
    return 0;
  }
  if amount_out >= reserve_out {
    return 0;
  }
  let fee = _defi_clamp_bps(fee_bps);
  if fee >= DEFI_BPS {
    return 0;
  }
  let without_fee = _defi_ceil_div(_defi_mul_sat(reserve_in, amount_out), reserve_out - amount_out);
  if without_fee <= 0 {
    return 0;
  }
  return _defi_ceil_div(_defi_mul_sat(without_fee, DEFI_SCALE), DEFI_SCALE - fee);
}

/// Marginal (spot) price of token A in token B, in parts per 10000:
/// floor(reserve_b * 10000 / reserve_a). One unit of A is worth this many
/// 1e-4 units of B when the pool is not moved.
/// Params: reserve_a - token A reserve; reserve_b - token B reserve.
/// Returns: price in parts per 10000; 0 when either reserve is non-positive.
/// Error case: none.
/// Complexity: O(1).
pub fn amm_spot_price_bps(reserve_a: Int, reserve_b: Int) -> Int {
  if reserve_a <= 0 || reserve_b <= 0 {
    return 0;
  }
  return _defi_mul_sat(reserve_b, DEFI_SCALE) / reserve_a;
}

/// Execute a swap against the pool, honoring a minimum-output guard.
/// `a_to_b` selects the direction: true sells A for B (A is the input
/// reserve), false sells B for A. The quote is computed first and the state
/// is mutated only when all guards pass, so a rejected swap leaves the pool
/// exactly unchanged. On success the input reserve grows by `amount_in`, the
/// output reserve shrinks by the output amount, and x*y=k never decreases
/// (fees make k strictly grow when the fee is positive).
/// Params: p - the pool; amount_in - input amount; min_out - minimum
///         acceptable output (0 or negative disables the guard);
///         a_to_b - swap direction.
/// Returns: Ok(output) on success.
/// Error case: Err("amm: amount_in must be > 0") for a non-positive input;
///             Err("amm: empty reserves") when either reserve is <= 0;
///             Err("amm: zero output") when the quote rounds to 0;
///             Err("amm: slippage") when output < min_out.
/// Complexity: O(1).
pub fn amm_swap(p: &mut AmmPool, amount_in: Int, min_out: Int, a_to_b: Bool) -> Result[Int, Str] {
  if amount_in <= 0 {
    return _defi_err("amm: amount_in must be > 0");
  }
  if p.reserve_a <= 0 || p.reserve_b <= 0 {
    return _defi_err("amm: empty reserves");
  }
  var out = 0;
  if a_to_b {
    out = amm_get_amount_out(p.reserve_a, p.reserve_b, amount_in, p.fee_bps);
  } else {
    out = amm_get_amount_out(p.reserve_b, p.reserve_a, amount_in, p.fee_bps);
  }
  if out <= 0 {
    return _defi_err("amm: zero output");
  }
  if out < min_out {
    return _defi_err("amm: slippage");
  }
  if a_to_b {
    p.reserve_a = _defi_add_sat(p.reserve_a, amount_in);
    p.reserve_b = p.reserve_b - out;
  } else {
    p.reserve_b = _defi_add_sat(p.reserve_b, amount_in);
    p.reserve_a = p.reserve_a - out;
  }
  return _defi_ok(out);
}

/// Mint LP shares by depositing both tokens at the pool's current ratio.
/// With an outstanding share supply: `shares = min(floor(amount_a *
/// lp_total / reserve_a), floor(amount_b * lp_total / reserve_b))` -- the
/// smaller of the two proportional claims, so a deposit is never overpaid in
/// shares; both full amounts are deposited and any imbalance is retained by
/// the pool (a documented donation to existing LPs). With no outstanding
/// shares (a fresh or drained pool) the geometric mean
/// floor(sqrt(amount_a * amount_b)) is minted, or 1 when that truncates to 0.
/// Params: p - the pool; amount_a - token A deposit; amount_b - token B
///         deposit.
/// Returns: minted shares; 0 (and no state change) when an amount is
///          non-positive, the pool has shares but a zero reserve, or the
///          proportional share count truncates to 0.
/// Error case: none.
/// Complexity: O(log(amount_a * amount_b)) for a first mint, O(1) otherwise.
pub fn amm_mint(p: &mut AmmPool, amount_a: Int, amount_b: Int) -> Int {
  if amount_a <= 0 || amount_b <= 0 {
    return 0;
  }
  var shares = 0;
  if p.lp_total <= 0 {
    shares = _defi_isqrt(_defi_mul_sat(amount_a, amount_b));
    if shares <= 0 {
      shares = 1;
    }
  } else {
    if p.reserve_a <= 0 || p.reserve_b <= 0 {
      return 0;
    }
    let shares_a = _defi_mul_sat(amount_a, p.lp_total) / p.reserve_a;
    let shares_b = _defi_mul_sat(amount_b, p.lp_total) / p.reserve_b;
    shares = shares_a;
    if shares_b < shares {
      shares = shares_b;
    }
    if shares <= 0 {
      return 0;
    }
  }
  p.reserve_a = _defi_add_sat(p.reserve_a, amount_a);
  p.reserve_b = _defi_add_sat(p.reserve_b, amount_b);
  p.lp_total = _defi_add_sat(p.lp_total, shares);
  return shares;
}

/// Burn LP shares and withdraw the proportional reserves.
/// `amount_a = floor(shares * reserve_a / lp_total)` and likewise for B;
/// both floors round in the pool's favor, so a full round trip after a
/// proportional mint never withdraws more than was deposited. A burn whose
/// both withdrawals truncate to 0 is rejected without state change so dust
/// shares cannot be destroyed for nothing.
/// Params: p - the pool; shares - LP shares to burn.
/// Returns: (withdrawn_a, withdrawn_b); (0, 0) with no state change when
///          `shares` is non-positive, exceeds `lp_total`, the pool has no
///          shares, or both withdrawals round to 0.
/// Error case: none.
/// Complexity: O(1).
pub fn amm_burn(p: &mut AmmPool, shares: Int) -> (Int, Int) {
  if shares <= 0 || p.lp_total <= 0 || shares > p.lp_total {
    return (0, 0);
  }
  let amount_a = _defi_mul_sat(shares, p.reserve_a) / p.lp_total;
  let amount_b = _defi_mul_sat(shares, p.reserve_b) / p.lp_total;
  if amount_a <= 0 && amount_b <= 0 {
    return (0, 0);
  }
  p.reserve_a = p.reserve_a - amount_a;
  p.reserve_b = p.reserve_b - amount_b;
  p.lp_total = p.lp_total - shares;
  return (amount_a, amount_b);
}

/// Current invariant value k = reserve_a * reserve_b (saturating).
/// Params: p - the pool.
/// Returns: k, capped at core.INT_MAX for extreme reserves.
/// Error case: none.
/// Complexity: O(1).
pub fn amm_k(p: &AmmPool) -> Int {
  return _defi_mul_sat(p.reserve_a, p.reserve_b);
}

/// True when the pool's invariant did not shrink between two snapshots:
/// sat(after) >= sat(before). Fee-bearing swaps and proportional mints keep
/// this true; only a buggy transition (or an unbalanced withdrawal) can make
/// it false.
/// Params: reserve_a_before, reserve_b_before - pre-state reserves;
///         reserve_a_after, reserve_b_after - post-state reserves.
/// Returns: true when k is non-decreasing.
/// Error case: none.
/// Complexity: O(1).
pub fn amm_k_check(reserve_a_before: Int, reserve_b_before: Int, reserve_a_after: Int, reserve_b_after: Int) -> Bool {
  let k_before = _defi_mul_sat(reserve_a_before, reserve_b_before);
  let k_after = _defi_mul_sat(reserve_a_after, reserve_b_after);
  return k_after >= k_before;
}

// ============================================================================
//  Share-index lending pool
// ============================================================================

/// Lending pool state with share indexes.
/// `supply_shares` / `borrow_shares` are the outstanding share counts;
/// `supply_index` / `borrow_index` are the per-share exchange rates in parts
/// per 10000 (1.0 = DEFI_SCALE) and are monotone non-decreasing. The live
/// totals are `shares * index / 10000`. `reserve_bps` is the fraction of
/// borrow interest kept by the pool (not credited to suppliers), in parts
/// per 10000.
pub type LendPool = {
  supply_shares: Int;
  borrow_shares: Int;
  supply_index: Int;
  borrow_index: Int;
  reserve_bps: Int;
}

/// New empty lending pool with both indexes at 1.0.
/// Params: reserve_bps - interest reserve factor in parts per 10000 (clamped
///         to [0, 10000]).
/// Returns: the pool.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_new(reserve_bps: Int) -> LendPool {
  return LendPool{
    supply_shares: 0;
    borrow_shares: 0;
    supply_index: DEFI_SCALE;
    borrow_index: DEFI_SCALE;
    reserve_bps: _defi_clamp_bps(reserve_bps);
  };
}

/// Live supplied amount: floor(supply_shares * supply_index / 10000).
/// Params: p - the pool.
/// Returns: total supplied base units.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_total_supply(p: &LendPool) -> Int {
  return _defi_mul_sat(p.supply_shares, p.supply_index) / DEFI_SCALE;
}

/// Live borrowed amount: floor(borrow_shares * borrow_index / 10000).
/// Params: p - the pool.
/// Returns: total borrowed base units.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_total_borrow(p: &LendPool) -> Int {
  return _defi_mul_sat(p.borrow_shares, p.borrow_index) / DEFI_SCALE;
}

/// Current value of `shares` supply shares: floor(shares * supply_index /
/// 10000). Non-positive share counts yield 0.
/// Params: p - the pool; shares - share count.
/// Returns: redeemable base units.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_supply_balance(p: &LendPool, shares: Int) -> Int {
  if shares <= 0 {
    return 0;
  }
  return _defi_mul_sat(shares, p.supply_index) / DEFI_SCALE;
}

/// Current debt of `shares` borrow shares: floor(shares * borrow_index /
/// 10000). Non-positive share counts yield 0.
/// Params: p - the pool; shares - share count.
/// Returns: owed base units.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_borrow_balance(p: &LendPool, shares: Int) -> Int {
  if shares <= 0 {
    return 0;
  }
  return _defi_mul_sat(shares, p.borrow_index) / DEFI_SCALE;
}

/// Supply `amount` and mint shares at the current supply index:
/// `shares = floor(amount * 10000 / supply_index)`. The floor favors the
/// pool, so a round trip (supply then withdraw with no accrual) returns at
/// most the deposited amount.
/// Params: p - the pool; amount - base units to supply.
/// Returns: minted shares; 0 (and no state change) when `amount` is
///          non-positive or truncates to 0 shares.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_supply(p: &mut LendPool, amount: Int) -> Int {
  if amount <= 0 || p.supply_index <= 0 {
    return 0;
  }
  let shares = _defi_mul_sat(amount, DEFI_SCALE) / p.supply_index;
  if shares <= 0 {
    return 0;
  }
  p.supply_shares = _defi_add_sat(p.supply_shares, shares);
  return shares;
}

/// Burn `shares` supply shares and withdraw floor(shares * supply_index /
/// 10000) base units. The floor rounds in the pool's favor, and the
/// withdrawal is only granted when the amount does not exceed the currently
/// available liquidity (`total_supply - total_borrow`), so borrowed funds
/// cannot be withdrawn.
/// Params: p - the pool; shares - supply shares to burn.
/// Returns: withdrawn base units; 0 (and no state change) when `shares` is
///          non-positive, exceeds `supply_shares`, withdraws 0 units, or the
///          amount exceeds available liquidity.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_withdraw(p: &mut LendPool, shares: Int) -> Int {
  if shares <= 0 || shares > p.supply_shares {
    return 0;
  }
  let amount = _defi_mul_sat(shares, p.supply_index) / DEFI_SCALE;
  if amount <= 0 {
    return 0;
  }
  let available = lend_total_supply(p) - lend_total_borrow(p);
  if amount > available {
    return 0;
  }
  p.supply_shares = p.supply_shares - shares;
  return amount;
}

/// Borrow `amount`, minting shares at the current borrow index:
/// `shares = floor(amount * 10000 / borrow_index)`. The floor favors the
/// pool. A borrow is only granted when the requested amount does not exceed
/// the currently available liquidity (`total_supply - total_borrow`).
/// Params: p - the pool; amount - base units to borrow.
/// Returns: minted borrow shares; 0 (and no state change) when `amount` is
///          non-positive, exceeds available liquidity, or truncates to
///          0 shares.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_borrow(p: &mut LendPool, amount: Int) -> Int {
  if amount <= 0 || p.borrow_index <= 0 {
    return 0;
  }
  let available = lend_total_supply(p) - lend_total_borrow(p);
  if amount > available {
    return 0;
  }
  let shares = _defi_mul_sat(amount, DEFI_SCALE) / p.borrow_index;
  if shares <= 0 {
    return 0;
  }
  p.borrow_shares = _defi_add_sat(p.borrow_shares, shares);
  return shares;
}

/// Repay `shares` borrow shares and return the base units burned:
/// floor(shares * borrow_index / 10000). The floor favors the pool.
/// Params: p - the pool; shares - borrow shares to repay.
/// Returns: repaid base units; 0 (and no state change) when `shares` is
///          non-positive, exceeds `borrow_shares`, or repays 0 units.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_repay(p: &mut LendPool, shares: Int) -> Int {
  if shares <= 0 || shares > p.borrow_shares {
    return 0;
  }
  let amount = _defi_mul_sat(shares, p.borrow_index) / DEFI_SCALE;
  if amount <= 0 {
    return 0;
  }
  p.borrow_shares = p.borrow_shares - shares;
  return amount;
}

/// Accrue `ticks` per-tick interest at `rate_bps` per tick.
/// Each tick compounds the borrow index in place:
///   `borrow_index = floor(borrow_index * (10000 + rate) / 10000)`
/// then computes `borrow_interest = floor(borrow_shares * delta_index /
/// 10000)`, keeps `reserve_cut = floor(borrow_interest * reserve_bps /
/// 10000)` for the pool, and credits the rest to suppliers as
/// `supply_index += floor(supply_interest * 10000 / supply_shares)` (the
/// per-share increment floors, so suppliers receive at most their exact
/// share). With no supply shares the supplier side is skipped but the borrow
/// index still compounds. `rate_bps` <= 0 makes the call a no-op, and the
/// non-negative rate keeps both indexes monotone non-decreasing.
/// Params: p - the pool; rate_bps - interest per tick in parts per 10000
///         (clamped to [0, 10000]); ticks - number of compounding steps.
/// Returns: total interest credited to suppliers across the ticks; 0 for
///          `ticks <= 0` or `rate_bps <= 0`.
/// Error case: none.
/// Complexity: O(ticks); the loop counter strictly increases.
pub fn lend_accrue(p: &mut LendPool, rate_bps: Int, ticks: Int) -> Int {
  if ticks <= 0 {
    return 0;
  }
  let rate = _defi_clamp_bps(rate_bps);
  if rate <= 0 || p.supply_index <= 0 || p.borrow_index <= 0 {
    return 0;
  }
  let reserve_factor = _defi_clamp_bps(p.reserve_bps);
  var total_interest = 0;
  var i = 0;
  while i < ticks {
    let old_index = p.borrow_index;
    let new_index = _defi_mul_sat(old_index, DEFI_SCALE + rate) / DEFI_SCALE;
    let delta = new_index - old_index;
    if delta > 0 {
      let borrow_interest = _defi_mul_sat(p.borrow_shares, delta) / DEFI_SCALE;
      let reserve_cut = _defi_mul_sat(borrow_interest, reserve_factor) / DEFI_SCALE;
      let supply_interest = borrow_interest - reserve_cut;
      if supply_interest > 0 && p.supply_shares > 0 {
        let per_share = _defi_mul_sat(supply_interest, DEFI_SCALE) / p.supply_shares;
        p.supply_index = _defi_add_sat(p.supply_index, per_share);
        total_interest = total_interest + supply_interest;
      }
      p.borrow_index = new_index;
    }
    i = i + 1;
  }
  return total_interest;
}

/// Collateral ratio in parts per 10000: floor(collateral * 10000 / debt).
/// Values above 10000 mean overcollateralized. A non-positive debt returns
/// core.INT_MAX (infinitely healthy); a non-positive collateral with positive
/// debt returns 0.
/// Params: collateral - collateral value; debt - debt value (same units).
/// Returns: the ratio in parts per 10000.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_collateral_ratio_bps(collateral: Int, debt: Int) -> Int {
  if debt <= 0 {
    return core.INT_MAX;
  }
  if collateral <= 0 {
    return 0;
  }
  return _defi_mul_sat(collateral, DEFI_SCALE) / debt;
}

/// Health factor in parts per 10000:
/// floor(collateral * threshold_bps / debt). 1.0 (DEFI_SCALE) is the
/// liquidation boundary; below it the position is liquidatable. A
/// non-positive debt returns core.INT_MAX; a non-positive collateral with
/// positive debt returns 0.
/// Params: collateral - collateral value; debt - debt value (same units);
///         threshold_bps - liquidation threshold in parts per 10000.
/// Returns: the health factor.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_health_factor_bps(collateral: Int, debt: Int, threshold_bps: Int) -> Int {
  if debt <= 0 {
    return core.INT_MAX;
  }
  if collateral <= 0 {
    return 0;
  }
  return _defi_mul_sat(collateral, _defi_clamp_bps(threshold_bps)) / debt;
}

/// True when a health factor is strictly below 1.0.
/// Params: health_factor_bps - health factor in parts per 10000.
/// Returns: true when the position is liquidatable.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_is_liquidatable(health_factor_bps: Int) -> Bool {
  return health_factor_bps < DEFI_SCALE;
}

/// Liquidation repayment and seizure for a position.
/// `repay = floor(debt * close_factor_bps / 10000)` is capped by the close
/// factor; `seize = ceil(repay * (10000 + bonus_bps) / 10000)` adds the
/// liquidation bonus and rounds up (favoring the protocol), then is capped
/// at `collateral` so a liquidation can never seize more than is posted.
/// Params: debt - position debt; collateral - position collateral (same
///         units); close_factor_bps - maximum repaid fraction per call in
///         parts per 10000; bonus_bps - liquidation bonus in parts per
///         10000.
/// Returns: (repay, seize); (0, 0) when debt or collateral is non-positive
///          or the repayment truncates to 0.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_liquidation_amounts(debt: Int, collateral: Int, close_factor_bps: Int, bonus_bps: Int) -> (Int, Int) {
  if debt <= 0 || collateral <= 0 {
    return (0, 0);
  }
  let close_factor = _defi_clamp_bps(close_factor_bps);
  let bonus = _defi_clamp_bps(bonus_bps);
  let repay = _defi_mul_sat(debt, close_factor) / DEFI_SCALE;
  if repay <= 0 {
    return (0, 0);
  }
  var seize = _defi_ceil_div(_defi_mul_sat(repay, DEFI_SCALE + bonus), DEFI_SCALE);
  if seize > collateral {
    seize = collateral;
  }
  return (repay, seize);
}

/// Index monotonicity invariant: both indexes must be at least their
/// recorded earlier values.
/// Params: p - the pool; supply_index_before, borrow_index_before - indexes
///         recorded before an accrual.
/// Returns: true when supply_index >= supply_index_before and
///          borrow_index >= borrow_index_before.
/// Error case: none.
/// Complexity: O(1).
pub fn lend_check_indexes(p: &LendPool, supply_index_before: Int, borrow_index_before: Int) -> Bool {
  let supply_ok = p.supply_index >= supply_index_before;
  let borrow_ok = p.borrow_index >= borrow_index_before;
  return supply_ok && borrow_ok;
}
