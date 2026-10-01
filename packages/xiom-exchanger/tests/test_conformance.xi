// XIOM -- xiom.exchanger conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Direct-call, fixture-driven tests for the pure deterministic integer limit
// order book: price-time priority, partial fills, maker/taker fees in bps,
// market order IOC semantics, cancel/replace, the sequence-numbered tape,
// top-N depth aggregation, OHLCV candles over tick buckets and the full
// invariant checker. Vec[Int] element reads always go through typed let
// bindings (XIOM v0.62.2 lowering rule); prices are ticks and fees are
// integer notional * bps / 10000 truncated toward zero.

module exchanger_tests
use xiom.io; use xiom.test; use xiom.exchanger;

// --- fixtures ---------------------------------------------------------------

fn no_fee_book() -> XchgOrderBook {
  return xchg_book_new(0, 0);
}

// --- priority and matching --------------------------------------------------

fn t01_rest_and_best() -> TestResult {
  var b = no_fee_book();
  let id1 = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 10);
  let id2 = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 101, 4);
  let id3 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 105, 7);
  var ok = id1 == 1;
  if id2 != 2 { ok = false; }
  if id3 != 3 { ok = false; }
  if xchg_best_bid(&b) != 101 { ok = false; }
  if xchg_best_ask(&b) != 105 { ok = false; }
  if xchg_trade_count(&b) != 0 { ok = false; }
  if xchg_open_order_count(&b) != 3 { ok = false; }
  if xchg_open_bid_qty(&b) != 14 { ok = false; }
  if xchg_open_ask_qty(&b) != 7 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "limit orders rest with best bid 101, best ask 105 and no trades");
}

fn t02_cross_at_maker_price() -> TestResult {
  var b = no_fee_book();
  let s = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 8);
  let t = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 103, 3);
  var ok = t == 2;
  if xchg_trade_count(&b) != 1 { ok = false; }
  if xchg_best_ask(&b) != 100 { ok = false; }
  if xchg_order_remaining(&b, s) != 5 { ok = false; }
  if xchg_order_status(&b, s) != XCHG_STATUS_OPEN { ok = false; }
  if xchg_order_remaining(&b, t) != 0 { ok = false; }
  if xchg_order_status(&b, t) != XCHG_STATUS_FILLED { ok = false; }
  let tp = xchg_tape_prices(&b);
  let tq = xchg_tape_qtys(&b);
  let ts = xchg_tape_taker_sides(&b);
  let tm = xchg_tape_maker_ids(&b);
  let tt = xchg_tape_taker_ids(&b);
  let tp0: Int = tp[0];
  let tq0: Int = tq[0];
  let ts0: Int = ts[0];
  let tm0: Int = tm[0];
  let tt0: Int = tt[0];
  if tp0 != 100 { ok = false; }
  if tq0 != 3 { ok = false; }
  if ts0 != XCHG_SIDE_BUY { ok = false; }
  if tm0 != s { ok = false; }
  if tt0 != t { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "a crossing buy takes the resting ask price (maker price) and partially fills it");
}

fn t03_price_priority() -> TestResult {
  var b = no_fee_book();
  let a1 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 101, 5);
  let a2 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 5);
  let t = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 101, 3);
  let tp = xchg_tape_prices(&b);
  let tm = xchg_tape_maker_ids(&b);
  let tp0: Int = tp[0];
  let tm0: Int = tm[0];
  var ok = xchg_trade_count(&b) == 1;
  if tp0 != 100 { ok = false; }
  if tm0 != a2 { ok = false; }
  if xchg_order_remaining(&b, a2) != 2 { ok = false; }
  if xchg_order_remaining(&b, a1) != 5 { ok = false; }
  if xchg_best_ask(&b) != 100 { ok = false; }
  if xchg_order_status(&b, a1) != XCHG_STATUS_OPEN { ok = false; }
  if xchg_order_status(&b, t) != XCHG_STATUS_FILLED { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "price priority: the cheaper ask trades first regardless of arrival");
}

