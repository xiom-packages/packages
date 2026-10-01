// XIOM -- xiom.defi conformance tests (28 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixture-driven deterministic checks of the documented xiom.defi API:
// constant-product quotes, fees, slippage/min-out, LP mint/burn round trips
// and the k-growth invariant, then lending share indexes, per-tick accrual,
// health factor, collateral ratio and liquidation close-factor/bonus math.
//
// All expectations are exact integers produced by the documented truncating
// arithmetic at scale 1e-4 (DEFI_SCALE = 10000). Direct calls only: results
// are read back from struct fields and through small classifier helpers, with
// no fn tables and no Vec[Str] text comparisons.

module defi_tests
use xiom.io; use xiom.test; use xiom.defi; use xiom.core;

// Swap classifier: Ok(output) as the output amount, Err(_) as -1. Keeping
// the match out of the test bodies lets each check stay branch-free.
fn swap_code(p: &mut AmmPool, amount_in: Int, min_out: Int, a_to_b: Bool) -> Int {
  match amm_swap(p, amount_in, min_out, a_to_b) {
    Ok(out) => { return out; },
    Err(_) => { return -1; },
  }
}

// A 100000/100000 pool with a 30 bps fee (1.0 seed share per base unit).
fn amm_even_fixture() -> AmmPool {
  return amm_new(100000, 100000, 30);
}

// A 100000/200000 pool with 100000 LP shares already outstanding: LP price
// is 1 share per unit of A and 0.5 shares per unit of B.
fn amm_pair_fixture() -> AmmPool {
  return AmmPool{ reserve_a: 100000; reserve_b: 200000; lp_total: 100000; fee_bps: 0; };
}

// The pair fixture immediately after amm_mint(10000, 20000).
fn amm_after_mint_fixture() -> AmmPool {
  return AmmPool{ reserve_a: 110000; reserve_b: 220000; lp_total: 110000; fee_bps: 0; };
}

// A lending pool with 1000 bps reserve factor, 100000 supplied and 50000
// borrowed at index 1.0.
fn lend_active_fixture() -> LendPool {
  var p = lend_new(1000);
  let supplied = lend_supply(&mut p, 100000);
  let borrowed = lend_borrow(&mut p, 50000);
  return p;
}

fn t01_amm_new_seeds_and_clamps() -> TestResult {
  let p = amm_new(100000, 400000, 30);
  var ok = p.reserve_a == 100000 && p.reserve_b == 400000 && p.fee_bps == 30;
  if p.lp_total != 200000 { ok = false; }
  let q = amm_new(-5, 100, 20000);
  if q.reserve_a != 0 || q.reserve_b != 100 || q.fee_bps != 10000 || q.lp_total != 0 { ok = false; }
  let r = amm_new(1, 1, -3);
  if r.fee_bps != 0 || r.lp_total != 1 { ok = false; }
  return assert(ok, "amm_new seeds sqrt(k) shares and clamps reserves and fee");
}

fn t02_amm_fee_amount_truncates() -> TestResult {
  var ok = amm_fee_amount(1000, 30) == 3;
  if amm_fee_amount(999, 30) != 2 { ok = false; }
  if amm_fee_amount(50, 30) != 0 { ok = false; }
  if amm_fee_amount(0, 30) != 0 { ok = false; }
  if amm_fee_amount(-5, 30) != 0 { ok = false; }
  if amm_fee_amount(100, 20000) != 100 { ok = false; }
  return assert(ok, "fee floors toward the trader and the fee rate is clamped to 10000");
}

fn t03_amm_out_no_fee() -> TestResult {
  var ok = amm_get_amount_out(100000, 100000, 10000, 0) == 9090;
  if amm_get_amount_out(100000, 200000, 10000, 0) != 18181 { ok = false; }
  return assert(ok, "zero-fee output is floor(in * reserve_out / (reserve_in + in))");
}

