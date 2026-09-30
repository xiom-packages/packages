// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.stats-tests: exact integer statistics with curated p-value
// buckets. Port task: replace the xiom.stats-tests placeholder with a pure
// XIOM module (scaled integers only: no floats, no FFI, no I/O).
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - Fixed point: every non-integer quantity is an Int in units of 1e-4
//     (10000 = 1.0). Ranks are exact multiples of 5000 (average-tie ranks),
//     so 15000 is rank 1.5. Divisions round halves away from zero at the
//     documented final step only; exact integer statistics (rank sums, U,
//     chi-square numerator/denominator, counts) are the primary output.
//   - Ranks: 1-based average ranks with tie handling, scaled 1e-4.
//   - Wilcoxon rank-sum (Mann-Whitney) U: average-tie ranks over the pooled
//     sample; p-values bucketed from an exact two-sided critical-value table
//     for sample sizes 2..8, derived from the exact permutation distribution
//     (see SPEC.md section 6).
//   - Chi-square goodness-of-fit and independence against integer expected
//     counts: the statistic is returned as an exact rational num/den in
//     lowest terms plus the scaled value; p-values bucketed from the
//     standard upper-tail critical values for df 1..10, stored scaled 1e-4.
//   - Sign test: counts of positive / negative differences (zeros dropped);
//     p-values bucketed from the exact two-sided binomial table n = 1..20.
//   - Permutation test: caller-seeded MINSTD LCG (48271, 2^31 - 1),
//     Fisher-Yates shuffle, |mean difference| in fixed point; the p-bucket
//     comes from the exact extreme/n_perm rational.
//
// v0.62.1 notes that shaped this module:
//   * Ok/Err construction is confined to the leaf helpers at the bottom.
//   * every Vec[Int] element read binds the element to a typed local first.
//   * free functions only: no methods, generics, callbacks, indexed
//     function-table dispatch or Vec[StructType]; structs carry Int fields.
//   * Int division truncates toward zero; every rounding step is explicit
//     via _div_round (halves away from zero).
//   * no function is named after a builtin; no mixed Vec<...> brackets.

module xiom.stats_tests

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Fixed-point scale: 10000 units = 1.0.
const _ST_SCALE: Int = 10000;
// Half of the scale: average-tie rank increments.
const _ST_HALF: Int = 5000;
const _ST_INT_MAX: Int = 9223372036854775807;
// Largest sample length whose rank scale n(n+1)/2 * 10000 fits in Int.
const _ST_MAX_SAMPLE: Int = 40000000;
// floor(sqrt(Int_max)): products above this square overflow when doubled.
const _ST_SQRT_MAX: Int = 3037000499;
// Largest |group sum| whose *10000 scaling fits in Int.
const _ST_SUM_LIMIT: Int = 922337203685477;
// floor(Int_max / 1000): permutation counts up to this admit the bucket
// multiplications extreme * 1000.
const _ST_PERM_LIMIT: Int = 9223372036854775;
const _ST_WILCOXON_MIN_N: Int = 2;
const _ST_WILCOXON_MAX_N: Int = 8;
const _ST_SIGN_MAX_N: Int = 20;
const _ST_CHI2_MAX_DF: Int = 10;
// MINSTD (Park-Miller) LCG: state = (state * 48271) mod (2^31 - 1).
const _ST_LCG_MULT: Int = 48271;
const _ST_LCG_MOD: Int = 2147483647;
const _ST_LCG_RANGE: Int = 2147483646;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// Wilcoxon rank-sum (Mann-Whitney) result.
///
/// `rank_sum_a` / `rank_sum_b` are the scaled rank sums of the two groups
/// over the pooled sample (1e-4 units); `u_a` / `u_b` are the corresponding
/// scaled U statistics, with u_a + u_b == n_a * n_b * 10000 exactly.
/// `p_bucket` is the two-sided bucket of min(u_a, u_b) from the curated
/// table (section 6 of SPEC.md). Fields are implementation detail; use the
/// stats_tests_wilcoxon_* accessors.
pub type WilcoxonResult = {
  u_a: Int;
  u_b: Int;
  rank_sum_a: Int;
  rank_sum_b: Int;
  n_a: Int;
  n_b: Int;
  p_bucket: Int;
}

/// Chi-square result: the statistic is the exact rational `num / den` in
/// lowest terms (den > 0), `scaled` is round_half_away(10000 * num / den),
/// `df` is the degrees of freedom and `p_bucket` the upper-tail bucket from
/// the standard critical values (section 7 of SPEC.md).
pub type ChiSquareResult = {
  num: Int;
  den: Int;
  scaled: Int;
  df: Int;
  p_bucket: Int;
}

/// Sign-test result: counts of positive, negative and zero differences;
/// `stat` is min(n_plus, n_minus); `p_bucket` is the two-sided binomial
/// bucket for `stat` out of `n_plus + n_minus` nonzero differences.
pub type SignTestResult = {
  n_plus: Int;
  n_minus: Int;
  n_zero: Int;
  stat: Int;
  p_bucket: Int;
}

/// Permutation-test result: `observed_diff` is the scaled mean difference
/// (group A minus group B, each mean rounded half away from zero),
/// `extreme` counts the permutations whose |difference| is at least the
/// observed one, and `p_bucket` buckets the exact extreme/n_perm ratio.
pub type PermutationResult = {
  observed_diff: Int;
  extreme: Int;
  n_perm: Int;
  p_bucket: Int;
}

// ---------------------------------------------------------------------------
// Scale and generator constants
// ---------------------------------------------------------------------------

/// Fixed-point scale (10000; 1.0 = 10000). Complexity: O(1).
pub fn stats_tests_scale() -> Int {
  return _ST_SCALE;
}

/// Bucket code for "not significant at 0.05" (0). Complexity: O(1).
pub fn stats_tests_p_bucket_not_significant() -> Int {
  return 0;
}

/// Bucket code for "p < 0.05" (1). Complexity: O(1).
pub fn stats_tests_p_bucket_05() -> Int {
  return 1;
}

