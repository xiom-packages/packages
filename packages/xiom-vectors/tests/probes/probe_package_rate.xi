// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: xiom.rate 0.2.0 package gate (adoption 2026-10-10; see
// docs/XIOM-RATE-ADOPTION.md). Direct consumption checks, independent of
// the service seam:
//   - TokenBucket: constructor clamp + full start, exact burst drain,
//     whole-second refill, sub-token remainder carry (the accuracy delta
//     vs the pre-adoption lane limiter), rate 0, retry_after_ms, cost
//     spending;
//   - WindowLimit: fixed span admit/rebase, count + retry_after;
//   - keyed layers: first-use creation, per-key isolation, bookkeeping
//     (tokens/contains/remove/prune) and keyed window spans.
// The lane-side surface lives in probe_service_auth / probe_metrics (same
// expectations through rate_limiter_new/allow).
// Exit = failed checks.

module probe_package_rate

use xiom.rate;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn main() -> Int {
  io.println("=== xvector probe: xiom.rate package adoption ===");
  var fails: Int = 0;

  // ---- token bucket: constructor + exact burst drain ----
  var b = rate_bucket_new(2, 1, 0);
  fails = check(rate_bucket_capacity(&b) == 2 && rate_bucket_tokens(&b) == 2,
    "bucket: new(2, 1/s) starts full at capacity", fails);
  var d1 = rate_bucket_allow(&mut b, 0, 1);
  var d2 = rate_bucket_allow(&mut b, 0, 1);
  var d3 = rate_bucket_allow(&mut b, 0, 1);
  fails = check(d1 && d2 && !d3 && rate_bucket_tokens(&b) == 0,
    "bucket: burst drains exactly capacity (2 admit, 3rd denied)", fails);

  // ---- whole-second refill ----
  var r1 = rate_bucket_allow(&mut b, 1000, 1);
  var r2 = rate_bucket_allow(&mut b, 1000, 1);
  fails = check(r1 && !r2, "bucket: refill 1/s grants one token at +1000ms", fails);

  // ---- sub-token remainder is carried (the adoption's accuracy delta) ----
  var c = rate_bucket_new(1, 1, 0);
  var c1 = rate_bucket_allow(&mut c, 0, 1);     // spend the only token
  var c2 = rate_bucket_allow(&mut c, 500, 1);   // gained 0 this call
  var c3 = rate_bucket_allow(&mut c, 1000, 1);  // 500 + 500 carried -> 1 token
  var c4 = rate_bucket_allow(&mut c, 1500, 1);  // nothing new yet
  fails = check(c1 && !c2 && c3 && !c4,
    "bucket: fractional refill carried exactly (500+500 -> token at 1000ms)", fails);

  // ---- rate 0 never refills; constructor clamps ----
  var z = rate_bucket_new(1, 0, 0);
  var z1 = rate_bucket_allow(&mut z, 0, 1);
  var z2 = rate_bucket_allow(&mut z, 100000, 1);
  fails = check(z1 && !z2, "bucket: rate 0 never refills", fails);
  var cl = rate_bucket_new(-5, -3, 0);
  fails = check(rate_bucket_capacity(&cl) == 1,
    "bucket: constructor clamps capacity >= 1 (refill >= 0)", fails);

  // ---- retry_after_ms ----
  var e = rate_bucket_new(1, 1, 0);
  rate_bucket_allow(&mut e, 0, 1);               // empty now
  var e0 = rate_bucket_retry_after_ms(&e, 1);    // 1000
  var e1 = rate_bucket_retry_after_ms(&e, 0);    // 0 (cost <= 0)
  var z3 = rate_bucket_new(1, 0, 0);
  rate_bucket_allow(&mut z3, 0, 1);
  var e2 = rate_bucket_retry_after_ms(&z3, 1);   // -1 (never at rate 0)
  fails = check(e0 == 1000 && e1 == 0 && e2 == -1,
    "bucket: retry_after_ms (1000 / 0 / -1 on rate 0)", fails);

  // ---- cost spending ----
  var cb = rate_bucket_new(3, 0, 0);
  var ok_cost = rate_bucket_allow(&mut cb, 0, 5);   // over-capacity -> denied
  var ok_cost2 = rate_bucket_allow(&mut cb, 0, 2);  // spends 2
  fails = check(!ok_cost && ok_cost2 && rate_bucket_tokens(&cb) == 1,
    "bucket: cost spending (over-capacity denied; cost 2 leaves 1)", fails);

  // ---- fixed window ----
  var w = rate_window_new(1000, 2, 0);
  var w1 = rate_window_allow(&mut w, 0);
  var w2 = rate_window_allow(&mut w, 500);
  var w3 = rate_window_allow(&mut w, 999);
  var w4 = rate_window_allow(&mut w, 1000);   // span elapsed -> rebase -> admit
  fails = check(w1 && w2 && !w3 && w4 && rate_window_count(&w) == 1,
    "window: 2/1000ms admits 2, blocks, rebases at +1000ms", fails);
  rate_window_allow(&mut w, 1000);            // count 2 (span full)
  fails = check(rate_window_count(&w) == 2 && rate_window_retry_after_ms(&w, 1000) == 1000,
    "window: count/retry_after on a full span (1000ms)", fails);

  // ---- keyed buckets ----
  var kb = rate_keyed_new(1, 0);
  var k1 = rate_keyed_allow(&mut kb, "a", 0);   // created full -> admit
  var k2 = rate_keyed_allow(&mut kb, "a", 0);   // drained at rate 0 -> deny
  var k3 = rate_keyed_allow(&mut kb, "b", 0);   // separate key -> admit
  fails = check(k1 && !k2 && k3 && rate_keyed_count(&kb) == 2,
    "keyed: first-use creation + per-key isolation", fails);
  var ktok = rate_keyed_tokens(&kb, "a", 0);    // 0 after the drain
  var khas = rate_keyed_contains(&kb, "b");
  var krm = rate_keyed_remove(&mut kb, "a");
  var krm2 = rate_keyed_remove(&mut kb, "a");   // already gone
  fails = check(ktok == 0 && khas && krm && !krm2 && rate_keyed_count(&kb) == 1,
    "keyed: tokens/contains/remove bookkeeping", fails);
  var kbx = rate_keyed_new(1, 1);
  rate_keyed_allow(&mut kbx, "x", 0);           // drained, not full
  fails = check(rate_keyed_prune(&mut kbx, 1000) == 1 && rate_keyed_count(&kbx) == 0,
    "keyed: prune drops the settled-full bucket", fails);

  // ---- keyed windows ----
  var kw = rate_window_keyed_new(1000, 1);
  var kw1 = rate_window_keyed_allow(&mut kw, "k", 0);    // admit
  var kw2 = rate_window_keyed_allow(&mut kw, "k", 500);  // span full
  var kw3 = rate_window_keyed_allow(&mut kw, "k", 1000); // rebase -> admit
  fails = check(kw1 && !kw2 && kw3 && rate_window_keyed_count(&kw, "k", 1000) == 1,
    "window keyed: per-key spans rebase at +window", fails);

  io.println("");
  io.println("probe_package_rate: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
