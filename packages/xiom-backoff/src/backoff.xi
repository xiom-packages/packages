// XIOM -- xiom.backoff: deterministic backoff policies and retry state
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no sleeping, no clock.
//
// Two building blocks:
//   * BackoffPolicy -- constant, linear and exponential delay growth with an
//     optional cap and optional jitter, computed with integer arithmetic;
//   * RetryState -- a small state machine over a policy snapshot (attempt
//     counter, cap, remaining).
//
// The package never sleeps and never reads a clock: a caller asks for the
// delay of attempt N (and, for jitter, passes a deterministic unit in
// [0, 10000) from its own random source). Every function is therefore a pure
// function of its arguments, which is what the conformance suite pins.
//
// Arithmetic rules: delay values saturate at BACKOFF_MAX_DELAY_MS instead of
// wrapping; the cap is applied to the raw delay before jitter; jitter modes
// are 0 = none, 1 = full (raw * unit / 10000) and 2 = equal
// (raw / 2 + raw * unit / 20000), both floored.
//
// Language notes (XIOM v0.61.3): free functions only; Result construction is
// confined to the leaf helpers _ok_int/_err_int; struct values use field
// literals.

module xiom.backoff

use xiom.string;
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

// --------------------------------------------------
//  Constants and data model
// --------------------------------------------------

// Saturation bound for every computed delay (1000000000000 ms).
const _BACKOFF_MAX: Int = 1000000000000;

// Jitter scale: a jitter unit is an integer in [0, 10000).
const _BACKOFF_SCALE: Int = 10000;

/// A backoff policy.
/// kind selects the growth shape: 0 = constant, 1 = linear, 2 = exponential.
/// base_ms is the delay of attempt 1 (after clamping, >= 0); step_ms is the
/// linear increment per attempt; factor_num / factor_den is the exponential
/// growth ratio; cap_ms bounds the raw delay (-1 = uncapped); jitter is the
/// mode (0 = none, 1 = full, 2 = equal). All fields are public; use the
/// backoff_* constructors for validated values.
pub type BackoffPolicy = {
  kind: Int;
  base_ms: Int;
  step_ms: Int;
  factor_num: Int;
  factor_den: Int;
  cap_ms: Int;
  jitter: Int;
}

/// A retry state machine: a snapshot of the policy plus the attempt budget.
/// `used` counts attempts handed out by retry_next; the state is exhausted
/// when `used >= max_attempts`. retry_reset restores the initial state.
pub type RetryState = {
  kind: Int;
  base_ms: Int;
  step_ms: Int;
  factor_num: Int;
  factor_den: Int;
  cap_ms: Int;
  jitter: Int;
  max_attempts: Int;
  used: Int;
}

// --------------------------------------------------
//  Policy construction
// --------------------------------------------------

// Largest of 0 and `v`, for non-negative clamps.
fn _at_least_zero(v: Int) -> Int {
  if v < 0 {
    return 0;
  }
  return v;
}

// At least 1, for factor clamps.
fn _at_least_one(v: Int) -> Int {
  if v < 1 {
    return 1;
  }
  return v;
}

/// A constant policy: every attempt waits `delay_ms` (negative delays are
/// clamped to 0), with no cap and no jitter.
/// Params: delay_ms - the fixed delay.
/// Returns: the policy.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_constant(delay_ms: Int) -> BackoffPolicy
  ensures: backoff_kind(result) == 0;
  ensures: delay_ms >= 0 => backoff_base(result) == delay_ms;
  ensures: delay_ms < 0 => backoff_base(result) == 0;
{
  return BackoffPolicy{
    kind: 0;
    base_ms: _at_least_zero(delay_ms);
    step_ms: 0;
    factor_num: 1;
    factor_den: 1;
    cap_ms: -1;
    jitter: 0;
  };
}

/// A linear policy: attempt N waits base + step * (N - 1).
/// Params: first_ms - the attempt-1 delay (clamped to >= 0); step_ms - the
/// increment per attempt (clamped to >= 0); cap_ms - the raw-delay cap, or
/// any negative value for uncapped.
/// Returns: the policy with no jitter.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_linear(first_ms: Int, step_ms: Int, cap_ms: Int) -> BackoffPolicy
  ensures: backoff_kind(result) == 1;
  ensures: first_ms >= 0 => backoff_base(result) == first_ms;
  ensures: backoff_cap_ms(result) == cap_ms;
{
  return BackoffPolicy{
    kind: 1;
    base_ms: _at_least_zero(first_ms);
    step_ms: _at_least_zero(step_ms);
    factor_num: 1;
    factor_den: 1;
    cap_ms: cap_ms;
    jitter: 0;
  };
}