/// Bucket code for "p < 0.01" (2). Complexity: O(1).
pub fn stats_tests_p_bucket_01() -> Int {
  return 2;
}

/// Bucket code for "p < 0.001" (3). Complexity: O(1).
pub fn stats_tests_p_bucket_001() -> Int {
  return 3;
}

/// Bucket code for "outside the curated table" (-1). Complexity: O(1).
pub fn stats_tests_p_bucket_unknown() -> Int {
  return -1;
}

/// True when a bucket code denotes significance at some level (>= 1).
/// Complexity: O(1).
pub fn stats_tests_is_significant(bucket: Int) -> Bool {
  return bucket >= 1;
}

/// Multiplier of the permutation LCG (48271). Complexity: O(1).
pub fn stats_tests_lcg_multiplier() -> Int {
  return _ST_LCG_MULT;
}

/// Modulus of the permutation LCG (2147483647 = 2^31 - 1). Complexity: O(1).
pub fn stats_tests_lcg_modulus() -> Int {
  return _ST_LCG_MOD;
}

/// One normalized MINSTD LCG step (KAT-friendly).
///
/// The state is normalized to [1, 2147483646] first, then advanced to
/// (state * 48271) mod 2147483647; the result is never 0. Seeds are
/// normalized by |seed mod 2147483646| + 1 (0 maps to 1, and a seed and its
/// negation produce the same stream). Complexity: O(1).
pub fn stats_tests_lcg_step(state: Int) -> Int {
  let s = _norm_lcg_state(state);
  return (s * _ST_LCG_MULT) % _ST_LCG_MOD;
}

// ---------------------------------------------------------------------------
// Ranks
// ---------------------------------------------------------------------------

/// Average-tie ranks of `values`, scaled 1e-4, in input order.
///
/// Rank r(v) = (#values strictly less than v) + (#values equal to v + 1)/2,
/// 1-based; a group of k tied values at positions p..p+k-1 receives the
/// common rank p + (k-1)/2. The scaled value is exact:
/// less * 10000 + (equal + 1) * 5000, so half-integer ranks land on
/// multiples of 5000 (rank 1.5 -> 15000). Empty input yields Ok(empty).
/// Params: values - the sample (read only).
/// Error case: Err("stats-tests: sample too large for the rank scale") when
/// the length exceeds 40000000 (the scaled rank sum would overflow Int).
/// Complexity: O(n^2).
pub fn stats_tests_ranks(values: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = values.len();
  if n > _ST_MAX_SAMPLE {
    return _err_ranks("stats-tests: sample too large for the rank scale");
  }
  let out = _ranks_vec(values);
  return _ok_ranks(out);
}

// ---------------------------------------------------------------------------
// Wilcoxon rank-sum (Mann-Whitney) U
// ---------------------------------------------------------------------------

/// Wilcoxon rank-sum (Mann-Whitney) U over two independent samples.
///
/// Params: a, b - the two samples (read only), each non-empty.
/// Returns: Ok(WilcoxonResult) with the scaled rank sums over the pooled
/// sample and both U statistics:
///   rank_sum_a = sum of scaled average ranks of a's entries in the pooled
///                sample (exact with ties);
///   u_a        = rank_sum_a - 10000 * n_a * (n_a + 1) / 2 (scaled);
///   u_b        = n_a * n_b * 10000 - u_a.
/// Ties: average ranks (documented in stats_tests_ranks); the U identity
/// u_a + u_b = n_a * n_b * 10000 holds exactly even with ties.
/// `p_bucket` is the two-sided bucket of min(u_a, u_b) from the curated
/// table (sample sizes 2..8, section 6 of SPEC.md).
/// Error case: Err("stats-tests: group A must not be empty" / "group B must
/// not be empty") and Err("stats-tests: pooled sample too large for the rank
/// scale") when n_a + n_b exceeds 40000000.
/// Complexity: O((n_a + n_b)^2).
pub fn stats_tests_wilcoxon_u(a: &Vec[Int], b: &Vec[Int]) -> Result[WilcoxonResult, Str] {
  let na = a.len();
  let nb = b.len();
  if na <= 0 {
    return _err_wilcoxon("stats-tests: group A must not be empty");
  }
  if nb <= 0 {
    return _err_wilcoxon("stats-tests: group B must not be empty");
  }
  if na + nb > _ST_MAX_SAMPLE {
    return _err_wilcoxon("stats-tests: pooled sample too large for the rank scale");
  }
  var pooled = Vec[Int].new();
  var i = 0;
  while i < na {
    let x: Int = a[i];
    pooled.push(x);
    i = i + 1;
  }
  i = 0;
  while i < nb {
    let x: Int = b[i];
    pooled.push(x);
    i = i + 1;
  }
  let ranked = _ranks_vec(&pooled);
  var ra: Int = 0;
  i = 0;
  while i < na {
    let r: Int = ranked[i];
    ra = ra + r;
    i = i + 1;
  }
  let total = _rank_total(na + nb);
  let rb = total - ra;
  let ua = ra - _rank_total(na);
  let ub = na * nb * _ST_SCALE - ua;
  let bucket = stats_tests_wilcoxon_p_bucket(ua, na, nb);
  return _ok_wilcoxon(WilcoxonResult{ u_a: ua; u_b: ub; rank_sum_a: ra; rank_sum_b: rb; n_a: na; n_b: nb; p_bucket: bucket; });
}

/// U statistic of group A (scaled 1e-4). Complexity: O(1).
pub fn stats_tests_wilcoxon_u_a(result: &WilcoxonResult) -> Int {
  return result.u_a;
}

/// U statistic of group B (scaled 1e-4). Complexity: O(1).
pub fn stats_tests_wilcoxon_u_b(result: &WilcoxonResult) -> Int {
  return result.u_b;
}

/// Scaled rank sum of group A over the pooled sample. Complexity: O(1).
pub fn stats_tests_wilcoxon_rank_sum_a(result: &WilcoxonResult) -> Int {
  return result.rank_sum_a;
}