fn t04_time_priority() -> TestResult {
  var b = no_fee_book();
  let a1 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 4);
  let a2 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 4);
  let t = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 6);
  let tm = xchg_tape_maker_ids(&b);
  let tq = xchg_tape_qtys(&b);
  let tm0: Int = tm[0];
  let tm1: Int = tm[1];
  let tq0: Int = tq[0];
  let tq1: Int = tq[1];
  var ok = xchg_trade_count(&b) == 2;
  if tm0 != a1 { ok = false; }
  if tm1 != a2 { ok = false; }
  if tq0 != 4 { ok = false; }
  if tq1 != 2 { ok = false; }
  if xchg_best_ask(&b) != 100 { ok = false; }
  if xchg_order_remaining(&b, a2) != 2 { ok = false; }
  if xchg_order_status(&b, t) != XCHG_STATUS_FILLED { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "time priority: equal prices trade in arrival order (4 then 2)");
}

fn t05_partial_fill_rests() -> TestResult {
  var b = no_fee_book();
  let s = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 3);
  let t = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 5);
  var ok = xchg_trade_count(&b) == 1;
  if xchg_order_status(&b, s) != XCHG_STATUS_FILLED { ok = false; }
  if xchg_order_remaining(&b, s) != 0 { ok = false; }
  if xchg_order_status(&b, t) != XCHG_STATUS_OPEN { ok = false; }
  if xchg_order_remaining(&b, t) != 2 { ok = false; }
  if xchg_best_bid(&b) != 100 { ok = false; }
  if xchg_best_ask(&b) != XCHG_NONE { ok = false; }
  if xchg_open_order_count(&b) != 1 { ok = false; }
  if xchg_open_bid_qty(&b) != 2 { ok = false; }
  if xchg_open_ask_qty(&b) != 0 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "a partial fill rests the unfilled remainder on the book");
}

fn t06_sweep_multiple_levels() -> TestResult {
  var b = no_fee_book();
  let a1 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 4);
  let a2 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 101, 3);
  let a3 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 102, 5);
  let t = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 102, 10);
  let tp = xchg_tape_prices(&b);
  let tq = xchg_tape_qtys(&b);
  let tm = xchg_tape_maker_ids(&b);
  let p0: Int = tp[0];
  let p1: Int = tp[1];
  let p2: Int = tp[2];
  let q0: Int = tq[0];
  let q1: Int = tq[1];
  let q2: Int = tq[2];
  let m0: Int = tm[0];
  let m1: Int = tm[1];
  let m2: Int = tm[2];
  var ok = xchg_trade_count(&b) == 3;
  if p0 != 100 { ok = false; }
  if p1 != 101 { ok = false; }
  if p2 != 102 { ok = false; }
  if q0 != 4 { ok = false; }
  if q1 != 3 { ok = false; }
  if q2 != 3 { ok = false; }
  if m0 != a1 { ok = false; }
  if m1 != a2 { ok = false; }
  if m2 != a3 { ok = false; }
  if xchg_order_status(&b, t) != XCHG_STATUS_FILLED { ok = false; }
  if xchg_order_status(&b, a3) != XCHG_STATUS_OPEN { ok = false; }
  if xchg_order_remaining(&b, a3) != 2 { ok = false; }
  if xchg_best_ask(&b) != 102 { ok = false; }
  if xchg_open_ask_qty(&b) != 2 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "a marketable limit sweeps levels cheapest-first with stays at the last");
}

fn t07_market_sell_ioc() -> TestResult {
  var b = no_fee_book();
  let b1 = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 2);
  let b2 = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 99, 3);
  let m = xchg_submit_market(&mut b, XCHG_SIDE_SELL, 10);
  let tp = xchg_tape_prices(&b);
  let tq = xchg_tape_qtys(&b);
  let ts = xchg_tape_taker_sides(&b);
  let p0: Int = tp[0];
  let p1: Int = tp[1];
  let q0: Int = tq[0];
  let q1: Int = tq[1];
  let s0: Int = ts[0];
  let s1: Int = ts[1];
  var ok = xchg_trade_count(&b) == 2;
  if p0 != 100 { ok = false; }
  if p1 != 99 { ok = false; }
  if q0 != 2 { ok = false; }
  if q1 != 3 { ok = false; }
  if s0 != XCHG_SIDE_SELL { ok = false; }
  if s1 != XCHG_SIDE_SELL { ok = false; }
  if xchg_order_status(&b, m) != XCHG_STATUS_CANCELLED { ok = false; }
  if xchg_order_remaining(&b, m) != 5 { ok = false; }
  if xchg_open_order_count(&b) != 0 { ok = false; }
  if xchg_best_bid(&b) != XCHG_NONE { ok = false; }
  if xchg_order_status(&b, b1) != XCHG_STATUS_FILLED { ok = false; }
  if xchg_order_status(&b, b2) != XCHG_STATUS_FILLED { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "an oversized market sell sweeps all bids and cancels the IOC remainder");
}