fn t04_amm_out_with_fee() -> TestResult {
  var ok = amm_get_amount_out(100000, 100000, 10000, 30) == 9066;
  if amm_get_amount_out(100000, 100000, 10000, 10000) != 0 { ok = false; }
  return assert(ok, "30 bps fee yields 9066 and a 100% fee yields nothing");
}

fn t05_amm_out_guards() -> TestResult {
  var ok = amm_get_amount_out(0, 100, 10, 0) == 0;
  if amm_get_amount_out(100, 0, 10, 0) != 0 { ok = false; }
  if amm_get_amount_out(100, 100, 0, 0) != 0 { ok = false; }
  if amm_get_amount_out(100, 100, -1, 0) != 0 { ok = false; }
  return assert(ok, "quotes are 0 for non-positive reserves or amounts");
}

fn t06_amm_in_inverse() -> TestResult {
  var ok = amm_get_amount_in(100000, 100000, 9066, 30) == 10000;
  if amm_get_amount_in(100000, 100000, 9090, 0) != 9999 { ok = false; }
  if amm_get_amount_in(100000, 100000, 100000, 0) != 0 { ok = false; }
  if amm_get_amount_in(100000, 100000, 10, 10000) != 0 { ok = false; }
  return assert(ok, "amount-in uses ceiling divisions and rejects unserviceable quotes");
}

fn t07_amm_spot_price() -> TestResult {
  var ok = amm_spot_price_bps(100000, 200000) == 20000;
  if amm_spot_price_bps(300000, 100000) != 3333 { ok = false; }
  if amm_spot_price_bps(0, 100) != 0 { ok = false; }
  if amm_spot_price_bps(100, -5) != 0 { ok = false; }
  return assert(ok, "spot price is floor(reserve_b * 10000 / reserve_a)");
}

fn t08_amm_swap_moves_reserves() -> TestResult {
  var p = amm_even_fixture();
  let out = swap_code(&mut p, 10000, 9000, true);
  var ok = out == 9066;
  if p.reserve_a != 110000 || p.reserve_b != 90934 { ok = false; }
  if p.lp_total != 100000 { ok = false; }
  if p.reserve_a * p.reserve_b != 10002740000 { ok = false; }
  if !amm_k_check(100000, 100000, p.reserve_a, p.reserve_b) { ok = false; }
  return assert(ok, "swap 10000 A for 9066 B and k grows from 1e10 to 10002740000");
}

fn t09_amm_swap_slippage_leaves_state() -> TestResult {
  var p = amm_even_fixture();
  let out = swap_code(&mut p, 10000, 9067, true);
  var ok = out == -1;
  if p.reserve_a != 100000 || p.reserve_b != 100000 || p.lp_total != 100000 { ok = false; }
  return assert(ok, "a swap below min_out is rejected and leaves the pool unchanged");
}

fn t10_amm_swap_invalid_inputs() -> TestResult {
  var p = amm_even_fixture();
  var ok = swap_code(&mut p, 0, 0, true) == -1;
  if swap_code(&mut p, -5, 0, true) != -1 { ok = false; }
  if p.reserve_a != 100000 || p.reserve_b != 100000 { ok = false; }
  var empty = amm_new(0, 100, 30);
  if swap_code(&mut empty, 10, 0, true) != -1 { ok = false; }
  if empty.reserve_b != 100 { ok = false; }
  return assert(ok, "non-positive input and empty reserves are rejected without state change");
}

fn t11_amm_swap_reverse_direction() -> TestResult {
  var p = amm_even_fixture();
  let out = swap_code(&mut p, 10000, 9000, false);
  var ok = out == 9066;
  if p.reserve_b != 110000 || p.reserve_a != 90934 { ok = false; }
  return assert(ok, "b_to_a sells B into the B reserve and shrinks the A reserve");
}

fn t12_amm_k_growth_invariant() -> TestResult {
  var ok = amm_k_check(100000, 100000, 110000, 90934);
  if !amm_k_check(100000, 100000, 100000, 100000) { ok = false; }
  if amm_k_check(100000, 100000, 99000, 100000) { ok = false; }
  let p = amm_new(100000, 100000, 30);
  if amm_k(&p) != 10000000000 { ok = false; }
  return assert(ok, "k-check accepts non-shrinking states, rejects shrinkage and reads k");
}