/// Scaled rank sum of group B over the pooled sample. Complexity: O(1).
pub fn stats_tests_wilcoxon_rank_sum_b(result: &WilcoxonResult) -> Int {
  return result.rank_sum_b;
}

/// Number of entries in group A. Complexity: O(1).
pub fn stats_tests_wilcoxon_n_a(result: &WilcoxonResult) -> Int {
  return result.n_a;
}

/// Number of entries in group B. Complexity: O(1).
pub fn stats_tests_wilcoxon_n_b(result: &WilcoxonResult) -> Int {
  return result.n_b;
}

/// Two-sided p-value bucket of the result. Complexity: O(1).
pub fn stats_tests_wilcoxon_p_bucket_of(result: &WilcoxonResult) -> Int {
  return result.p_bucket;
}

/// Two-sided p-value bucket for a rank-sum U statistic.
///
/// Params: u - the scaled U of the first group (any side; internally the
/// smaller of u and n_a * n_b * 10000 - u is used); n_a, n_b - the two
/// sample sizes.
/// Returns: 3 (p < 0.001), 2 (p < 0.01), 1 (p < 0.05), 0 (within the table
/// but not significant at 0.05), or -1 when n_a or n_b is outside [2, 8] or
/// u is outside [0, n_a * n_b * 10000].
/// The comparisons are exact integer tests against the curated critical
/// values (section 6 of SPEC.md): bucket >= 1 iff the smaller scaled U is at
/// most the critical value, i.e. 2 * P(U <= u) <= alpha under the exact
/// permutation distribution with average-tie handling.
/// Complexity: O(1).
pub fn stats_tests_wilcoxon_p_bucket(u: Int, n_a: Int, n_b: Int) -> Int {
  if n_a < _ST_WILCOXON_MIN_N {
    return -1;
  }
  if n_a > _ST_WILCOXON_MAX_N {
    return -1;
  }
  if n_b < _ST_WILCOXON_MIN_N {
    return -1;
  }
  if n_b > _ST_WILCOXON_MAX_N {
    return -1;
  }
  var s = n_a;
  var l = n_b;
  if s > l {
    let tmp = s;
    s = l;
    l = tmp;
  }
  let total = n_a * n_b * _ST_SCALE;
  if u < 0 {
    return -1;
  }
  if u > total {
    return -1;
  }
  let other = total - u;
  var umin = u;
  if other < umin {
    umin = other;
  }
  let pair = _wilcoxon_pair_id(s, l);
  let c05 = _wilcoxon_crit(pair, 0);
  let c01 = _wilcoxon_crit(pair, 1);
  let c001 = _wilcoxon_crit(pair, 2);
  return _bucket_smaller(umin, c05, c01, c001);
}

// ---------------------------------------------------------------------------
// Chi-square
// ---------------------------------------------------------------------------

/// Chi-square p-value bucket from a scaled statistic and degrees of freedom.
///
/// Params: chi2_scaled - the statistic in 1e-4 units (>= 0); df - degrees of
/// freedom in [1, 10].
/// Returns: 3 (p < 0.001), 2 (p < 0.01), 1 (p < 0.05), 0 (within the table
/// but not significant at 0.05), or -1 when df is outside [1, 10] or the
/// statistic is negative.
/// The decision is chi2_scaled >= critical(df, alpha), where the critical
/// values are the standard chi-square upper-tail quantiles rounded to the
/// nearest 1e-4 (section 7 of SPEC.md), so a bucket boundary sits within
/// 5e-5 of the exact quantile.
/// Complexity: O(1).
pub fn stats_tests_chi_square_p_bucket(chi2_scaled: Int, df: Int) -> Int {
  if df < 1 {
    return -1;
  }
  if df > _ST_CHI2_MAX_DF {
    return -1;
  }
  if chi2_scaled < 0 {
    return -1;
  }
  let c05 = _chi2_crit(df, 0);
  let c01 = _chi2_crit(df, 1);
  let c001 = _chi2_crit(df, 2);
  if chi2_scaled >= c001 {
    return 3;
  }
  if chi2_scaled >= c01 {
    return 2;
  }
  if chi2_scaled >= c05 {
    return 1;
  }
  return 0;
}

/// Chi-square goodness-of-fit statistic against integer expected counts.
///
/// Computes chi2 = sum_i (observed[i] - expected[i])^2 / expected[i] exactly
/// as a rational: with L = lcm(expected), numerator = sum_i (o_i - e_i)^2 *
/// (L / e_i) and denominator = L; the result is reduced and `scaled` is
/// round_half_away(10000 * num / den) where num/den is the reduced rational.
/// Params: observed - the observed counts (>= 0); expected - the expected
/// counts (> 0), same length (>= 2, so df >= 1).
/// Validation order: length match, category count, then per-category
/// positivity (expected first), lcm overflow, per-category term overflow,
/// sum overflow, scale overflow.
/// Error case: Err("stats-tests: ...") for a length mismatch, fewer than two
/// categories, a non-positive expected count, a negative observed count, or
/// any overflow in the exact accumulation.
/// Complexity: O(n^2) with the Euclid gcd (n = number of categories).
pub fn stats_tests_chi_square_gof(observed: &Vec[Int], expected: &Vec[Int]) -> Result[ChiSquareResult, Str] {
  let n = observed.len();
  if n != expected.len() {
    return _err_chi2("stats-tests: observed and expected lengths differ");
  }
  if n < 2 {
    return _err_chi2("stats-tests: need at least two categories");
  }
  var l: Int = 1;
  var i = 0;
  while i < n {
    let e: Int = expected[i];
    if e <= 0 {
      return _err_chi2("stats-tests: expected counts must be positive");
    }
    let o: Int = observed[i];
    if o < 0 {
      return _err_chi2("stats-tests: observed counts must not be negative");
    }
    l = _lcm(l, e);
    if l < 0 {
      return _err_chi2("stats-tests: expected-count lcm overflows");
    }
    i = i + 1;
  }
  var num: Int = 0;
  i = 0;
  while i < n {
    let e: Int = expected[i];
    let o: Int = observed[i];
    let d = o - e;
    var ad = d;
    if ad < 0 {
      ad = 0 - ad;
    }
    if ad > _ST_SQRT_MAX {
      return _err_chi2("stats-tests: chi-square term overflows");
    }
    let dd = ad * ad;
    let f = l / e;
    if dd > _ST_INT_MAX / f {
      return _err_chi2("stats-tests: chi-square term overflows");
    }
    let term = dd * f;
    if term > _ST_INT_MAX - num {
      return _err_chi2("stats-tests: chi-square sum overflows");
    }
    num = num + term;
    i = i + 1;
  }
  let g = _gcd(num, l);
  let rnum = num / g;
  let rden = l / g;
  let scaled = _scale_rational(rnum, rden);
  if scaled < 0 {
    return _err_chi2("stats-tests: chi-square scale overflows");
  }
  let df = n - 1;
  let bucket = stats_tests_chi_square_p_bucket(scaled, df);
  return _ok_chi2(ChiSquareResult{ num: rnum; den: rden; scaled: scaled; df: df; p_bucket: bucket; });
}

