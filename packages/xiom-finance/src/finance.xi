// Port task: pure-XIOM xiom.finance -- integer time-value-of-money: simple
// and compound interest, APY, annuity payments, total interest, NPV and a
// rule-of-72 doubling indicator. All money is in cents, all rates are in
// permille (1% = 10 permille); there is no floating point and no FFI.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Rounding convention for the whole module: every division uses the native
// Int `/`, which truncates toward zero -- positive magnitudes round down,
// negative magnitudes round up (toward zero). Each truncation point is
// documented per function and pinned by tests; no other rounding mode (half
// up, banker's, floor) is offered. Free functions only -- XIOM v0.61.x has
// no methods; Vec[Int] element reads are copied into typed let bindings
// because untyped indexed reads mis-lower in v0.61.3.

module xiom.finance

// --- internal helpers -------------------------------------------------------

// ceil(a / b) for b > 0. The native Int `/` truncates toward zero, so for
// a > 0 a non-zero remainder is one below the ceiling, while for a <= 0
// truncation is already the ceiling (e.g. -7/2 = -3 = ceil(-3.5)). Never
// called with b <= 0 from the public API.
fn _finance_ceil_div(a: Int, b: Int) -> Int {
  var q = a / b;
  if a > 0 {
    if a % b != 0 {
      q = q + 1;
    }
  }
  return q;
}

// --- public API -------------------------------------------------------------

/// Simple (non-compounding) interest in cents.
/// Formula: principal_cents * rate_permille * periods / 1000, evaluated as
/// one product and one division that truncates toward zero. Negative
/// principal, negative rate and non-positive periods are all accepted; a
/// non-positive `periods` makes the product 0.
/// Params: principal_cents - principal in cents; rate_permille - simple rate
///         per period in permille (1% = 10); periods - number of periods.
/// Returns: interest in cents (negative for a negative rate or principal).
/// Complexity: O(1).
pub fn finance_simple_interest_cents(principal_cents: Int, rate_permille: Int, periods: Int) -> Int {
  return principal_cents * rate_permille * periods / 1000;
}

/// Compound interest in cents, compounded once per period.
/// Recurrence applied `periods` times, each step truncated toward zero before
/// the next step sees the value:
///   p = p * (1000 + rate_permille) / 1000
/// Truncation therefore compounds: 333 cents at 50 permille for 2 periods is
/// 349 then 366 (the untruncated balance would be 367.08...). A `periods`
/// below 1 returns the principal unchanged.
/// Params: principal_cents - starting principal in cents;
///         rate_permille - rate per compounding period in permille;
///         periods - number of compounding periods.
/// Returns: ending balance in cents.
/// Complexity: O(periods).
pub fn finance_compound_cents(principal_cents: Int, rate_permille: Int, periods: Int) -> Int {
  var p = principal_cents;
  var i = 0;
  while i < periods {
    p = p * (1000 + rate_permille) / 1000;
    i = i + 1;
  }
  return p;
}

/// Effective annual rate (APY) in permille from a nominal annual rate.
/// The nominal rate is spread over `periods_per_year` compounding periods
/// inside the scaled growth iteration, so the per-period factor is exactly
/// (1000*m + nominal) / (1000*m) with m = max(1, periods_per_year) before
/// truncation. The growth factor is tracked in millionths (1000000 = 1.0)
/// so per-period truncation stays negligible; each of the m periods and the
/// final permille conversion truncate toward zero:
///   growth = 1000000
///   growth = growth * (1000*m + nominal) / (1000*m)   (m times)
///   apy    = (growth - 1000000) / 1000
/// Annual compounding (m == 1) returns the nominal rate exactly. If the
/// per-period factor would be non-positive (nominal <= -1000*m permille),
/// growth is clamped to total loss and -1000 is returned.
/// Params: nominal_permille - nominal annual rate in permille;
///         periods_per_year - compounding periods per year (clamped to >= 1).
/// Returns: effective annual rate in permille.
/// Complexity: O(periods_per_year).
pub fn finance_apy_permille(nominal_permille: Int, periods_per_year: Int) -> Int {
  var m = periods_per_year;
  if m < 1 {
    m = 1;
  }
  let denom = 1000 * m + nominal_permille;
  if denom <= 0 {
    return -1000;
  }
  var growth: Int = 1000000;
  var i = 0;
  while i < m {
    growth = growth * denom / (1000 * m);
    i = i + 1;
  }
  return (growth - 1000000) / 1000;
}

