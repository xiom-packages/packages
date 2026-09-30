// XIOM -- xiom.stats-tests package manifest
// Port task: promote the xiom.stats-tests placeholder to a real, tested,
// pure-XIOM package (exact integer statistics, fixed point 1e-4, curated
// p-value buckets).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing from it; the
// tests use xiom.test, xiom.io and xiom.string.compare.
//
// The manifest lists the actual declared module name (xiom.stats_tests, with
// an underscore): `xiom.stats.tests` would collide with the stdlib namespace
// xiom.stats.test under the section-4 module namespace rule.

package xiom_stats_tests {
  name: "xiom.stats-tests";
  version: "0.1.0";
  description: "Exact integer statistical tests at fixed point 1e-4: average-tie ranks, Wilcoxon rank-sum U, chi-square goodness-of-fit and independence, sign test and a deterministic seeded permutation test, with curated p-value buckets";
  categories: ["data", "science"];
  keywords: ["statistics", "hypothesis-testing", "ranks", "wilcoxon", "mann-whitney", "chi-square", "sign-test", "permutation", "fixed-point"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.stats_tests"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