fn t08_market_empty_book() -> TestResult {
  var b = no_fee_book();
  let m = xchg_submit_market(&mut b, XCHG_SIDE_BUY, 4);
  var ok = m == 1;
  if xchg_order_status(&b, m) != XCHG_STATUS_CANCELLED { ok = false; }
  if xchg_order_remaining(&b, m) != 4 { ok = false; }
  if xchg_trade_count(&b) != 0 { ok = false; }
  if xchg_best_ask(&b) != XCHG_NONE { ok = false; }
  if xchg_open_order_count(&b) != 0 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "a market order on an empty book fills nothing and cancels in full");
}

// --- cancel and replace -----------------------------------------------------

fn t09_cancel_live_order() -> TestResult {
  var b = no_fee_book();
  let a1 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 5);
  let a2 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 101, 3);
  var ok = xchg_cancel(&mut b, a1);
  if xchg_best_ask(&b) != 101 { ok = false; }
  if xchg_order_status(&b, a1) != XCHG_STATUS_CANCELLED { ok = false; }
  if xchg_order_remaining(&b, a1) != 5 { ok = false; }
  if xchg_cancel(&mut b, a1) { ok = false; }
  if xchg_cancel(&mut b, 99) { ok = false; }
  if xchg_open_order_count(&b) != 1 { ok = false; }
  if xchg_order_status(&b, a2) != XCHG_STATUS_OPEN { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "cancel removes a live order once and refuses terminal or unknown ids");
}

fn t10_cancel_middle_level() -> TestResult {
  var b = no_fee_book();
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 2);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 3);
  var ok = xchg_cancel(&mut b, 2);
  if xchg_open_order_count(&b) != 2 { ok = false; }
  if xchg_open_bid_qty(&b) != 4 { ok = false; }
  if xchg_best_bid(&b) != 100 { ok = false; }
  if xchg_trade_count(&b) != 0 { ok = false; }
  if xchg_order_status(&b, 2) != XCHG_STATUS_CANCELLED { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "cancelling a middle time-priority slot keeps the other bids intact");
}

fn t11_replace_is_cancel_plus_new() -> TestResult {
  var b = no_fee_book();
  let a1 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 5);
  let r1 = xchg_replace(&mut b, a1, 101, 7);
  var ok = r1 == 2;
  if xchg_order_status(&b, a1) != XCHG_STATUS_CANCELLED { ok = false; }
  if xchg_order_status(&b, r1) != XCHG_STATUS_OPEN { ok = false; }
  if xchg_order_remaining(&b, r1) != 7 { ok = false; }
  if xchg_best_ask(&b) != 101 { ok = false; }
  if xchg_open_order_count(&b) != 1 { ok = false; }
  let r2 = xchg_replace(&mut b, r1, 102, 4);
  if r2 != 3 { ok = false; }
  if xchg_order_status(&b, r1) != XCHG_STATUS_CANCELLED { ok = false; }
  if xchg_order_remaining(&b, r2) != 4 { ok = false; }
  if xchg_best_ask(&b) != 102 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "replace cancels the old id and rests a new order at the new price");
}

fn t12_replace_rejections() -> TestResult {
  var b = no_fee_book();
  let a1 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 5);
  var ok = xchg_replace(&mut b, a1, 0, 3) == 0;
  if xchg_replace(&mut b, a1, 101, 0) != 0 { ok = false; }
  if xchg_replace(&mut b, 42, 101, 3) != 0 { ok = false; }
  if xchg_order_status(&b, a1) != XCHG_STATUS_OPEN { ok = false; }
  if xchg_order_remaining(&b, a1) != 5 { ok = false; }
  if xchg_best_ask(&b) != 100 { ok = false; }
  if xchg_open_order_count(&b) != 1 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "an invalid or unknown replace returns 0 and leaves the old order live");
}

// --- fees -------------------------------------------------------------------