/// Annuity payment in cents for a fully amortizing loan (payment due at the
/// end of every period). The annuity factor a = sum over k = 1..periods of
/// (1000/(1000 + rate_permille))^k is built by scaled integer iteration in
/// millionths -- factor starts at 1000000 and each period:
///   factor = factor * 1000 / (1000 + rate_permille)
///   accum  = accum + factor
/// with every step truncated toward zero. The payment is then
///   principal_cents * 1000000 / accum
/// also truncated toward zero. `periods <= 0` returns 0. `rate_permille == 0`
/// returns ceil(principal_cents / periods) (truncation toward zero is the
/// ceiling for negative principals). `rate_permille <= -1000` returns 0: at
/// or beyond -100% per period the annuity factor diverges.
/// Params: principal_cents - loan principal in cents; rate_permille - rate
///         per period in permille; periods - number of payments.
/// Returns: level payment in cents (0 for periods <= 0).
/// Complexity: O(periods).
pub fn finance_payment_cents(principal_cents: Int, rate_permille: Int, periods: Int) -> Int {
  if periods <= 0 {
    return 0;
  }
  if rate_permille == 0 {
    return _finance_ceil_div(principal_cents, periods);
  }
  if rate_permille <= -1000 {
    return 0;
  }
  let scale: Int = 1000000;
  var factor: Int = scale;
  var accum: Int = 0;
  var i = 0;
  while i < periods {
    factor = factor * 1000 / (1000 + rate_permille);
    accum = accum + factor;
    i = i + 1;
  }
  return principal_cents * scale / accum;
}

/// Total interest paid over the life of the annuity: the payment times the
/// number of periods minus the principal, clamped to a minimum of 0 (payment
/// rounding and negative rates can otherwise make it negative). At
/// rate_permille == 0 the exact result is only the payment-rounding excess
/// (e.g. 100000 cents over 3 periods pays 33334 * 3 = 100002, so 2 cents).
/// Params: principal_cents - loan principal in cents; rate_permille - rate
///         per period in permille; periods - number of payments.
/// Returns: total interest in cents, never negative.
/// Complexity: O(periods).
pub fn finance_total_interest_cents(principal_cents: Int, rate_permille: Int, periods: Int) -> Int {
  let payment = finance_payment_cents(principal_cents, rate_permille, periods);
  var total = payment * periods - principal_cents;
  if total < 0 {
    return 0;
  }
  return total;
}

/// Net present value of a flow series in cents at a per-period rate.
/// flow[0] is undiscounted; for each flow the permille discount factor
/// (1000 = 1.0) is applied and then advanced one period:
///   discounted = flow[i] * factor / 1000
///   total      = total + discounted
///   factor     = factor * 1000 / (1000 + rate_permille)
/// Every division truncates toward zero, so each contribution is truncated
/// before it is summed. Rates below -1000 permille are clamped so the
/// divisor is at least 1 (the factor then grows by 1000x per period).
/// An empty series returns 0; at rate 0 the result is exactly the sum.
/// Params: rate_permille - discount rate per period in permille;
///         flows - cash flows by period (index 0 = period 0).
/// Returns: net present value in cents.
/// Complexity: O(flows.len()).
pub fn finance_npv_cents(rate_permille: Int, flows: &Vec[Int]) -> Int {
  var divisor = 1000 + rate_permille;
  if divisor < 1 {
    divisor = 1;
  }
  var factor: Int = 1000;
  var total: Int = 0;
  let n = flows.len();
  var i = 0;
  while i < n {
    let flow: Int = flows[i];
    let discounted = flow * factor / 1000;
    total = total + discounted;
    factor = factor * 1000 / divisor;
    i = i + 1;
  }
  return total;
}

/// Rule-of-72 doubling indicator in periods.
/// Formula: ceil(72000 / rate_permille) for rate_permille > 0, computed by
/// ceiling division so the result never underestimates; rate_permille <= 0
/// returns -1 (compounding never doubles). The ceiling is observable:
/// 70 permille gives 1029 periods (72000/70 = 1028.57...), 100 permille gives
/// exactly 720.
/// Params: rate_permille - rate per period in permille.
/// Returns: periods to double, or -1 for a non-positive rate.
/// Complexity: O(1).
pub fn finance_rule_of_72_periods(rate_permille: Int) -> Int {
  if rate_permille <= 0 {
    return -1;
  }
  return _finance_ceil_div(72000, rate_permille);
}
