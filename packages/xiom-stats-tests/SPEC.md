# xiom.stats-tests -- Specification

Status: `incubating` (implemented, harness-green on compiler 0.62.1, not
published).
Package: `xiom.stats-tests`; module: `xiom.stats_tests`
(`src/stats_tests.xi`); manifest: `package.xi` (version `0.1.0`). The library
module imports no stdlib module; the manifest depends on `xiom.std`
(`>=0.60.0 <1.0.0`) as a platform dependency. Tests:
`tests/test_conformance.xi` (25 checks).

## 1. Scope

Pure, deterministic, integer-only hypothesis testing at fixed point 1e-4:

- average-tie ranks over `Int` samples;
- Wilcoxon rank-sum (Mann-Whitney) U with average-tie ranks and a two-sided
  exact critical-value table for sample sizes 2..8;
- chi-square goodness-of-fit and independence statistics against integer
  expected counts, as exact rationals (`num / den` in lowest terms) plus the
  scaled value, with the standard upper-tail critical values for df 1..10;
- the two-sided sign test with the exact binomial table for n = 1..20;
- a deterministic two-sample permutation test on the scaled mean difference,
  driven by a caller-seeded MINSTD LCG, with exact `extreme / n_perm` buckets.

No floats, no FFI, no I/O, no clock access, no global state, no allocation
beyond the returned vectors.

## 2. Non-goals (v0.1.0)

- t-tests, ANOVA, Kolmogorov-Smirnov, Fisher's exact test and regression
  (reserved by the placeholder; they need distribution functions the module
  does not provide);
- asymptotic / normal-approximation p-values of any kind;
- confidence intervals and effect sizes;
- floating-point inputs or outputs;
- random-number generation beyond the reproducibility LCG;
- cryptography or secure randomness.

## 3. Fixed point and rounding

The scale is `S = 10000` (1.0 = 10000), exposed by `stats_tests_scale()`.
Every non-integer quantity is stored as `round_half_away(S * x)`:

```
_div_round(a, b), b > 0:
  q = a / b            // truncates toward zero (v0.62.x)
  r = a % b            // sign of the dividend
  if 2 * |r| >= b:  q + 1 when a >= 0, else q - 1
  else:             q
```

This is the only rounding rule in the module. `Int` division and `%` follow
the dividend's sign; `_div_round` is used for every final division, and all
preceding arithmetic (rank sums, U, lcm/numerator accumulation) is exact
integer arithmetic.

Envelopes (documented caller contracts):

- rank scale: samples of at most `40000000` entries (else `Err`); the scaled
  rank sum `n(n+1)/2 * 10000` then fits `Int`;
- permutation sums: `|group sum| * 10000` must fit `Int`, i.e.
  `|sum| <= 922337203685477`; the summation is not guarded and no error is
  raised on overflow;
- chi-square: every lcm, product, sum and scale step is guarded and returns
  the errors in section 11.

## 4. Ranks

`stats_tests_ranks(values) -> Result[Vec[Int], Str]`, in input order, leading
`0`-based positions dropped in favour of 1-based ranks:

```
less(v)  = #{ w in values : w < v }
equal(v) = #{ w in values : w == v }
scaled_rank(v) = less(v) * 10000 + (equal(v) + 1) * 5000
```

The real rank is `less(v) + (equal(v) + 1) / 2`, so a group of `k` tied values
at 1-based positions `p..p+k-1` receives the common rank `p + (k-1)/2`; halves
land exactly on multiples of 5000 (15000 = rank 1.5). Duplicated values get
equal ranks. Empty input yields `Ok(empty)`. Complexity O(n^2).

## 5. Wilcoxon rank-sum (Mann-Whitney) U

`stats_tests_wilcoxon_u(a, b) -> Result[WilcoxonResult, Str]`.

1. Reject either group being empty.
2. Pool `a` then `b`, rank with section 4 (average ties), and sum the scaled
   ranks of the first `n_a` entries into `rank_sum_a`; `rank_sum_b` is the
   total `(n_a+n_b)(n_a+n_b+1)/2 * 10000` minus `rank_sum_a`.
3. `u_a = rank_sum_a - 10000 * n_a(n_a + 1) / 2` (scaled);
   `u_b = n_a * n_b * 10000 - u_a`. The identity
   `u_a + u_b = n_a * n_b * 10000` holds exactly, ties included.