fn t13_maker_taker_fees() -> TestResult {
  var b = xchg_book_new(2, 5);
  let s = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 1000, 3);
  let t = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 1000, 3);
  let mf = xchg_tape_maker_fees(&b);
  let tf = xchg_tape_taker_fees(&b);
  let mf0: Int = mf[0];
  let tf0: Int = tf[0];
  var ok = xchg_trade_count(&b) == 1;
  if mf0 != 0 { ok = false; }
  if tf0 != 1 { ok = false; }
  if xchg_fees_maker_total(&b) != 0 { ok = false; }
  if xchg_fees_taker_total(&b) != 1 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "fees: qty 3 at price 1000 pays maker 0 (0.6) and taker 1 (1.5) at 2/5 bps");
}

fn t14_fee_truncation() -> TestResult {
  var b = xchg_book_new(2, 5);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 1000, 7);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 1000, 7);
  var ok = xchg_fees_maker_total(&b) == 1;
  if xchg_fees_taker_total(&b) != 3 { ok = false; }
  if xchg_fee(9999, 5) != 4 { ok = false; }
  if xchg_fee(19999, 5) != 9 { ok = false; }
  if xchg_fee(100, 0) != 0 { ok = false; }
  if xchg_fee(100, -3) != 0 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "fees truncate toward zero: 7000 at 2/5 bps is 1 and 3");
}

// --- tape, depth and candles ------------------------------------------------

fn t15_tape_sequence_and_last() -> TestResult {
  var b = no_fee_book();
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 101, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 102, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 102, 3);
  let sq = xchg_tape_seqs(&b);
  let ts = xchg_tape_taker_sides(&b);
  let tm = xchg_tape_maker_ids(&b);
  let s0: Int = sq[0];
  let s1: Int = sq[1];
  let s2: Int = sq[2];
  let k0: Int = ts[0];
  let k1: Int = ts[1];
  let k2: Int = ts[2];
  let m0: Int = tm[0];
  let m1: Int = tm[1];
  let m2: Int = tm[2];
  var ok = xchg_trade_count(&b) == 3;
  if s0 != 1 { ok = false; }
  if s1 != 2 { ok = false; }
  if s2 != 3 { ok = false; }
  if k0 != XCHG_SIDE_BUY { ok = false; }
  if k1 != XCHG_SIDE_BUY { ok = false; }
  if k2 != XCHG_SIDE_BUY { ok = false; }
  if m0 != 1 { ok = false; }
  if m1 != 2 { ok = false; }
  if m2 != 3 { ok = false; }
  if xchg_last_trade_price(&b) != 102 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "the tape numbers trades 1..n in execution order and tracks the last price");
}

fn t16_depth_bids() -> TestResult {
  var b = no_fee_book();
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 3);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 4);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 99, 5);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 101, 2);
  let d2 = xchg_depth_bids(&b, 2);
  let p0: Int = d2.prices[0];
  let p1: Int = d2.prices[1];
  let q0: Int = d2.qtys[0];
  let q1: Int = d2.qtys[1];
  var ok = d2.prices.len() == 2;
  if p0 != 101 { ok = false; }
  if p1 != 100 { ok = false; }
  if q0 != 2 { ok = false; }
  if q1 != 7 { ok = false; }
  let d0 = xchg_depth_bids(&b, 0);
  if d0.prices.len() != 0 { ok = false; }
  if d0.qtys.len() != 0 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "bid depth aggregates equal prices and returns at most top-N descending");
}

fn t17_depth_asks() -> TestResult {
  var b = no_fee_book();
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 103, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 101, 2);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 102, 3);
  let d3 = xchg_depth_asks(&b, 3);
  let p0: Int = d3.prices[0];
  let p1: Int = d3.prices[1];
  let p2: Int = d3.prices[2];
  let q0: Int = d3.qtys[0];
  let q1: Int = d3.qtys[1];
  let q2: Int = d3.qtys[2];
  var ok = d3.prices.len() == 3;
  if p0 != 101 { ok = false; }
  if p1 != 102 { ok = false; }
  if p2 != 103 { ok = false; }
  if q0 != 2 { ok = false; }
  if q1 != 3 { ok = false; }
  if q2 != 1 { ok = false; }
  let d2 = xchg_depth_asks(&b, 2);
  if d2.prices.len() != 2 { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "ask depth is ascending with top-N truncation");
}