fn t13_amm_mint_proportional() -> TestResult {
  var p = amm_pair_fixture();
  let shares = amm_mint(&mut p, 10000, 20000);
  var ok = shares == 10000;
  if p.reserve_a != 110000 || p.reserve_b != 220000 || p.lp_total != 110000 { ok = false; }
  return assert(ok, "proportional mint credits min(amount * lp / reserve) shares");
}

fn t14_amm_mint_rejects() -> TestResult {
  var p = amm_pair_fixture();
  var ok = amm_mint(&mut p, 0, 100) == 0;
  if amm_mint(&mut p, 5, -1) != 0 { ok = false; }
  if p.reserve_a != 100000 || p.reserve_b != 200000 || p.lp_total != 100000 { ok = false; }
  var q = AmmPool{ reserve_a: 1000000; reserve_b: 2000000; lp_total: 100000; fee_bps: 0; };
  if amm_mint(&mut q, 1, 1) != 0 { ok = false; }
  if q.lp_total != 100000 { ok = false; }
  return assert(ok, "non-positive and dust mints are rejected without state change");
}

fn t15_amm_burn_round_trip() -> TestResult {
  var p = amm_after_mint_fixture();
  let (amount_a, amount_b) = amm_burn(&mut p, 10000);
  var ok = amount_a == 10000 && amount_b == 20000;
  if p.reserve_a != 100000 || p.reserve_b != 200000 || p.lp_total != 100000 { ok = false; }
  return assert(ok, "burning the minted shares restores the original reserves exactly");
}

fn t16_amm_burn_guards() -> TestResult {
  var p = amm_after_mint_fixture();
  let (a0, b0) = amm_burn(&mut p, 0);
  var ok = a0 == 0 && b0 == 0;
  let (a1, b1) = amm_burn(&mut p, 110001);
  if a1 != 0 || b1 != 0 { ok = false; }
  if p.reserve_a != 110000 || p.reserve_b != 220000 || p.lp_total != 110000 { ok = false; }
  var q = amm_pair_fixture();
  let (a2, b2) = amm_burn(&mut q, 100000);
  if a2 != 100000 || b2 != 200000 { ok = false; }
  if q.reserve_a != 0 || q.reserve_b != 0 || q.lp_total != 0 { ok = false; }
  return assert(ok, "burn rejects invalid share counts and a full burn drains exactly");
}

fn t17_amm_burn_partial() -> TestResult {
  var p = amm_after_mint_fixture();
  let (amount_a, amount_b) = amm_burn(&mut p, 50000);
  var ok = amount_a == 50000 && amount_b == 100000;
  if p.reserve_a != 60000 || p.reserve_b != 120000 || p.lp_total != 60000 { ok = false; }
  return assert(ok, "partial burn withdraws the proportional share of both reserves");
}

fn t18_amm_saturation_guard() -> TestResult {
  var ok = amm_get_amount_out(core.INT_MAX, core.INT_MAX, core.INT_MAX, 0) == 1;
  if amm_fee_amount(core.INT_MAX, 10000) != 922337203685477 { ok = false; }
  return assert(ok, "saturating guards keep extreme products deterministic instead of wrapping");
}

fn t19_lend_new_and_supply() -> TestResult {
  var p = lend_new(1000);
  var ok = p.supply_index == 10000 && p.borrow_index == 10000 && p.reserve_bps == 1000;
  let shares = lend_supply(&mut p, 100000);
  if shares != 100000 { ok = false; }
  if p.supply_shares != 100000 || p.supply_index != 10000 { ok = false; }
  if p.supply_shares * p.supply_index / 10000 != 100000 { ok = false; }
  if lend_supply(&mut p, 0) != 0 { ok = false; }
  if lend_supply(&mut p, -5) != 0 { ok = false; }
  return assert(ok, "supply mints shares at index 1.0 and rejects non-positive amounts");
}