4. `p_bucket = stats_tests_wilcoxon_p_bucket(u_a, n_a, n_b)`, which internally
   uses `min(u, n_a * n_b * 10000 - u)`, so either side may be passed.

### 5.1 Two-sided critical-value table

Sizes are canonicalised to `2 <= n1 <= n2 <= 8` (the U distribution is
symmetric under swapping groups). Pair id = row-major:
`(2,2..8) -> 0..6`, `(3,3..8) -> 7..12`, `(4,4..8) -> 13..17`,
`(5,5..8) -> 18..21`, `(6,6..8) -> 22..24`, `(7,7..8) -> 25..26`, `(8,8) -> 27`.

Each pair stores critical scaled U values for (0.05, 0.01, 0.001); the value
is the largest `u` with `2 * P(U <= u) <= alpha` under the exact permutation
distribution (average-tie handling: the exact distribution of the U statistic
computed over all `C(n1+n2, n1)` interleavings), or `-1` when that alpha is
unreachable at the size. Buckets: stat `<=` crit(0.001) -> 3, `<=` crit(0.01)
-> 2, `<=` crit(0.05) -> 1, else 0. Sizes outside `[2, 8]` or `u` outside
`[0, n_a * n_b * 10000]` yield `-1`.

| Pair | (n1,n2) | 0.05 | 0.01 | 0.001 | | Pair | (n1,n2) | 0.05 | 0.01 | 0.001 |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | (2,2) | -1 | -1 | -1 | | 14 | (4,5) | 1 | -1 | -1 |
| 1 | (2,3) | -1 | -1 | -1 | | 15 | (4,6) | 2 | 0 | -1 |
| 2 | (2,4) | -1 | -1 | -1 | | 16 | (4,7) | 3 | 0 | -1 |
| 3 | (2,5) | -1 | -1 | -1 | | 17 | (4,8) | 4 | 1 | -1 |
| 4 | (2,6) | -1 | -1 | -1 | | 18 | (5,5) | 2 | 0 | -1 |
| 5 | (2,7) | -1 | -1 | -1 | | 19 | (5,6) | 3 | 1 | -1 |
| 6 | (2,8) | 0 | -1 | -1 | | 20 | (5,7) | 5 | 1 | -1 |
| 7 | (3,3) | -1 | -1 | -1 | | 21 | (5,8) | 6 | 2 | -1 |
| 8 | (3,4) | -1 | -1 | -1 | | 22 | (6,6) | 5 | 2 | -1 |
| 9 | (3,5) | 0 | -1 | -1 | | 23 | (6,7) | 6 | 3 | -1 |
| 10 | (3,6) | 1 | -1 | -1 | | 24 | (6,8) | 8 | 4 | 0 |
| 11 | (3,7) | 1 | -1 | -1 | | 25 | (7,7) | 8 | 4 | 0 |
| 12 | (3,8) | 2 | -1 | -1 | | 26 | (7,8) | 10 | 6 | 1 |
| 13 | (4,4) | 0 | -1 | -1 | | 27 | (8,8) | 13 | 7 | 2 |

Table provenance: for `(4,4)` the distribution has `C(8,4) = 70` equally
likely interleavings; `2 * P(U <= 0) = 2/70 = 0.0286 <= 0.05` and
`2/70 > 0.01`, hence `(0.05, 0.01) = (0, -1)`. The full table was generated
at authoring time by dynamic programming over the exact
interleaving/inversion counts and is asserted by the conformance suite at the
documented boundaries.

## 6. Chi-square goodness-of-fit

`stats_tests_chi_square_gof(observed, expected) -> Result[ChiSquareResult, Str]`
computes `chi2 = sum_i (o_i - e_i)^2 / e_i` exactly. With
`L = lcm_i(e_i)`:

```
num = sum_i (o_i - e_i)^2 * (L / e_i)      (exact integer)
den = L
```

Then `g = gcd(num, den)` and the result stores `num/g`, `den/g` (lowest terms;
`0` is stored as `0/1`). `scaled = _div_round(10000 * (num/g), den/g)`, and
`df = n - 1` with `n >= 2`. Validation order: length match, category count
(`n >= 2`), per-category `e_i > 0` and `o_i >= 0`, lcm overflow, per-category
term overflow, running-sum overflow, scale overflow.