/// Chi-square independence statistic over a contingency table of counts.
///
/// Computes chi2 = sum_ij (n * o_ij - r_i * c_j)^2 / (n * r_i * c_j) exactly
/// as a rational: with Lr = lcm(row totals), Lc = lcm(column totals), the
/// denominator is n * Lr * Lc and the numerator is
/// sum_ij (n * o_ij - r_i * c_j)^2 * (Lr / r_i) * (Lc / c_j); the result is
/// reduced and `scaled` is round_half_away(10000 * num / den).
/// Params: table - row-major counts (>= 0), n_rows rows and n_cols columns,
/// laid out table[i * n_cols + j]; n_rows, n_cols >= 2.
/// Validation order: row count, column count, dimensions, length, per-cell
/// non-negativity, row totals, column totals, grand total, lcms, per-cell
/// term overflow, sum overflow, scale overflow.
/// Error case: Err("stats-tests: ...") for fewer than two rows or columns,
/// a length mismatch, a negative count, a zero row or column total, or any
/// overflow in the exact accumulation.
/// Complexity: O(n_rows * n_cols) plus gcd/lcm work.
pub fn stats_tests_chi_square_independence(table: &Vec[Int], n_rows: Int, n_cols: Int) -> Result[ChiSquareResult, Str] {
  if n_rows < 2 {
    return _err_chi2("stats-tests: need at least two rows");
  }
  if n_cols < 2 {
    return _err_chi2("stats-tests: need at least two columns");
  }
  if n_rows > _ST_INT_MAX / n_cols {
    return _err_chi2("stats-tests: dimensions overflow");
  }
  if table.len() != n_rows * n_cols {
    return _err_chi2("stats-tests: table length does not match the shape");
  }
  var rows = Vec[Int].new();
  var i = 0;
  while i < n_rows {
    var s: Int = 0;
    var j = 0;
    while j < n_cols {
      let x: Int = table[i * n_cols + j];
      if x < 0 {
        return _err_chi2("stats-tests: table counts must not be negative");
      }
      if x > _ST_INT_MAX - s {
        return _err_chi2("stats-tests: row total overflows");
      }
      s = s + x;
      j = j + 1;
    }
    if s <= 0 {
      return _err_chi2("stats-tests: row totals must be positive");
    }
    rows.push(s);
    i = i + 1;
  }
  var cols = Vec[Int].new();
  var jj = 0;
  while jj < n_cols {
    var s2: Int = 0;
    var ii = 0;
    while ii < n_rows {
      let y: Int = table[ii * n_cols + jj];
      if y > _ST_INT_MAX - s2 {
        return _err_chi2("stats-tests: column total overflows");
      }
      s2 = s2 + y;
      ii = ii + 1;
    }
    if s2 <= 0 {
      return _err_chi2("stats-tests: column totals must be positive");
    }
    cols.push(s2);
    jj = jj + 1;
  }
  var total: Int = 0;
  i = 0;
  while i < n_rows {
    let r: Int = rows[i];
    if r > _ST_INT_MAX - total {
      return _err_chi2("stats-tests: grand total overflows");
    }
    total = total + r;
    i = i + 1;
  }
  var lr: Int = 1;
  i = 0;
  while i < n_rows {
    let r: Int = rows[i];
    lr = _lcm(lr, r);
    if lr < 0 {
      return _err_chi2("stats-tests: row-total lcm overflows");
    }
    i = i + 1;
  }
  var lc: Int = 1;
  jj = 0;
  while jj < n_cols {
    let c: Int = cols[jj];
    lc = _lcm(lc, c);
    if lc < 0 {
      return _err_chi2("stats-tests: column-total lcm overflows");
    }
    jj = jj + 1;
  }
  if total > _ST_INT_MAX / lr {
    return _err_chi2("stats-tests: chi-square denominator overflows");
  }
  var den = total * lr;
  if den > _ST_INT_MAX / lc {
    return _err_chi2("stats-tests: chi-square denominator overflows");
  }
  den = den * lc;
  var num: Int = 0;
  i = 0;
  while i < n_rows {
    let r: Int = rows[i];
    var j = 0;
    while j < n_cols {
      let c: Int = cols[j];
      let o: Int = table[i * n_cols + j];
      if o > 0 {
        if total > _ST_INT_MAX / o {
          return _err_chi2("stats-tests: chi-square term overflows");
        }
      }
      let to = total * o;
      if r > _ST_INT_MAX / c {
        return _err_chi2("stats-tests: chi-square term overflows");
      }
      let rc = r * c;
      let d = to - rc;
      var ad = d;
      if ad < 0 {
        ad = 0 - ad;
      }
      if ad > _ST_SQRT_MAX {
        return _err_chi2("stats-tests: chi-square term overflows");
      }
      let dd = ad * ad;
      let fr = lr / r;
      let fc = lc / c;
      if dd > _ST_INT_MAX / fr {
        return _err_chi2("stats-tests: chi-square term overflows");
      }
      let t1 = dd * fr;
      if t1 > _ST_INT_MAX / fc {
        return _err_chi2("stats-tests: chi-square term overflows");
      }
      let term = t1 * fc;
      if term > _ST_INT_MAX - num {
        return _err_chi2("stats-tests: chi-square sum overflows");
      }
      num = num + term;
      j = j + 1;
    }
    i = i + 1;
  }
  let g = _gcd(num, den);
  let rnum = num / g;
  let rden = den / g;
  let scaled = _scale_rational(rnum, rden);
  if scaled < 0 {
    return _err_chi2("stats-tests: chi-square scale overflows");
  }
  let df = (n_rows - 1) * (n_cols - 1);
  let bucket = stats_tests_chi_square_p_bucket(scaled, df);
  return _ok_chi2(ChiSquareResult{ num: rnum; den: rden; scaled: scaled; df: df; p_bucket: bucket; });
}