fn t20_lend_borrow_and_limits() -> TestResult {
  var p = lend_new(1000);
  let supplied = lend_supply(&mut p, 100000);
  var ok = lend_borrow(&mut p, 100001) == 0;
  if lend_borrow(&mut p, 50000) != 50000 { ok = false; }
  if lend_borrow(&mut p, 50001) != 0 { ok = false; }
  if lend_borrow(&mut p, 50000) != 50000 { ok = false; }
  if p.borrow_shares != 100000 { ok = false; }
  if p.borrow_shares * p.borrow_index / 10000 != 100000 { ok = false; }
  return assert(ok, "borrow mints shares and never exceeds available liquidity");
}

fn t21_lend_accrue_two_ticks() -> TestResult {
  var p = lend_active_fixture();
  let interest = lend_accrue(&mut p, 100, 2);
  var ok = interest == 905;
  if p.supply_index != 10090 || p.borrow_index != 10201 { ok = false; }
  if p.supply_shares != 100000 || p.borrow_shares != 50000 { ok = false; }
  if p.supply_shares * p.supply_index / 10000 != 100900 { ok = false; }
  if p.borrow_shares * p.borrow_index / 10000 != 51005 { ok = false; }
  return assert(ok, "two 1% ticks compound the borrow index to 10201 and credit 905 to suppliers");
}

fn t22_lend_accrue_noop_and_monotone() -> TestResult {
  var p = lend_active_fixture();
  var ok = lend_accrue(&mut p, 100, 0) == 0;
  if lend_accrue(&mut p, 0, 5) != 0 { ok = false; }
  if lend_accrue(&mut p, -50, 5) != 0 { ok = false; }
  if p.supply_index != 10000 || p.borrow_index != 10000 { ok = false; }
  let credited = lend_accrue(&mut p, 50, 3);
  if credited <= 0 { ok = false; }
  if p.supply_index < 10000 || p.borrow_index < 10000 { ok = false; }
  return assert(ok, "accrual is a no-op for non-positive ticks or rate and never decreases indexes");
}

fn t23_lend_read_helpers() -> TestResult {
  let p = lend_new(1000);
  var ok = lend_total_supply(&p) == 0;
  if lend_total_borrow(&p) != 0 { ok = false; }
  if lend_supply_balance(&p, 0) != 0 { ok = false; }
  if lend_supply_balance(&p, 5) != 5 { ok = false; }
  if lend_borrow_balance(&p, 5) != 5 { ok = false; }
  if !lend_check_indexes(&p, 10000, 10000) { ok = false; }
  if lend_check_indexes(&p, 10001, 10000) { ok = false; }
  return assert(ok, "empty-pool totals value shares at 1.0 and the invariant checks indexes");
}

fn t24_lend_round_trip_and_guards() -> TestResult {
  var p = lend_new(1000);
  var ok = lend_supply(&mut p, 100000) == 100000;
  if lend_withdraw(&mut p, 100000) != 100000 { ok = false; }
  if p.supply_shares != 0 { ok = false; }
  if lend_supply(&mut p, 123456) != 123456 { ok = false; }
  if lend_withdraw(&mut p, 23456) != 23456 { ok = false; }
  if p.supply_shares != 100000 { ok = false; }
  if lend_withdraw(&mut p, 0) != 0 { ok = false; }
  if lend_withdraw(&mut p, 100001) != 0 { ok = false; }
  if p.supply_shares != 100000 { ok = false; }
  return assert(ok, "supply/withdraw round-trips at 1.0 and invalid share counts are rejected");
}

fn t25_lend_lifecycle_after_accrual() -> TestResult {
  var p = lend_active_fixture();
  let interest = lend_accrue(&mut p, 100, 2);
  var ok = interest == 905;
  if lend_withdraw(&mut p, 100000) != 0 { ok = false; }
  if p.supply_shares != 100000 { ok = false; }
  if lend_withdraw(&mut p, 40000) != 40360 { ok = false; }
  if p.supply_shares != 60000 { ok = false; }
  if lend_repay(&mut p, 50000) != 51005 { ok = false; }
  if p.borrow_shares != 0 { ok = false; }
  if lend_withdraw(&mut p, 60000) != 60540 { ok = false; }
  if p.supply_shares != 0 || p.borrow_shares != 0 { ok = false; }
  return assert(ok, "withdrawals respect available liquidity; repayment unlocks the full exit");
}