Worked example (asserted): `o = [10,20,30]`, `e = [20,20,20]` give
`L = 20`, `num = 200`, `den = 20`, reduced `10/1`, `scaled = 100000`,
`df = 2`, bucket 2.

## 7. Chi-square independence

`stats_tests_chi_square_independence(table, n_rows, n_cols)` over a row-major
count table (`table[i * n_cols + j]`), `n_rows, n_cols >= 2`:

```
r_i = row total i,  c_j = column total j,  n = grand total
e_ij = r_i * c_j / n
chi2 = sum_ij (n * o_ij - r_i * c_j)^2 / (n * r_i * c_j)
```

With `Lr = lcm_i(r_i)` and `Lc = lcm_j(c_j)`:

```
den = n * Lr * Lc
num = sum_ij (n * o_ij - r_i * c_j)^2 * (Lr / r_i) * (Lc / c_j)
```

reduced by `gcd(num, den)`, `df = (n_rows - 1) * (n_cols - 1)`. Validation
order: row count, column count, dimensions (`n_rows * n_cols` fits `Int`),
length, per-cell non-negativity, row totals positive, column totals positive,
grand total, lcm denominators, per-cell term overflow, sum overflow, scale
overflow.

Worked examples (asserted): `[10,20,30,40]` (2x2) gives `50/63`, scaled 7937,
df 1, bucket 0; `[10,20,30,20,10,30]` (2x3) gives `20/3`, scaled 66667, df 2,
bucket 1; a proportional table gives `0/1`.

### 7.1 Chi-square upper-tail critical values (scaled 1e-4)

The standard chi-square quantiles rounded to the nearest 1e-4 at authoring
time. Buckets: `scaled >= crit(0.001)` -> 3, `>= crit(0.01)` -> 2,
`>= crit(0.05)` -> 1, else 0; `df` outside `[1, 10]` or a negative statistic
yields `-1`.

| df | 0.05 | 0.01 | 0.001 |
|---|---|---|---|
| 1 | 38415 | 66349 | 108276 |
| 2 | 59915 | 92103 | 138155 |
| 3 | 78147 | 113449 | 162662 |
| 4 | 94877 | 132767 | 184668 |
| 5 | 110705 | 150863 | 205150 |
| 6 | 125916 | 168119 | 224577 |
| 7 | 140671 | 184753 | 243219 |
| 8 | 155073 | 200902 | 261245 |
| 9 | 169190 | 216660 | 278772 |
| 10 | 183070 | 232093 | 295883 |

Because both the statistic and the critical value are rounded to 1e-4, a
bucket boundary sits within 5e-5 of the exact real comparison.

## 8. Sign test

`stats_tests_sign_test(diffs) -> Result[SignTestResult, Str]`:

```
n_plus  = #{ d : d > 0 }
n_minus = #{ d : d < 0 }
n_zero  = #{ d : d == 0 }        // dropped from the test
stat    = min(n_plus, n_minus)
```

Empty input errors; an all-zero input errors (no nonzero difference).
`p_bucket = stats_tests_sign_p_bucket(stat, n_plus + n_minus)`.

### 8.1 Two-sided binomial critical values

Exact under `Binomial(n, 1/2)`: the critical `k` is the largest value with
`2 * P(K <= k) <= alpha`, or `-1` when unreachable. Buckets: `stat <=`
crit(0.001) -> 3, `<=` crit(0.01) -> 2, `<=` crit(0.05) -> 1, else 0; `n`
outside `[1, 20]` or `k` outside `[0, n]` yields `-1`.

| n | 0.05 | 0.01 | 0.001 | | n | 0.05 | 0.01 | 0.001 |
|---|---|---|---|---|---|---|---|---|
| 1 | -1 | -1 | -1 | | 11 | 1 | 0 | 0 |
| 2 | -1 | -1 | -1 | | 12 | 2 | 1 | 0 |
| 3 | -1 | -1 | -1 | | 13 | 2 | 1 | 0 |
| 4 | -1 | -1 | -1 | | 14 | 2 | 1 | 0 |
| 5 | -1 | -1 | -1 | | 15 | 3 | 2 | 1 |
| 6 | 0 | -1 | -1 | | 16 | 3 | 2 | 1 |
| 7 | 0 | -1 | -1 | | 17 | 4 | 2 | 1 |
| 8 | 0 | 0 | -1 | | 18 | 4 | 3 | 1 |
| 9 | 1 | 0 | -1 | | 19 | 4 | 3 | 2 |
| 10 | 1 | 0 | -1 | | 20 | 5 | 3 | 2 |