/// An exponential policy: attempt N waits base * (factor_num / factor_den)
/// to the power (N - 1), with integer truncation after each multiplication.
/// Params: first_ms - the attempt-1 delay (clamped to >= 0); factor_num -
/// the growth numerator (clamped to >= 1); factor_den - the growth
/// denominator (clamped to >= 1); cap_ms - the raw-delay cap, or any
/// negative value for uncapped.
/// Returns: the policy with no jitter.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_exponential(first_ms: Int, factor_num: Int, factor_den: Int, cap_ms: Int) -> BackoffPolicy
  ensures: backoff_kind(result) == 2;
  ensures: backoff_factor_num(result) >= 1;
  ensures: backoff_factor_den(result) >= 1;
{
  return BackoffPolicy{
    kind: 2;
    base_ms: _at_least_zero(first_ms);
    step_ms: 0;
    factor_num: _at_least_one(factor_num);
    factor_den: _at_least_one(factor_den);
    cap_ms: cap_ms;
    jitter: 0;
  };
}

/// A copy of `p` with the jitter mode set. A mode outside 0..2 is stored as
/// 0 (none); backoff_delay of a hand-built policy with an out-of-range mode
/// is an error instead.
/// Params: p - the source policy; mode - 0 none, 1 full, 2 equal.
/// Returns: the updated copy.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_with_jitter(p: &BackoffPolicy, mode: Int) -> BackoffPolicy
  ensures: mode >= 0 && mode <= 2 => backoff_jitter_mode(result) == mode;
  ensures: mode < 0 || mode > 2 => backoff_jitter_mode(result) == 0;
  ensures: backoff_kind(result) == p.kind;
{
  var m = mode;
  if m < 0 || m > 2 {
    m = 0;
  }
  return BackoffPolicy{
    kind: p.kind;
    base_ms: p.base_ms;
    step_ms: p.step_ms;
    factor_num: p.factor_num;
    factor_den: p.factor_den;
    cap_ms: p.cap_ms;
    jitter: m;
  };
}

/// A copy of `p` with a new raw-delay cap. A negative cap means uncapped.
/// Params: p - the source policy; cap_ms - the new cap.
/// Returns: the updated copy.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_with_cap(p: &BackoffPolicy, cap_ms: Int) -> BackoffPolicy
  ensures: backoff_cap_ms(result) == cap_ms;
  ensures: backoff_base(result) == p.base_ms;
  ensures: backoff_jitter_mode(result) == p.jitter;
{
  return BackoffPolicy{
    kind: p.kind;
    base_ms: p.base_ms;
    step_ms: p.step_ms;
    factor_num: p.factor_num;
    factor_den: p.factor_den;
    cap_ms: cap_ms;
    jitter: p.jitter;
  };
}

// --------------------------------------------------
//  Policy accessors
// --------------------------------------------------

/// Growth shape of the policy: 0 constant, 1 linear, 2 exponential.
/// Params: p - the policy.
/// Returns: the kind.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_kind(p: &BackoffPolicy) -> Int
  ensures: result == p.kind;
{
  let v: Int = p.kind;
  return v;
}

/// Attempt-1 delay of the policy.
/// Params: p - the policy.
/// Returns: base_ms.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_base(p: &BackoffPolicy) -> Int
  ensures: result == p.base_ms;
{
  let v: Int = p.base_ms;
  return v;
}

/// Linear increment of the policy.
/// Params: p - the policy.
/// Returns: step_ms.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_step(p: &BackoffPolicy) -> Int
  ensures: result == p.step_ms;
{
  let v: Int = p.step_ms;
  return v;
}

/// Exponential growth numerator.
/// Params: p - the policy.
/// Returns: factor_num.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_factor_num(p: &BackoffPolicy) -> Int
  ensures: result == p.factor_num;
{
  let v: Int = p.factor_num;
  return v;
}

/// Exponential growth denominator.
/// Params: p - the policy.
/// Returns: factor_den.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_factor_den(p: &BackoffPolicy) -> Int
  ensures: result == p.factor_den;
{
  let v: Int = p.factor_den;
  return v;
}

/// Raw-delay cap of the policy.
/// Params: p - the policy.
/// Returns: cap_ms; a negative value means uncapped.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_cap_ms(p: &BackoffPolicy) -> Int
  ensures: result == p.cap_ms;
{
  let v: Int = p.cap_ms;
  return v;
}

/// Jitter mode of the policy: 0 none, 1 full, 2 equal.
/// Params: p - the policy.
/// Returns: the mode.
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_jitter_mode(p: &BackoffPolicy) -> Int
  ensures: result == p.jitter;
{
  let v: Int = p.jitter;
  return v;
}