fn t26_lend_repay_guards() -> TestResult {
  var p = lend_active_fixture();
  let repaid = lend_repay(&mut p, 50000);
  var ok = repaid == 50000;
  if p.borrow_shares != 0 { ok = false; }
  if lend_repay(&mut p, 1) != 0 { ok = false; }
  if lend_repay(&mut p, 0) != 0 { ok = false; }
  return assert(ok, "repay burns borrow shares at index 1.0 and rejects empty or invalid repayments");
}

fn t27_lend_health_and_ratio() -> TestResult {
  var ok = lend_collateral_ratio_bps(150000, 100000) == 15000;
  if lend_collateral_ratio_bps(100000, 100000) != 10000 { ok = false; }
  if lend_collateral_ratio_bps(50000, 100000) != 5000 { ok = false; }
  if lend_collateral_ratio_bps(100000, 0) != core.INT_MAX { ok = false; }
  if lend_collateral_ratio_bps(0, 100) != 0 { ok = false; }
  if lend_health_factor_bps(150000, 100000, 8000) != 12000 { ok = false; }
  if lend_health_factor_bps(75000, 100000, 8000) != 6000 { ok = false; }
  if lend_is_liquidatable(10000) { ok = false; }
  if !lend_is_liquidatable(9999) { ok = false; }
  if !lend_is_liquidatable(6000) { ok = false; }
  if lend_is_liquidatable(12000) { ok = false; }
  return assert(ok, "collateral ratio, health factor and the 1.0 liquidation boundary are exact");
}

fn t28_lend_liquidation_amounts() -> TestResult {
  let (repay, seize) = lend_liquidation_amounts(100002, 150000, 5000, 800);
  var ok = repay == 50001 && seize == 54002;
  let (repay2, seize2) = lend_liquidation_amounts(100000, 30000, 10000, 1000);
  if repay2 != 100000 || seize2 != 30000 { ok = false; }
  let (repay3, seize3) = lend_liquidation_amounts(100000, 300000, 20000, 0);
  if repay3 != 100000 || seize3 != 100000 { ok = false; }
  let (repay4, seize4) = lend_liquidation_amounts(0, 100, 5000, 800);
  if repay4 != 0 || seize4 != 0 { ok = false; }
  let (repay5, seize5) = lend_liquidation_amounts(100000, 0, 5000, 800);
  if repay5 != 0 || seize5 != 0 { ok = false; }
  return assert(ok, "liquidation applies the close factor, ceilings the bonus and caps at collateral");
}

fn main() -> Int {
  io.println("=== xiom.defi conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_amm_new_seeds_and_clamps();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_amm_fee_amount_truncates();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_amm_out_no_fee();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_amm_out_with_fee();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_amm_out_guards();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_amm_in_inverse();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_amm_spot_price();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_amm_swap_moves_reserves();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_amm_swap_slippage_leaves_state();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_amm_swap_invalid_inputs();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_amm_swap_reverse_direction();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_amm_k_growth_invariant();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_amm_mint_proportional();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_amm_mint_rejects();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_amm_burn_round_trip();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_amm_burn_guards();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_amm_burn_partial();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_amm_saturation_guard();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_lend_new_and_supply();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_lend_borrow_and_limits();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_lend_accrue_two_ticks();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_lend_accrue_noop_and_monotone();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_lend_read_helpers();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_lend_round_trip_and_guards();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25_lend_lifecycle_after_accrual();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26_lend_repay_guards();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27_lend_health_and_ratio();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28_lend_liquidation_amounts();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.defi: all tests passed");
  } else {
    io.println("xiom.defi: tests failed");
  }
  return failed;
}