Boundary examples (asserted): `(0,5) -> 0` because `2 * P(K<=0) = 2/32 =
0.0625 > 0.05`; `(0,6) -> 1` because `2/64 = 0.03125 <= 0.05`.

## 9. Permutation test

`stats_tests_permutation_test(a, b, seed, n_perm) -> Result[PermutationResult, Str]`.

Observed statistic (scaled 1e-4):

```
observed = _div_round(10000 * sum(a), n_a) - _div_round(10000 * sum(b), n_b)
```

Then, for each of `n_perm` permutations: pool `a` then `b` into one vector,
Fisher-Yates shuffle it (descending `k = n-1 .. 1`,
`j = state % (k+1)`, swap), and recompute the same difference for the first
`n_a` positions. `extreme` counts permutations whose `|difference|` is at
least `|observed|`.

The LCG is MINSTD (Park-Miller): state normalisation
`s0 = |seed mod 2147483646| + 1`, step
`s_{k+1} = (s_k * 48271) mod 2147483647` (multiplier and modulus exposed by
`stats_tests_lcg_multiplier` / `stats_tests_lcg_modulus`). The same
`(a, b, seed, n_perm)` always yields the same result on every run and
platform; the generator is not cryptographic and `state % (k+1)` is slightly
biased (documented).

Buckets from the exact ratio (`p_hat = extreme / n_perm`, no pseudo-count):
`extreme * 1000 <= n_perm` -> 3, `extreme * 100 <= n_perm` -> 2,
`extreme * 20 <= n_perm` -> 1, else 0; `n_perm` outside `(0, 9223372036854775]`
or `extreme` outside `[0, n_perm]` yields `-1`. Hence `extreme == 0` yields
bucket 3 and an all-tied sample (`observed == 0`, every permutation extreme)
yields bucket 0.

Fixed vectors (asserted):

| Call | observed | extreme | bucket |
|---|---|---|---|
| `permutation_test([1,2,3], [4,5,6], 1, 20)` | -30000 | 1 | 1 |
| `permutation_test([1,2,3], [4,5,6], 1, 200)` | -30000 | 18 | 0 |
| `permutation_test([1,1,2], [2,3,3], 7, 50)` | -13334 | 9 | 0 |
| `permutation_test([5,5,5], [5,5,5], 3, 10)` | 0 | 10 | 0 |

## 10. Data model and API

Structs are flat with `Int` fields only; fields are implementation detail and
are read through the accessors in `README.md`.

| Type | Fields |
|---|---|
| `WilcoxonResult` | `u_a, u_b, rank_sum_a, rank_sum_b, n_a, n_b, p_bucket` |
| `ChiSquareResult` | `num, den, scaled, df, p_bucket` |
| `SignTestResult` | `n_plus, n_minus, n_zero, stat, p_bucket` |
| `PermutationResult` | `observed_diff, extreme, n_perm, p_bucket` |

Bucket codes: `-1` unknown / outside the curated table, `0` not significant
at 0.05, `1` p < 0.05, `2` p < 0.01, `3` p < 0.001;
`stats_tests_is_significant(bucket)` is `bucket >= 1`.

## 11. Error catalog