/// Saturation bound for every computed delay.
/// Params: none.
/// Returns: 1000000000000 (ms).
/// Error case: none.
/// Complexity: O(1).
pub fn backoff_max_delay() -> Int
  ensures: result == 1000000000000;
{
  return _BACKOFF_MAX;
}

// --------------------------------------------------
//  Delay computation
// --------------------------------------------------

// a + b, saturating at _BACKOFF_MAX. Both arguments must be >= 0.
fn _saturating_add(a: Int, b: Int) -> Int {
  if a > _BACKOFF_MAX - b {
    return _BACKOFF_MAX;
  }
  return a + b;
}

// a * b, saturating at _BACKOFF_MAX. Both arguments must be >= 0.
fn _saturating_mul(a: Int, b: Int) -> Int {
  if a == 0 || b == 0 {
    return 0;
  }
  if a > _BACKOFF_MAX / b {
    return _BACKOFF_MAX;
  }
  return a * b;
}

// Raw delay (before jitter and cap) of `attempt` under a validated policy.
fn _raw_delay(p: &BackoffPolicy, attempt: Int) -> Int {
  let kind: Int = p.kind;
  let base: Int = p.base_ms;
  if kind == 0 {
    return base;
  }
  if kind == 1 {
    let step: Int = p.step_ms;
    let span = _saturating_mul(step, attempt - 1);
    return _saturating_add(base, span);
  }
  let fnum: Int = p.factor_num;
  let fden: Int = p.factor_den;
  var v = base;
  var k = 1;
  while k < attempt {
    if v > _BACKOFF_MAX / fnum {
      return _BACKOFF_MAX;
    }
    v = v * fnum / fden;
    k = k + 1;
  }
  return v;
}

// Shared delay pipeline. Validates attempt, jitter unit and jitter mode,
// then applies growth, cap and jitter in that order.
fn _delay(p: &BackoffPolicy, attempt: Int, jitter_unit: Int) -> Result[Int, Str] {
  if attempt < 1 {
    return _err_int("backoff: bad attempt " + int_to_string(attempt));
  }
  if jitter_unit < 0 || jitter_unit >= _BACKOFF_SCALE {
    return _err_int("backoff: bad jitter unit " + int_to_string(jitter_unit));
  }
  let jitter: Int = p.jitter;
  if jitter < 0 || jitter > 2 {
    return _err_int("backoff: bad jitter mode " + int_to_string(jitter));
  }
  var d = _raw_delay(p, attempt);
  let cap: Int = p.cap_ms;
  if cap >= 0 && d > cap {
    d = cap;
  }
  if jitter == 1 {
    d = d * jitter_unit / _BACKOFF_SCALE;
  } elif jitter == 2 {
    d = d / 2 + d * jitter_unit / (2 * _BACKOFF_SCALE);
  }
  return _ok_int(d);
}

/// Raw delay of attempt `attempt`, before the cap and before jitter.
/// Params: p - the policy; attempt - the 1-based attempt number.
/// Returns: Ok(delay) computed by the policy's growth rule, saturated at
/// backoff_max_delay(). Negative constructor inputs were already clamped.
/// Error case: Err("backoff: bad attempt <n>") when `attempt < 1`.
/// Complexity: O(attempt) for exponential policies, O(1) otherwise.
pub fn backoff_raw_delay(p: &BackoffPolicy, attempt: Int) -> Result[Int, Str]
  ensures: attempt < 1 => result is Err;
  ensures: attempt >= 1 => result is Ok;
{
  if attempt < 1 {
    return _err_int("backoff: bad attempt " + int_to_string(attempt));
  }
  return _ok_int(_raw_delay(p, attempt));
}

/// Delay of attempt `attempt` with the policy's cap and jitter applied.
/// Params: p - the policy; attempt - the 1-based attempt number;
/// jitter_unit - a deterministic unit in [0, 10000) from the caller's random
/// source (ignored when the policy has no jitter).
/// Returns: Ok(delay) in [0, cap] (or [0, backoff_max_delay()] when
/// uncapped). The cap bounds the raw delay first; jitter then scales it
/// down with floor division, so the result never exceeds the capped raw
/// delay.
/// Error case: Err("backoff: bad attempt <n>") for `attempt < 1`;
/// Err("backoff: bad jitter unit <n>") for a unit outside [0, 10000);
/// Err("backoff: bad jitter mode <m>") when the policy carries a mode
/// outside 0..2.
/// Complexity: O(attempt) for exponential policies, O(1) otherwise.
pub fn backoff_delay(p: &BackoffPolicy, attempt: Int, jitter_unit: Int) -> Result[Int, Str]
  ensures: attempt < 1 => result is Err;
  ensures: p.jitter < 0 || p.jitter > 2 => result is Err;
  ensures: result is Ok && p.cap_ms >= 0 && p.jitter == 0 => result.value <= p.cap_ms;
{
  return _delay(p, attempt, jitter_unit);
}

