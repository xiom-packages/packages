# xiom.stats-tests

> **Status:** `incubating` -- conformance-tested (25/25); published at `v0.1.0` on the XIOM registry.
> **Scope:** exact integer statistical tests at fixed point 1e-4 (10000 = 1.0):
> average-tie ranks, Wilcoxon rank-sum (Mann-Whitney) U, chi-square
> goodness-of-fit and independence against integer expected counts, the sign
> test and a deterministic caller-seeded permutation test. P-values are
> bucketed from documented critical-value tables; the exact integer
> statistics are the primary output.
> **Deps:** `xiom.std >=0.60.0 <1.0.0`. The library module imports no stdlib
> module (pure integer arithmetic); the tests use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.stats-tests` (module `xiom.stats_tests`) is a dependency-free,
floating-point-free hypothesis-testing toolkit. Every quantity is an `Int`:
non-integer values live in units of `1e-4`, so a rank of 1.5 is `15000` and a
chi-square of 10.0 is `100000`. Four families are covered:

- **Ranks** (`stats_tests_ranks`): 1-based average ranks with tie handling,
  returned in input order, scaled 1e-4.
- **Wilcoxon rank-sum / Mann-Whitney U** (`stats_tests_wilcoxon_u`): rank sums
  over the pooled sample, both U statistics (`u_a + u_b = n_a * n_b * 10000`
  exactly, even with ties), and a two-sided p-bucket for sample sizes 2..8 from
  an exact critical-value table.
- **Chi-square** (`stats_tests_chi_square_gof`,
  `stats_tests_chi_square_independence`): the statistic is an exact rational
  `num / den` in lowest terms plus its scaled value; p-buckets for df 1..10
  from the standard upper-tail critical values.
- **Sign test** (`stats_tests_sign_test`) and **permutation test**
  (`stats_tests_permutation_test`, MINSTD LCG seeded by the caller): counts are
  exact; p-values are exact bucket comparisons (binomial table for the sign
  test, the exact `extreme / n_perm` ratio for the permutation test).

No `Float64`, no FFI, no I/O, no clock access, no global state, no allocation
beyond the returned vectors. Results are deterministic on every run and
platform. See `SPEC.md` for the exact formulas, tie/rounding rules and the
critical-value tables as implemented.

## Units

| Quantity | Unit | Notes |
|---|---|---|
| scaled value | `Int`, 1e-4 units | `10000` = 1.0 |
| ranks | 1e-4 units | average ties; halves land on multiples of 5000 |
| U, rank sums | 1e-4 units | exact integer identities hold with ties |
| chi-square | exact `num / den` (reduced) plus scaled value | `den > 0` |
| mean difference | 1e-4 units | each group mean rounded half away from zero |
| p-value bucket | `Int` | `-1` unknown, `0` >= 0.05, `1` < 0.05, `2` < 0.01, `3` < 0.001 |

## API

| Function | Returns | Description |
|---|---|---|
| `stats_tests_scale()` | `Int` | Fixed-point scale (10000). |
| `stats_tests_lcg_multiplier()` / `stats_tests_lcg_modulus()` | `Int` | Permutation LCG constants (48271 / 2147483647). |
| `stats_tests_lcg_step(state)` | `Int` | One normalized MINSTD step (KAT-friendly). |
| `stats_tests_p_bucket_*` accessors | `Int` | Bucket code constants (`..._05`, `..._01`, `..._001`, `_not_significant`, `_unknown`). |
| `stats_tests_is_significant(bucket)` | `Bool` | `bucket >= 1`. |
| `stats_tests_ranks(&values)` | `Result[Vec[Int], Str]` | Average-tie ranks, scaled 1e-4, input order. |
| `stats_tests_wilcoxon_u(&a, &b)` | `Result[WilcoxonResult, Str]` | Rank sums, `u_a`, `u_b`, sizes and p-bucket. |
| `stats_tests_wilcoxon_rank_sum_a/_b(&r)` | `Int` | Scaled pooled rank sums. |
| `stats_tests_wilcoxon_u_a/_b(&r)` | `Int` | Scaled U statistics. |
| `stats_tests_wilcoxon_n_a/_b(&r)` | `Int` | Group sizes. |
| `stats_tests_wilcoxon_p_bucket_of(&r)` | `Int` | Two-sided p-bucket of `min(u_a, u_b)`. |
| `stats_tests_wilcoxon_p_bucket(u, n_a, n_b)` | `Int` | Bucket for any scaled U (internally uses the smaller side). |
| `stats_tests_chi_square_gof(&observed, &expected)` | `Result[ChiSquareResult, Str]` | Exact GoF rational against integer expectations. |
| `stats_tests_chi_square_independence(&table, n_rows, n_cols)` | `Result[ChiSquareResult, Str]` | Exact independence rational over a row-major count table. |
| `stats_tests_chi_square_num/_den/_scaled/_df/_p_bucket_of(&r)` | `Int` | Chi-square result accessors. |
| `stats_tests_chi_square_p_bucket(chi2_scaled, df)` | `Int` | Upper-tail bucket for df 1..10. |
| `stats_tests_sign_test(&diffs)` | `Result[SignTestResult, Str]` | Sign counts (zeros dropped), statistic and p-bucket. |
| `stats_tests_sign_n_plus/_n_minus/_n_zero/_stat/_p_bucket_of(&r)` | `Int` | Sign-test accessors. |
| `stats_tests_sign_p_bucket(k, n)` | `Int` | Exact two-sided binomial bucket, n = 1..20. |
| `stats_tests_permutation_test(&a, &b, seed, n_perm)` | `Result[PermutationResult, Str]` | Deterministic seeded mean-difference permutation test. |
| `stats_tests_permutation_observed_diff/_extreme/_n_perm/_p_bucket_of(&r)` | `Int` | Permutation accessors. |
| `stats_tests_permutation_p_bucket(extreme, n_perm)` | `Int` | Exact `extreme / n_perm` bucket. |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.stats_tests;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // Average-tie ranks, scaled 1e-4: [10000, 25000, 25000, 40000].
  var data = Vec[Int].new();
  data.push(10); data.push(20); data.push(20); data.push(30);
  let ranks = stats_tests_ranks(&data);
  if ranks.is_ok {
    let r = ranks.value;
    io.println(convert.int_to_string(r[1])); // 25000
  }

  // Wilcoxon rank-sum on two separated samples: bucket 1 (p < 0.05).
  var a = Vec[Int].new();
  a.push(1); a.push(2); a.push(3); a.push(4);
  var b = Vec[Int].new();
  b.push(5); b.push(6); b.push(7); b.push(8);
  let w = stats_tests_wilcoxon_u(&a, &b);
  if w.is_ok {
    let res = w.value;
    io.println(convert.int_to_string(stats_tests_wilcoxon_u_a(&res)));   // 0
    io.println(convert.int_to_string(stats_tests_wilcoxon_p_bucket_of(&res))); // 1
  }
  return 0;
}
```