fn t18_candles_single_bucket() -> TestResult {
  var b = no_fee_book();
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 250, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 260, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 240, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 255, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 260, 4);
  let c = xchg_candles(&b, 100);
  let bu: Int = c.bucket[0];
  let op: Int = c.open_px[0];
  let hi: Int = c.high_px[0];
  let lo: Int = c.low_px[0];
  let cl: Int = c.close_px[0];
  let vo: Int = c.volume[0];
  let tr: Int = c.trades[0];
  var ok = xchg_trade_count(&b) == 4;
  if c.bucket.len() != 1 { ok = false; }
  if bu != 2 { ok = false; }
  if op != 240 { ok = false; }
  if hi != 260 { ok = false; }
  if lo != 240 { ok = false; }
  if cl != 260 { ok = false; }
  if vo != 4 { ok = false; }
  if tr != 4 { ok = false; }
  return assert(ok, "one tick bucket aggregates four trades into OHLCV 240/260/240/260 volume 4");
}

fn t19_candles_interleaved_buckets() -> TestResult {
  var b = no_fee_book();
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 350, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 150, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 360, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 360, 3);
  let c1 = xchg_candles(&b, 100);
  var ok = c1.bucket.len() == 2;
  let b0: Int = c1.bucket[0];
  let b1: Int = c1.bucket[1];
  let c0: Int = c1.close_px[0];
  let c1c: Int = c1.close_px[1];
  let v1: Int = c1.volume[1];
  if b0 != 1 { ok = false; }
  if b1 != 3 { ok = false; }
  if c0 != 150 { ok = false; }
  if c1c != 360 { ok = false; }
  if v1 != 2 { ok = false; }
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 356, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 356, 1);
  let c2 = xchg_candles(&b, 100);
  let h1: Int = c2.high_px[1];
  let cl1: Int = c2.close_px[1];
  let vv1: Int = c2.volume[1];
  let tt1: Int = c2.trades[1];
  if c2.bucket.len() != 2 { ok = false; }
  if h1 != 360 { ok = false; }
  if cl1 != 356 { ok = false; }
  if vv1 != 3 { ok = false; }
  if tt1 != 3 { ok = false; }
  return assert(ok, "interleaved buckets update in place: bucket 3 keeps high 360 and moves close/volume");
}

fn t20_candle_bucket_boundaries() -> TestResult {
  var b = no_fee_book();
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 99, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 199, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 200, 1);
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 200, 4);
  let c = xchg_candles(&b, 100);
  let b0: Int = c.bucket[0];
  let b1: Int = c.bucket[1];
  let b2: Int = c.bucket[2];
  let o1: Int = c.open_px[1];
  let h1: Int = c.high_px[1];
  let l1: Int = c.low_px[1];
  let c1: Int = c.close_px[1];
  let v1: Int = c.volume[1];
  let t1: Int = c.trades[1];
  var ok = c.bucket.len() == 3;
  if b0 != 0 { ok = false; }
  if b1 != 1 { ok = false; }
  if b2 != 2 { ok = false; }
  if o1 != 100 { ok = false; }
  if h1 != 199 { ok = false; }
  if l1 != 100 { ok = false; }
  if c1 != 199 { ok = false; }
  if v1 != 2 { ok = false; }
  if t1 != 2 { ok = false; }
  let cz = xchg_candles(&b, 0);
  if cz.bucket.len() != 0 { ok = false; }
  return assert(ok, "bucket = price/ticks: 99,100,199,200 map to 0,1,1,2; a zero width yields none");
}

// --- invariants -------------------------------------------------------------