/// Exact numerator of the chi-square rational (reduced). Complexity: O(1).
pub fn stats_tests_chi_square_num(result: &ChiSquareResult) -> Int {
  return result.num;
}

/// Exact denominator of the chi-square rational (reduced, > 0). O(1).
pub fn stats_tests_chi_square_den(result: &ChiSquareResult) -> Int {
  return result.den;
}

/// Scaled chi-square value (1e-4 units). Complexity: O(1).
pub fn stats_tests_chi_square_scaled(result: &ChiSquareResult) -> Int {
  return result.scaled;
}

/// Degrees of freedom of the chi-square result. Complexity: O(1).
pub fn stats_tests_chi_square_df(result: &ChiSquareResult) -> Int {
  return result.df;
}

/// Upper-tail p-value bucket of the chi-square result. Complexity: O(1).
pub fn stats_tests_chi_square_p_bucket_of(result: &ChiSquareResult) -> Int {
  return result.p_bucket;
}

// ---------------------------------------------------------------------------
// Sign test
// ---------------------------------------------------------------------------

/// Two-sided sign test over a vector of differences.
///
/// Differences greater than zero count as plus, less than zero as minus, and
/// zeros are dropped (ties). `stat` is min(n_plus, n_minus); the p-bucket
/// comes from the exact two-sided binomial table for
/// n = n_plus + n_minus (1..20, section 8 of SPEC.md): bucket >= 1 iff
/// 2 * P(K <= stat) <= alpha under Binomial(n, 1/2).
/// Params: diffs - the paired differences (read only).
/// Error case: Err("stats-tests: differences must not be empty") for an
/// empty input and Err("stats-tests: sign test needs at least one nonzero
/// difference") when every difference is zero.
/// Complexity: O(n).
pub fn stats_tests_sign_test(diffs: &Vec[Int]) -> Result[SignTestResult, Str] {
  let n = diffs.len();
  if n <= 0 {
    return _err_sign("stats-tests: differences must not be empty");
  }
  var plus: Int = 0;
  var minus: Int = 0;
  var zero: Int = 0;
  var i = 0;
  while i < n {
    let d: Int = diffs[i];
    if d > 0 {
      plus = plus + 1;
    }
    if d < 0 {
      minus = minus + 1;
    }
    if d == 0 {
      zero = zero + 1;
    }
    i = i + 1;
  }
  let nz = plus + minus;
  if nz <= 0 {
    return _err_sign("stats-tests: sign test needs at least one nonzero difference");
  }
  var stat = plus;
  if minus < stat {
    stat = minus;
  }
  let bucket = stats_tests_sign_p_bucket(stat, nz);
  return _ok_sign(SignTestResult{ n_plus: plus; n_minus: minus; n_zero: zero; stat: stat; p_bucket: bucket; });
}

/// Count of positive differences. Complexity: O(1).
pub fn stats_tests_sign_n_plus(result: &SignTestResult) -> Int {
  return result.n_plus;
}

/// Count of negative differences. Complexity: O(1).
pub fn stats_tests_sign_n_minus(result: &SignTestResult) -> Int {
  return result.n_minus;
}

/// Count of dropped zero differences. Complexity: O(1).
pub fn stats_tests_sign_n_zero(result: &SignTestResult) -> Int {
  return result.n_zero;
}

/// min(n_plus, n_minus), the sign-test statistic. Complexity: O(1).
pub fn stats_tests_sign_stat(result: &SignTestResult) -> Int {
  return result.stat;
}

/// Two-sided p-value bucket of the sign-test result. Complexity: O(1).
pub fn stats_tests_sign_p_bucket_of(result: &SignTestResult) -> Int {
  return result.p_bucket;
}

/// Two-sided sign-test p-value bucket for a statistic `k` out of `n`.
///
/// Params: k - the statistic (normally min(n_plus, n_minus)); n - number of
/// nonzero differences.
/// Returns: 3 (p < 0.001), 2 (p < 0.01), 1 (p < 0.05), 0 (within the table
/// but not significant at 0.05), or -1 when n is outside [1, 20] or k is
/// outside [0, n].
/// Exact rule: bucket >= 1 iff k <= critical(n, alpha), the largest k with
/// 2 * P(K <= k) <= alpha under Binomial(n, 1/2) (section 8 of SPEC.md).
/// Complexity: O(1).
pub fn stats_tests_sign_p_bucket(k: Int, n: Int) -> Int {
  if n < 1 {
    return -1;
  }
  if n > _ST_SIGN_MAX_N {
    return -1;
  }
  if k < 0 {
    return -1;
  }
  if k > n {
    return -1;
  }
  let c05 = _sign_crit(n, 0);
  let c01 = _sign_crit(n, 1);
  let c001 = _sign_crit(n, 2);
  return _bucket_smaller(k, c05, c01, c001);
}

// ---------------------------------------------------------------------------
// Permutation test
// ---------------------------------------------------------------------------