## Install / publish

```
xiom pkg install xiom.stats-tests@0.1.0     # consumer (once published)
xiom pkg publish                            # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Until the package is published, use it from this monorepo with
`.\scripts\port.ps1 -Package xiom.stats-tests`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.stats-tests
```

Expected tail: 25 `[PASS]` lines, `xiom.stats-tests: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`. Verified with the
pinned compiler 0.62.1 and the repo stdlib.

## Limitations

- **Fixed-point only.** Every non-integer quantity is scaled by 1e-4; the
  module never sees a float. Comparisons of scaled statistics to scaled
  critical values can differ from the exact real comparison by at most 5e-5.
- **Bucket tables are small and documented.** Wilcoxon U: exact tables for
  sample sizes 2..8 (two-sided, 0.05 / 0.01 / 0.001 where reachable). Sign
  test: exact binomial tables for n = 1..20. Chi-square: standard upper-tail
  quantiles for df 1..10. Larger samples return bucket `-1` ("outside the
  curated table") rather than an approximation.
- **No asymptotic (normal/Wald) approximations.** The module deliberately
  reports exact integer statistics and table-driven buckets only.
- **Permutation p-values carry a Monte-Carlo error** proportional to
  `1/sqrt(n_perm)` and use no pseudo-count, so `extreme == 0` yields bucket 3;
  raise `n_perm` and/or add a continuity correction outside the module if that
  matters.
- **Overflow envelope.** Unordered summation paths (permutation group sums)
  and the raw summations are not guarded: keep every group sum times 10000
  inside `Int` (`|sum| <= 922337203685477`). The exact chi-square accumulator
  and its lcm/scale steps *are* guarded and return typed errors.
- **Not implemented:** t-test, ANOVA, Kolmogorov-Smirnov, Fisher exact test and
  regression (the placeholder reserved some of these); they need distribution
  functions this integer-only module does not provide.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