fn t21_invariant_busy_session() -> TestResult {
  var b = xchg_book_new(100, 300);
  var ok = xchg_invariant_ok(&b);
  let id1 = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 99, 5);
  if !xchg_invariant_ok(&b) { ok = false; }
  let id2 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 101, 5);
  if !xchg_invariant_ok(&b) { ok = false; }
  let id3 = xchg_submit_market(&mut b, XCHG_SIDE_BUY, 3);
  if !xchg_invariant_ok(&b) { ok = false; }
  let id4 = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 98, 4);
  if !xchg_invariant_ok(&b) { ok = false; }
  if !xchg_cancel(&mut b, id1) { ok = false; }
  if !xchg_invariant_ok(&b) { ok = false; }
  let id5 = xchg_replace(&mut b, id4, 100, 6);
  if !xchg_invariant_ok(&b) { ok = false; }
  let id6 = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 97, 6);
  if !xchg_invariant_ok(&b) { ok = false; }
  let id7 = xchg_submit_market(&mut b, XCHG_SIDE_BUY, 1);
  if !xchg_invariant_ok(&b) { ok = false; }
  let id8 = xchg_replace(&mut b, id2, 101, 1);
  if !xchg_invariant_ok(&b) { ok = false; }
  if id5 != 5 { ok = false; }
  if id6 != 6 { ok = false; }
  if id7 != 7 { ok = false; }
  if id8 != 8 { ok = false; }
  if xchg_trade_count(&b) != 3 { ok = false; }
  if xchg_order_status(&b, id3) != XCHG_STATUS_FILLED { ok = false; }
  if xchg_order_status(&b, id5) != XCHG_STATUS_FILLED { ok = false; }
  if xchg_order_status(&b, id6) != XCHG_STATUS_FILLED { ok = false; }
  if xchg_order_status(&b, id2) != XCHG_STATUS_CANCELLED { ok = false; }
  if xchg_order_status(&b, id8) != XCHG_STATUS_OPEN { ok = false; }
  if xchg_best_ask(&b) != 101 { ok = false; }
  if xchg_best_bid(&b) != XCHG_NONE { ok = false; }
  if xchg_open_order_count(&b) != 1 { ok = false; }
  if xchg_open_ask_qty(&b) != 1 { ok = false; }
  if xchg_fees_maker_total(&b) <= 0 { ok = false; }
  if xchg_fees_taker_total(&b) <= 0 { ok = false; }
  return assert(ok, "a mixed limit/market/cancel/replace session stays invariant-clean end to end");
}

fn t22_invariant_detects_crossed_book() -> TestResult {
  var b = no_fee_book();
  var ok = xchg_invariant_ok(&b);
  xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 5);
  if !xchg_invariant_ok(&b) { ok = false; }
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 2);
  if !xchg_invariant_ok(&b) { ok = false; }
  b.ask_ids.push(77);
  b.ask_prices.push(99);
  b.ask_qtys.push(1);
  if xchg_invariant_ok(&b) { ok = false; }
  return assert(ok, "an injected unregistered 99 ask both skews the book and crosses it: invariant false");
}

fn t23_invariant_detects_skew_and_status() -> TestResult {
  var b = no_fee_book();
  xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 100, 5);
  var ok = xchg_invariant_ok(&b);
  b.bid_ids.push(999);
  if xchg_invariant_ok(&b) { ok = false; }
  var c = no_fee_book();
  xchg_submit_limit(&mut c, XCHG_SIDE_BUY, 100, 5);
  c.ord_status[0] = XCHG_STATUS_FILLED;
  if xchg_invariant_ok(&c) { ok = false; }
  return assert(ok, "skewed parallel vectors and a FILLED row with a nonzero remainder are both rejected");
}

fn t24_deterministic_session() -> TestResult {
  var b = xchg_book_new(3, 7);
  var seed: Int = 12345;
  var i = 0;
  var max_id = 0;
  while i < 60 {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    let side = (seed / 65536) % 2;
    let price = 95 + (seed / 131072) % 11;
    let qty = 1 + (seed / 17) % 5;
    let id = xchg_submit_limit(&mut b, side, price, qty);
    if id > max_id { max_id = id; }
    i = i + 1;
  }
  var ok = xchg_invariant_ok(&b);
  if max_id != 60 { ok = false; }
  if xchg_trade_count(&b) < 1 { ok = false; }
  if xchg_fees_taker_total(&b) < xchg_fees_maker_total(&b) { ok = false; }
  let bb = xchg_best_bid(&b);
  let ba = xchg_best_ask(&b);
  if bb != XCHG_NONE && ba != XCHG_NONE {
    if bb >= ba { ok = false; }
  }
  return assert(ok, "60 deterministic orders stay invariant-clean with exact fill accounting");
}

fn main() -> Int {
  io.println("=== xiom.exchanger conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_rest_and_best();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_cross_at_maker_price();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_price_priority();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_time_priority();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_partial_fill_rests();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_sweep_multiple_levels();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_market_sell_ioc();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_market_empty_book();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_cancel_live_order();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_cancel_middle_level();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_replace_is_cancel_plus_new();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_replace_rejections();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_maker_taker_fees();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_fee_truncation();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_tape_sequence_and_last();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_depth_bids();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_depth_asks();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_candles_single_bucket();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_candles_interleaved_buckets();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_candle_bucket_boundaries();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_invariant_busy_session();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_invariant_detects_crossed_book();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_invariant_detects_skew_and_status();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_deterministic_session();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.exchanger: all tests passed");
  } else {
    io.println("xiom.exchanger: tests failed");
  }
  return failed;
}