// --------------------------------------------------
//  Retry state machine
// --------------------------------------------------

/// A retry state over a snapshot of `p` with an attempt budget.
/// Params: p - the policy to snapshot; max_attempts - the number of delays
/// the state may hand out (clamped to >= 0; 0 is immediately exhausted).
/// Returns: the state with `used = 0`.
/// Error case: none.
/// Complexity: O(1).
pub fn retry_new(p: &BackoffPolicy, max_attempts: Int) -> RetryState
  ensures: max_attempts >= 0 => retry_max_attempts(result) == max_attempts;
  ensures: max_attempts < 0 => retry_max_attempts(result) == 0;
  ensures: retry_used(result) == 0;
{
  var cap = max_attempts;
  if cap < 0 {
    cap = 0;
  }
  return RetryState{
    kind: p.kind;
    base_ms: p.base_ms;
    step_ms: p.step_ms;
    factor_num: p.factor_num;
    factor_den: p.factor_den;
    cap_ms: p.cap_ms;
    jitter: p.jitter;
    max_attempts: cap;
    used: 0;
  };
}

// Rebuild the snapshotted policy of a state.
fn _state_policy(s: &RetryState) -> BackoffPolicy {
  return BackoffPolicy{
    kind: s.kind;
    base_ms: s.base_ms;
    step_ms: s.step_ms;
    factor_num: s.factor_num;
    factor_den: s.factor_den;
    cap_ms: s.cap_ms;
    jitter: s.jitter;
  };
}

/// Delay for the next attempt and consume one attempt from the budget.
/// Params: s - the state; jitter_unit - a deterministic jitter unit in
/// [0, 10000).
/// Returns: Ok(delay) for attempt `used + 1`, exactly like backoff_delay on
/// the snapshotted policy; `used` grows by 1 on success.
/// Error case: Err("backoff: attempts exhausted") when `used` already
/// equals `max_attempts` (the state is not modified); the backoff_delay
/// errors for a bad jitter unit or mode (also without consuming).
/// Complexity: O(used) for exponential policies, O(1) otherwise.
pub fn retry_next(s: &mut RetryState, jitter_unit: Int) -> Result[Int, Str]
  ensures: s.used@pre >= s.max_attempts@pre => result is Err;
  ensures: result is Ok => s.used == s.used@pre + 1;
  ensures: result is Err => s.used == s.used@pre;
{
  let used: Int = s.used;
  let max: Int = s.max_attempts;
  if used >= max {
    return _err_int("backoff: attempts exhausted");
  }
  let p = _state_policy(s);
  let r = _delay(&p, used + 1, jitter_unit);
  match r {
    Ok(d) => {
      s.used = used + 1;
      return _ok_int(d);
    },
    Err(e) => { return _err_int(e); },
  }
  return _err_int("backoff: attempts exhausted");
}

/// Reset the attempt counter of `s` to 0 (the budget is unchanged).
/// Params: s - the state to reset.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn retry_reset(s: &mut RetryState)
  ensures: s.used == 0;
  ensures: s.max_attempts == s.max_attempts@pre;
{
  s.used = 0;
}

/// Number of attempts already handed out.
/// Params: s - the state.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn retry_used(s: &RetryState) -> Int
  ensures: result == s.used;
{
  let v: Int = s.used;
  return v;
}

/// Number of attempts still available.
/// Params: s - the state.
/// Returns: max_attempts - used (never negative).
/// Error case: none.
/// Complexity: O(1).
pub fn retry_remaining(s: &RetryState) -> Int
  ensures: s.max_attempts - s.used >= 0 => result == s.max_attempts - s.used;
  ensures: s.max_attempts - s.used < 0 => result == 0;
  ensures: result >= 0;
{
  let v: Int = s.max_attempts - s.used;
  if v < 0 {
    return 0;
  }
  return v;
}

/// Attempt budget of the state.
/// Params: s - the state.
/// Returns: max_attempts.
/// Error case: none.
/// Complexity: O(1).
pub fn retry_max_attempts(s: &RetryState) -> Int
  ensures: result == s.max_attempts;
{
  let v: Int = s.max_attempts;
  return v;
}

/// True when no attempt is left.
/// Params: s - the state.
/// Returns: the flag (`used >= max_attempts`).
/// Error case: none.
/// Complexity: O(1).
pub fn retry_exhausted(s: &RetryState) -> Bool
  ensures: result => s.used >= s.max_attempts;
  ensures: s.used < s.max_attempts => !result;
{
  let used: Int = s.used;
  let max: Int = s.max_attempts;
  return used >= max;
}