| Message | Trigger |
|---|---|
| `stats-tests: sample too large for the rank scale` | `ranks` with more than 40000000 entries |
| `stats-tests: group A must not be empty` | Wilcoxon / permutation with an empty first group |
| `stats-tests: group B must not be empty` | Wilcoxon / permutation with an empty second group |
| `stats-tests: pooled sample too large for the rank scale` | `n_a + n_b > 40000000` (Wilcoxon) |
| `stats-tests: differences must not be empty` | sign test with no differences |
| `stats-tests: sign test needs at least one nonzero difference` | sign test with all-zero differences |
| `stats-tests: observed and expected lengths differ` | GoF length mismatch |
| `stats-tests: need at least two categories` | GoF with fewer than two categories |
| `stats-tests: expected counts must be positive` | GoF `e_i <= 0` |
| `stats-tests: observed counts must not be negative` | GoF `o_i < 0` |
| `stats-tests: expected-count lcm overflows` | GoF lcm exceeds `Int` |
| `stats-tests: chi-square term overflows` | GoF/independence per-term product or square exceeds `Int` |
| `stats-tests: chi-square sum overflows` | GoF/independence running sum exceeds `Int` |
| `stats-tests: chi-square scale overflows` | scaled numerator would exceed `Int` |
| `stats-tests: need at least two rows` | independence `n_rows < 2` |
| `stats-tests: need at least two columns` | independence `n_cols < 2` |
| `stats-tests: dimensions overflow` | independence `n_rows * n_cols` exceeds `Int` |
| `stats-tests: table length does not match the shape` | independence `table.len() != n_rows * n_cols` |
| `stats-tests: table counts must not be negative` | independence negative cell |
| `stats-tests: row total overflows` | independence row sum exceeds `Int` |
| `stats-tests: row totals must be positive` | independence zero row |
| `stats-tests: column total overflows` | independence column sum exceeds `Int` |
| `stats-tests: column totals must be positive` | independence zero column |
| `stats-tests: grand total overflows` | independence grand total exceeds `Int` |
| `stats-tests: row-total lcm overflows` / `... column-total lcm overflows` | independence lcm exceeds `Int` |
| `stats-tests: chi-square denominator overflows` | independence `n * Lr * Lc` exceeds `Int` |
| `stats-tests: permutation count must be positive` | permutation `n_perm <= 0` |
| `stats-tests: permutation count too large for the bucket scale` | permutation `n_perm > 9223372036854775` |

## 12. Compatibility notes (compiler 0.62.1)

- `Ok` / `Err` are constructed only in the leaf helpers
  (`_ok_ranks` / `_err_ranks`, `_ok_wilcoxon` / `_err_wilcoxon`,
  `_ok_chi2` / `_err_chi2`, `_ok_sign` / `_err_sign`,
  `_ok_perm` / `_err_perm`).
- Every `Vec[Int]` element read binds the element to a typed local first;
  struct fields are read through accessors, never through a `&field` passed
  into a `&Vec` parameter.
- Free functions only: no methods, generics, callbacks or indexed
  function-table dispatch; all struct payloads are scalar `Int` fields.
- `Int` division truncates toward zero; all rounding is explicit in
  `_div_round`.
- No function is named after a builtin and no mixed `Vec<...]` brackets are
  used.

## 13. Test plan

`tests/test_conformance.xi` (25 checks, all passing; direct calls, no function
tables):

| # | Check |
|---|---|
| 1 | scale, bucket codes, LCG constants and KAT steps |
| 2 | ranks: distinct values, empty input, singleton |
| 3 | ranks: average ties, all-equal group, input order |
| 4 | ranks: negative values, two tied pairs |
| 5 | Wilcoxon 2x2 example and the U identity |
| 6 | Wilcoxon average-tie ranks keep the U identity |
| 7 | Wilcoxon separated samples significant in both directions |
| 8 | Wilcoxon bucket boundaries, symmetry, range guards |
| 9 | Wilcoxon empty-group errors |
| 10 | GoF exact 10.0, df 2, bucket 2 |
| 11 | GoF perfect fit is 0/1 |
| 12 | GoF validation (length, categories, expectation sign) |
| 13 | GoF lcm / term / sum overflow guards |
| 14 | chi-square critical-value boundaries for df 1 and 2 |
| 15 | independence exact 50/63 on 2x2 |
| 16 | independence exact 20/3 on 2x3, df 2 |
| 17 | independence proportional table is 0/1 |
| 18 | independence shape, totals, sign, dimension guards |
| 19 | sign 3 vs 2 not significant |
| 20 | sign drops zeros |
| 21 | sign binomial boundaries and range guards |
| 22 | sign empty / all-zero errors |
| 23 | permutation fixed-seed KAT and determinism |
| 24 | permutation tie handling and all-tied sample |
| 25 | permutation validation and exact ratio buckets |