/// Deterministic two-sample permutation test on the mean difference.
///
/// The observed statistic is the scaled mean difference
/// mean(a) - mean(b), each mean rounded half away from zero:
/// round_half_away(10000 * sum_a / n_a) - round_half_away(10000 * sum_b / n_b).
/// Each of the n_perm permutations pools a and b and shuffles the positions
/// with a Fisher-Yates pass whose swap indices come from a MINSTD LCG seeded
/// by `seed` (normalized as in stats_tests_lcg_step); the group sizes stay
/// n_a and n_b. `extreme` counts the permutations whose |difference| is at
/// least |observed_diff|; the p-bucket comes from the exact ratio
/// (section 9 of SPEC.md):
///   bucket 3 iff extreme * 1000 <= n_perm (p <= 0.001),
///   bucket 2 iff extreme * 100 <= n_perm (p <= 0.01),
///   bucket 1 iff extreme * 20 <= n_perm (p <= 0.05),
///   else 0. The estimate has no pseudo-count: extreme == 0 yields bucket 3.
/// Params: a, b - the two samples (read only), each non-empty; seed - any
/// Int; n_perm - number of permutations (> 0 and <= 9223372036854775).
/// Returns: Ok(PermutationResult); the same (a, b, seed, n_perm) always
/// yields the same result, on every run and platform.
/// Error case: Err("stats-tests: ...") for an empty group, a non-positive
/// permutation count or a permutation count too large for the bucket scale.
/// Overflow envelope: all pooled group sums times 10000 must fit in Int
/// (|sum| <= 922337203685477); the summation itself is not guarded.
/// Complexity: O(n_perm * (n_a + n_b)).
pub fn stats_tests_permutation_test(a: &Vec[Int], b: &Vec[Int], seed: Int, n_perm: Int) -> Result[PermutationResult, Str] {
  let na = a.len();
  let nb = b.len();
  if na <= 0 {
    return _err_perm("stats-tests: group A must not be empty");
  }
  if nb <= 0 {
    return _err_perm("stats-tests: group B must not be empty");
  }
  if n_perm <= 0 {
    return _err_perm("stats-tests: permutation count must be positive");
  }
  if n_perm > _ST_PERM_LIMIT {
    return _err_perm("stats-tests: permutation count too large for the bucket scale");
  }
  var pooled = Vec[Int].new();
  var i = 0;
  while i < na {
    let x: Int = a[i];
    pooled.push(x);
    i = i + 1;
  }
  i = 0;
  while i < nb {
    let x: Int = b[i];
    pooled.push(x);
    i = i + 1;
  }
  let observed = _mean_diff_scaled(a, b);
  let n = na + nb;
  var state = _norm_lcg_state(seed);
  var extreme: Int = 0;
  var p = 0;
  while p < n_perm {
    var k = n - 1;
    while k > 0 {
      state = (state * _ST_LCG_MULT) % _ST_LCG_MOD;
      let j = state % (k + 1);
      let left: Int = pooled[k];
      let right: Int = pooled[j];
      pooled[k] = right;
      pooled[j] = left;
      k = k - 1;
    }
    var sa: Int = 0;
    var sb: Int = 0;
    var q = 0;
    while q < na {
      let x: Int = pooled[q];
      sa = sa + x;
      q = q + 1;
    }
    q = na;
    while q < n {
      let x: Int = pooled[q];
      sb = sb + x;
      q = q + 1;
    }
    let d = _div_round(sa * _ST_SCALE, na) - _div_round(sb * _ST_SCALE, nb);
    var ad = d;
    if ad < 0 {
      ad = 0 - ad;
    }
    var ao = observed;
    if ao < 0 {
      ao = 0 - ao;
    }
    if ad >= ao {
      extreme = extreme + 1;
    }
    p = p + 1;
  }
  let bucket = stats_tests_permutation_p_bucket(extreme, n_perm);
  return _ok_perm(PermutationResult{ observed_diff: observed; extreme: extreme; n_perm: n_perm; p_bucket: bucket; });
}

/// Scaled observed mean difference (group A minus group B). O(1).
pub fn stats_tests_permutation_observed_diff(result: &PermutationResult) -> Int {
  return result.observed_diff;
}

/// Number of permutations at least as extreme as the observed one. O(1).
pub fn stats_tests_permutation_extreme(result: &PermutationResult) -> Int {
  return result.extreme;
}

/// Number of permutations requested. Complexity: O(1).
pub fn stats_tests_permutation_n_perm(result: &PermutationResult) -> Int {
  return result.n_perm;
}

/// P-value bucket of the permutation result. Complexity: O(1).
pub fn stats_tests_permutation_p_bucket_of(result: &PermutationResult) -> Int {
  return result.p_bucket;
}

/// P-value bucket for an extreme count out of a permutation count.
///
/// Params: extreme - number of permutations at least as extreme as the
/// observed one (0 <= extreme <= n_perm); n_perm - permutations performed.
/// Returns: 3 (p <= 0.001), 2 (p <= 0.01), 1 (p <= 0.05), 0 (p > 0.05), or
/// -1 when n_perm <= 0, n_perm is too large for the bucket multiplications
/// (> 9223372036854775), or extreme is outside [0, n_perm]. The comparisons
/// are exact: p_hat = extreme / n_perm without a pseudo-count.
/// Complexity: O(1).
pub fn stats_tests_permutation_p_bucket(extreme: Int, n_perm: Int) -> Int {
  if n_perm <= 0 {
    return -1;
  }
  if n_perm > _ST_PERM_LIMIT {
    return -1;
  }
  if extreme < 0 {
    return -1;
  }
  if extreme > n_perm {
    return -1;
  }
  if extreme * 1000 <= n_perm {
    return 3;
  }
  if extreme * 100 <= n_perm {
    return 2;
  }
  if extreme * 20 <= n_perm {
    return 1;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Exact two-sided bucket of a statistic against critical values; a negative
// critical value marks an alpha the table cannot reach at this size.
fn _bucket_smaller(stat: Int, c05: Int, c01: Int, c001: Int) -> Int {
  if c001 >= 0 {
    if stat <= c001 {
      return 3;
    }
  }
  if c01 >= 0 {
    if stat <= c01 {
      return 2;
    }
  }
  if c05 >= 0 {
    if stat <= c05 {
      return 1;
    }
  }
  return 0;
}

// Average-tie ranks of `values` scaled 1e-4, in input order (caller guards
// the length). Rank = less + (equal + 1) / 2 in scale units.
fn _ranks_vec(values: &Vec[Int]) -> Vec[Int] {
  let n = values.len();
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    let v: Int = values[i];
    var less: Int = 0;
    var equal: Int = 0;
    var j = 0;
    while j < n {
      let w: Int = values[j];
      if w < v {
        less = less + 1;
      }
      if w == v {
        equal = equal + 1;
      }
      j = j + 1;
    }
    out.push(less * _ST_SCALE + (equal + 1) * _ST_HALF);
    i = i + 1;
  }
  return out;
}

// Scaled sum of the ranks 1..n: n * (n + 1) / 2 * 10000. Callers keep n
// within _ST_MAX_SAMPLE so the product fits in Int.
fn _rank_total(n: Int) -> Int {
  let t = n * (n + 1) / 2;
  return t * _ST_SCALE;
}

// Truncating division with halves rounded away from zero (b > 0); the
// doubled remainder cannot overflow for the small denominators used here.
fn _div_round(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  var mag = r;
  if mag < 0 {
    mag = 0 - mag;
  }
  if mag * 2 >= b {
    if a < 0 {
      return q - 1;
    }
    return q + 1;
  }
  return q;
}

// Normalize any Int seed into [1, 2147483646]: |seed mod 2147483646| + 1.
fn _norm_lcg_state(seed: Int) -> Int {
  var s = seed % _ST_LCG_RANGE;
  if s < 0 {
    s = 0 - s;
  }
  return s + 1;
}

// Scaled mean difference mean(a) - mean(b), each mean rounded half away from
// zero. The caller keeps |sum| * 10000 inside Int (documented envelope).
fn _mean_diff_scaled(a: &Vec[Int], b: &Vec[Int]) -> Int {
  let sa = _sum_vec(a);
  let sb = _sum_vec(b);
  let ma = _div_round(sa * _ST_SCALE, a.len());
  let mb = _div_round(sb * _ST_SCALE, b.len());
  return ma - mb;
}

// Plain arithmetic sum (no overflow detection; caller envelope).
fn _sum_vec(values: &Vec[Int]) -> Int {
  var s: Int = 0;
  var i = 0;
  while i < values.len() {
    let x: Int = values[i];
    s = s + x;
    i = i + 1;
  }
  return s;
}

// Greatest common divisor of two non-negative Ints (gcd(0, b) = b).
fn _gcd(a: Int, b: Int) -> Int {
  var x = a;
  var y = b;
  while y != 0 {
    let t = x % y;
    x = y;
    y = t;
  }
  return x;
}

// Least common multiple of two positive Ints, or -1 when the product
// overflows Int. The result is positive on success.
fn _lcm(a: Int, b: Int) -> Int {
  let g = _gcd(a, b);
  let q = a / g;
  if q > _ST_INT_MAX / b {
    return -1;
  }
  return q * b;
}

// round_half_away(10000 * num / den) for num >= 0, den > 0; -1 when the
// scaled numerator would overflow Int.
fn _scale_rational(num: Int, den: Int) -> Int {
  if num > _ST_INT_MAX / _ST_SCALE {
    return -1;
  }
  return _div_round(num * _ST_SCALE, den);
}

// ---------------------------------------------------------------------------
// Curated critical-value tables
// ---------------------------------------------------------------------------

// Two-sided Mann-Whitney critical U values in 1e-4 scale, computed from the
// exact permutation distribution (SPEC.md section 6). Pair ids are
// row-major over 2 <= n1 <= n2 <= 8; each pair stores (0.05, 0.01, 0.001),
// with -1 when that alpha is unreachable at the size.
fn _wilcoxon_crit(pair: Int, alpha: Int) -> Int {
  if pair < 0 {
    return -1;
  }
  if pair > 27 {
    return -1;
  }
  if alpha < 0 {
    return -1;
  }
  if alpha > 2 {
    return -1;
  }
  var t = Vec[Int].new();
  // pair 0: n1=2, n2=2
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // pair 1: n1=2, n2=3
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // pair 2: n1=2, n2=4
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // pair 3: n1=2, n2=5
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // pair 4: n1=2, n2=6
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // pair 5: n1=2, n2=7
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // pair 6: n1=2, n2=8
  t.push(0);
  t.push(-1);
  t.push(-1);
  // pair 7: n1=3, n2=3
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // pair 8: n1=3, n2=4
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // pair 9: n1=3, n2=5
  t.push(0);
  t.push(-1);
  t.push(-1);
  // pair 10: n1=3, n2=6
  t.push(1);
  t.push(-1);
  t.push(-1);
  // pair 11: n1=3, n2=7
  t.push(1);
  t.push(-1);
  t.push(-1);
  // pair 12: n1=3, n2=8
  t.push(2);
  t.push(-1);
  t.push(-1);
  // pair 13: n1=4, n2=4
  t.push(0);
  t.push(-1);
  t.push(-1);
  // pair 14: n1=4, n2=5
  t.push(1);
  t.push(-1);
  t.push(-1);
  // pair 15: n1=4, n2=6
  t.push(2);
  t.push(0);
  t.push(-1);
  // pair 16: n1=4, n2=7
  t.push(3);
  t.push(0);
  t.push(-1);
  // pair 17: n1=4, n2=8
  t.push(4);
  t.push(1);
  t.push(-1);
  // pair 18: n1=5, n2=5
  t.push(2);
  t.push(0);
  t.push(-1);
  // pair 19: n1=5, n2=6
  t.push(3);
  t.push(1);
  t.push(-1);
  // pair 20: n1=5, n2=7
  t.push(5);
  t.push(1);
  t.push(-1);
  // pair 21: n1=5, n2=8
  t.push(6);
  t.push(2);
  t.push(-1);
  // pair 22: n1=6, n2=6
  t.push(5);
  t.push(2);
  t.push(-1);
  // pair 23: n1=6, n2=7
  t.push(6);
  t.push(3);
  t.push(-1);
  // pair 24: n1=6, n2=8
  t.push(8);
  t.push(4);
  t.push(0);
  // pair 25: n1=7, n2=7
  t.push(8);
  t.push(4);
  t.push(0);
  // pair 26: n1=7, n2=8
  t.push(10);
  t.push(6);
  t.push(1);
  // pair 27: n1=8, n2=8
  t.push(13);
  t.push(7);
  t.push(2);
  let x: Int = t[pair * 3 + alpha];
  return x;
}

// Pair id of (s, l) with 2 <= s <= l <= 8 in the row-major canonical order;
// -1 when the sizes are outside the table.
fn _wilcoxon_pair_id(s: Int, l: Int) -> Int {
  if s == 2 {
    return l - 2;
  }
  if s == 3 {
    return 7 + (l - 3);
  }
  if s == 4 {
    return 13 + (l - 4);
  }
  if s == 5 {
    return 18 + (l - 5);
  }
  if s == 6 {
    return 22 + (l - 6);
  }
  if s == 7 {
    return 25 + (l - 7);
  }
  if s == 8 {
    return 27;
  }
  return -1;
}

// Two-sided sign-test critical k values for n = 1..20 (SPEC.md section 8),
// computed from the exact binomial distribution; each n stores
// (0.05, 0.01, 0.001), with -1 when that alpha is unreachable at the size.
fn _sign_crit(n: Int, alpha: Int) -> Int {
  if n < 1 {
    return -1;
  }
  if n > 20 {
    return -1;
  }
  if alpha < 0 {
    return -1;
  }
  if alpha > 2 {
    return -1;
  }
  var t = Vec[Int].new();
  // n = 1
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // n = 2
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // n = 3
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // n = 4
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // n = 5
  t.push(-1);
  t.push(-1);
  t.push(-1);
  // n = 6
  t.push(0);
  t.push(-1);
  t.push(-1);
  // n = 7
  t.push(0);
  t.push(-1);
  t.push(-1);
  // n = 8
  t.push(0);
  t.push(0);
  t.push(-1);
  // n = 9
  t.push(1);
  t.push(0);
  t.push(-1);
  // n = 10
  t.push(1);
  t.push(0);
  t.push(-1);
  // n = 11
  t.push(1);
  t.push(0);
  t.push(0);
  // n = 12
  t.push(2);
  t.push(1);
  t.push(0);
  // n = 13
  t.push(2);
  t.push(1);
  t.push(0);
  // n = 14
  t.push(2);
  t.push(1);
  t.push(0);
  // n = 15
  t.push(3);
  t.push(2);
  t.push(1);
  // n = 16
  t.push(3);
  t.push(2);
  t.push(1);
  // n = 17
  t.push(4);
  t.push(2);
  t.push(1);
  // n = 18
  t.push(4);
  t.push(3);
  t.push(1);
  // n = 19
  t.push(4);
  t.push(3);
  t.push(2);
  // n = 20
  t.push(5);
  t.push(3);
  t.push(2);
  let x: Int = t[(n - 1) * 3 + alpha];
  return x;
}

// Standard chi-square upper-tail critical values in 1e-4 scale, rounded to
// the nearest unit at authoring time (SPEC.md section 7); df = 1..10 and
// alpha = 0.05, 0.01, 0.001.
fn _chi2_crit(df: Int, alpha: Int) -> Int {
  if df == 1 {
    if alpha == 0 {
      return 38415;
    }
    if alpha == 1 {
      return 66349;
    }
    return 108276;
  }
  if df == 2 {
    if alpha == 0 {
      return 59915;
    }
    if alpha == 1 {
      return 92103;
    }
    return 138155;
  }
  if df == 3 {
    if alpha == 0 {
      return 78147;
    }
    if alpha == 1 {
      return 113449;
    }
    return 162662;
  }
  if df == 4 {
    if alpha == 0 {
      return 94877;
    }
    if alpha == 1 {
      return 132767;
    }
    return 184668;
  }
  if df == 5 {
    if alpha == 0 {
      return 110705;
    }
    if alpha == 1 {
      return 150863;
    }
    return 205150;
  }
  if df == 6 {
    if alpha == 0 {
      return 125916;
    }
    if alpha == 1 {
      return 168119;
    }
    return 224577;
  }
  if df == 7 {
    if alpha == 0 {
      return 140671;
    }
    if alpha == 1 {
      return 184753;
    }
    return 243219;
  }
  if df == 8 {
    if alpha == 0 {
      return 155073;
    }
    if alpha == 1 {
      return 200902;
    }
    return 261245;
  }
  if df == 9 {
    if alpha == 0 {
      return 169190;
    }
    if alpha == 1 {
      return 216660;
    }
    return 278772;
  }
  if df == 10 {
    if alpha == 0 {
      return 183070;
    }
    if alpha == 1 {
      return 232093;
    }
    return 295883;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_ranks(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

fn _err_ranks(msg: Str) -> Result[Vec[Int], Str] {
  return Err(msg);
}

fn _ok_wilcoxon(v: WilcoxonResult) -> Result[WilcoxonResult, Str] {
  return Ok(v);
}

fn _err_wilcoxon(msg: Str) -> Result[WilcoxonResult, Str] {
  return Err(msg);
}

fn _ok_chi2(v: ChiSquareResult) -> Result[ChiSquareResult, Str] {
  return Ok(v);
}

fn _err_chi2(msg: Str) -> Result[ChiSquareResult, Str] {
  return Err(msg);
}

fn _ok_sign(v: SignTestResult) -> Result[SignTestResult, Str] {
  return Ok(v);
}

fn _err_sign(msg: Str) -> Result[SignTestResult, Str] {
  return Err(msg);
}

fn _ok_perm(v: PermutationResult) -> Result[PermutationResult, Str] {
  return Ok(v);
}

fn _err_perm(msg: Str) -> Result[PermutationResult, Str] {
  return Err(msg);
}
