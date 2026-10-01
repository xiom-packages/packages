// XIOM -- xiom.exchanger: deterministic integer limit order book
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic matching engine: limit and market orders, price-time
// priority, partial fills, maker/taker fees in basis points, cancel and
// cancel/replace, a sequence-numbered trade tape, top-N depth snapshots and
// OHLCV candles over explicit tick buckets. No clock, no threads, no I/O, no
// FFI, no global state: the caller owns the book and every function is a
// total transition over plain values. Integer-only -- prices are ticks, all
// money values are integer notional units (qty * ticks) and all divisions
// truncate toward zero, which the tests pin.
//
// Language notes (XIOM v0.62.2): free functions only; no Vec[StructType], no
// lambdas, no fn tables, no self, no Vec[Str]; Vec[Int] element reads are
// bound with a typed `let` before use; parallel Vec fields are pushed and
// rebuilt together so they can never skew. Every loop advances an index or a
// strictly monotonic level toward a fixed bound, so the suite terminates.
//
// Semantics (see SPEC.md for the exact rules):
//   - price-time priority: best price first, ties broken by arrival order
//     (resting vector index); a replace is cancel + new order and therefore
//     loses time priority.
//   - a limit order first matches the opposite side while it crosses, trades
//     execute at the resting (maker) price, then the remainder rests.
//   - a market order is IOC: it sweeps any liquidity, never rests, and its
//     unfilled remainder is cancelled (status CANCELLED, remaining kept on the
//     registry for accounting).
//   - fees: fee = notional * bps / 10000 truncated toward zero, charged on
//     every trade to both the maker and the taker; totals accumulate.
//   - tape: trade i (0-based) has sequence number i + 1.
//   - candles: bucket = price / bucket_ticks (truncation = floor for positive
//     prices); candles appear in first-touch order and later trades in the
//     same bucket update high/low/close/volume/trades in place.
//   - invalid submissions (bad side, price <= 0 for limits, qty <= 0) return
//     order id 0 and leave the book untouched; the id space starts at 1 and
//     the registry is append-only with ord_ids[i] == i + 1, so registry
//     lookup is O(1).
//   - xchg_invariant_ok re-derives every structural and accounting rule
//     (parallel lengths, sequential ids, resting/registry agreement, an
//     uncrossed book, tape sequence and fee formulas, per-order fill
//     accounting).

module xiom.exchanger

// --- public constants -------------------------------------------------------

/// Buy side (bid).
pub const XCHG_SIDE_BUY: Int = 0;

/// Sell side (ask).
pub const XCHG_SIDE_SELL: Int = 1;

/// Order status: live on the book.
pub const XCHG_STATUS_OPEN: Int = 0;

/// Order status: fully filled.
pub const XCHG_STATUS_FILLED: Int = 1;

/// Order status: cancelled outright, or an IOC market remainder.
pub const XCHG_STATUS_CANCELLED: Int = 2;

/// Sentinel: no price / unknown order / empty result.
pub const XCHG_NONE: Int = -1;

// --- types ------------------------------------------------------------------

/// One book. Every field is an internal implementation detail; callers must
/// go through the xchg_* free functions.
///
/// Resting bids and asks are parallel Vec[Int] fields in arrival order; index
/// order is time priority within a price level. `ord_*` is the append-only
/// registry of every accepted order (id, side, submitted price -- 0 for
/// market orders, original qty, remaining qty, status). `trade_*` is the
/// execution tape. `next_order_id` is the id to assign next; it always equals
/// ord_ids.len() + 1.
pub type XchgOrderBook = {
  bid_ids: Vec[Int];
  bid_prices: Vec[Int];
  bid_qtys: Vec[Int];
  ask_ids: Vec[Int];
  ask_prices: Vec[Int];
  ask_qtys: Vec[Int];
  ord_ids: Vec[Int];
  ord_sides: Vec[Int];
  ord_prices: Vec[Int];
  ord_qtys: Vec[Int];
  ord_remaining: Vec[Int];
  ord_status: Vec[Int];
  trade_seqs: Vec[Int];
  trade_prices: Vec[Int];
  trade_qtys: Vec[Int];
  trade_taker_sides: Vec[Int];
  trade_maker_ids: Vec[Int];
  trade_taker_ids: Vec[Int];
  trade_maker_fees: Vec[Int];
  trade_taker_fees: Vec[Int];
  maker_fee_bps: Int;
  taker_fee_bps: Int;
  fees_maker_total: Int;
  fees_taker_total: Int;
  next_order_id: Int;
}

/// Aggregated price levels: prices[i] has total resting qty qtys[i].
/// Bids are descending, asks ascending, at most `levels` entries.
pub type XchgDepth = {
  prices: Vec[Int];
  qtys: Vec[Int];
}

/// OHLCV candles over explicit tick buckets, in first-touch order.
/// For candle i: bucket index bucket[i] = trade_price / bucket_ticks,
/// open_px/high_px/low_px/close_px are trade prices, volume is the summed qty
/// and trades is the trade count.
pub type XchgCandles = {
  bucket: Vec[Int];
  open_px: Vec[Int];
  high_px: Vec[Int];
  low_px: Vec[Int];
  close_px: Vec[Int];
  volume: Vec[Int];
  trades: Vec[Int];
}

// --- fee helper -------------------------------------------------------------

/// Fee in notional units for `notional` at `bps` basis points.
/// Formula: notional * bps / 10000 (Int `/` truncates toward zero). A
/// non-positive bps is 0. Negative notionals keep the truncation-toward-zero
/// convention; the engine itself only feeds non-negative notionals.
/// Complexity: O(1).
pub fn xchg_fee(notional: Int, bps: Int) -> Int {
  if bps <= 0 { return 0; }
  return notional * bps / 10000;
}

// --- construction -----------------------------------------------------------

/// Empty book with the given fee schedule. Negative bps are clamped to 0;
/// bps above 10000 are accepted unchanged (a fee above 100%).
/// Complexity: O(1).
pub fn xchg_book_new(maker_fee_bps: Int, taker_fee_bps: Int) -> XchgOrderBook {
  var maker_bps = maker_fee_bps;
  if maker_bps < 0 { maker_bps = 0; }
  var taker_bps = taker_fee_bps;
  if taker_bps < 0 { taker_bps = 0; }
  return XchgOrderBook{
    bid_ids: Vec[Int].new();
    bid_prices: Vec[Int].new();
    bid_qtys: Vec[Int].new();
    ask_ids: Vec[Int].new();
    ask_prices: Vec[Int].new();
    ask_qtys: Vec[Int].new();
    ord_ids: Vec[Int].new();
    ord_sides: Vec[Int].new();
    ord_prices: Vec[Int].new();
    ord_qtys: Vec[Int].new();
    ord_remaining: Vec[Int].new();
    ord_status: Vec[Int].new();
    trade_seqs: Vec[Int].new();
    trade_prices: Vec[Int].new();
    trade_qtys: Vec[Int].new();
    trade_taker_sides: Vec[Int].new();
    trade_maker_ids: Vec[Int].new();
    trade_taker_ids: Vec[Int].new();
    trade_maker_fees: Vec[Int].new();
    trade_taker_fees: Vec[Int].new();
    maker_fee_bps: maker_bps;
    taker_fee_bps: taker_bps;
    fees_maker_total: 0;
    fees_taker_total: 0;
    next_order_id: 1;
  };
}

// --- internal helpers -------------------------------------------------------

// true for the two valid side codes.
fn _xchg_valid_side(side: Int) -> Bool {
  if side == XCHG_SIDE_BUY { return true; }
  if side == XCHG_SIDE_SELL { return true; }
  return false;
}

// Registry index of `id`, or -1 when unknown. O(1): ids are dense and
// sequential, so index == id - 1; the identity is also re-checked.
fn _xchg_reg_index(book: &XchgOrderBook, id: Int) -> Int {
  if id < 1 { return -1; }
  let idx = id - 1;
  if idx >= book.ord_ids.len() { return -1; }
  let cur: Int = book.ord_ids[idx];
  if cur != id { return -1; }
  return idx;
}

// Resting slot of `id` among bids, or -1.
fn _xchg_bid_slot(book: &XchgOrderBook, id: Int) -> Int {
  var i = 0;
  while i < book.bid_ids.len() {
    let cur: Int = book.bid_ids[i];
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Resting slot of `id` among asks, or -1.
fn _xchg_ask_slot(book: &XchgOrderBook, id: Int) -> Int {
  var i = 0;
  while i < book.ask_ids.len() {
    let cur: Int = book.ask_ids[i];
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of the best bid (highest price, earliest arrival on ties), or -1.
fn _xchg_best_bid_index(book: &XchgOrderBook) -> Int {
  var best = -1;
  var best_idx = -1;
  var i = 0;
  while i < book.bid_prices.len() {
    let p: Int = book.bid_prices[i];
    if best_idx < 0 { best = p; best_idx = i; }
    else { if p > best { best = p; best_idx = i; } }
    i = i + 1;
  }
  return best_idx;
}

// Index of the best ask (lowest price, earliest arrival on ties), or -1.
fn _xchg_best_ask_index(book: &XchgOrderBook) -> Int {
  var best = -1;
  var best_idx = -1;
  var i = 0;
  while i < book.ask_prices.len() {
    let p: Int = book.ask_prices[i];
    if best_idx < 0 { best = p; best_idx = i; }
    else { if p < best { best = p; best_idx = i; } }
    i = i + 1;
  }
  return best_idx;
}

// Remove resting bid slot `slot` (all three parallel vectors together).
fn _xchg_remove_bid(book: &mut XchgOrderBook, slot: Int) {
  book.bid_ids.remove(slot);
  book.bid_prices.remove(slot);
  book.bid_qtys.remove(slot);
}

// Remove resting ask slot `slot` (all three parallel vectors together).
fn _xchg_remove_ask(book: &mut XchgOrderBook, slot: Int) {
  book.ask_ids.remove(slot);
  book.ask_prices.remove(slot);
  book.ask_qtys.remove(slot);
}

// Append a registry entry for a new accepted order; status OPEN, remaining
// equal to the submitted qty. The caller assigned the id.
fn _xchg_register(book: &mut XchgOrderBook, id: Int, side: Int, price: Int, qty: Int) {
  book.ord_ids.push(id);
  book.ord_sides.push(side);
  book.ord_prices.push(price);
  book.ord_qtys.push(qty);
  book.ord_remaining.push(qty);
  book.ord_status.push(XCHG_STATUS_OPEN);
}

// Rest an already-registered order on its side with `qty` remaining.
fn _xchg_rest(book: &mut XchgOrderBook, id: Int, side: Int, price: Int, qty: Int) {
  if side == XCHG_SIDE_BUY {
    book.bid_ids.push(id);
    book.bid_prices.push(price);
    book.bid_qtys.push(qty);
  } else {
    book.ask_ids.push(id);
    book.ask_prices.push(price);
    book.ask_qtys.push(qty);
  }
}

// Copy a Vec[Int] (typed element reads; no Vec[Str]).
fn _xchg_copy(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

// Execute one maker/taker fill at the maker's resting price: update both
// registry remainders (and the maker's resting qty on a partial fill), append
// one tape row and accumulate both fees. The maker is removed from the book
// and marked FILLED when its remainder hits 0.
// `qty` is positive and at most both remainders (the caller guarantees it).
fn _xchg_execute_trade(book: &mut XchgOrderBook, maker_id: Int, taker_id: Int, taker_side: Int, price: Int, qty: Int) {
  let maker_reg = _xchg_reg_index(book, maker_id);
  let taker_reg = _xchg_reg_index(book, taker_id);
  let maker_side: Int = book.ord_sides[maker_reg];
  let mrem: Int = book.ord_remaining[maker_reg];
  let trem: Int = book.ord_remaining[taker_reg];
  let notional = qty * price;
  let maker_fee = xchg_fee(notional, book.maker_fee_bps);
  let taker_fee = xchg_fee(notional, book.taker_fee_bps);
  let seq = book.trade_seqs.len() + 1;
  book.trade_seqs.push(seq);
  book.trade_prices.push(price);
  book.trade_qtys.push(qty);
  book.trade_taker_sides.push(taker_side);
  book.trade_maker_ids.push(maker_id);
  book.trade_taker_ids.push(taker_id);
  book.trade_maker_fees.push(maker_fee);
  book.trade_taker_fees.push(taker_fee);
  book.fees_maker_total = book.fees_maker_total + maker_fee;
  book.fees_taker_total = book.fees_taker_total + taker_fee;
  book.ord_remaining[maker_reg] = mrem - qty;
  book.ord_remaining[taker_reg] = trem - qty;
  if mrem - qty == 0 {
    book.ord_status[maker_reg] = XCHG_STATUS_FILLED;
    if maker_side == XCHG_SIDE_BUY {
      let slot = _xchg_bid_slot(book, maker_id);
      if slot >= 0 { _xchg_remove_bid(book, slot); }
    } else {
      let slot = _xchg_ask_slot(book, maker_id);
      if slot >= 0 { _xchg_remove_ask(book, slot); }
    }
  } else {
    if maker_side == XCHG_SIDE_BUY {
      let slot = _xchg_bid_slot(book, maker_id);
      if slot >= 0 { book.bid_qtys[slot] = mrem - qty; }
    } else {
      let slot = _xchg_ask_slot(book, maker_id);
      if slot >= 0 { book.ask_qtys[slot] = mrem - qty; }
    }
  }
}

// Sweep resting asks for taker `taker_id` while it crosses. With `has_cap`
// the taker stops at `limit_price`; without a cap (market) any ask price
// qualifies. Progress: every iteration fills at least one unit or empties at
// least one maker level, so the taker remainder strictly decreases toward 0.
// Returns the filled qty.
fn _xchg_match_buy(book: &mut XchgOrderBook, taker_id: Int, limit_price: Int, has_cap: Bool) -> Int {
  var filled = 0;
  let taker_reg = _xchg_reg_index(book, taker_id);
  var rem: Int = book.ord_remaining[taker_reg];
  while rem > 0 {
    let ask_idx = _xchg_best_ask_index(book);
    if ask_idx < 0 { break; }
    let ask_price: Int = book.ask_prices[ask_idx];
    if has_cap {
      if ask_price > limit_price { break; }
    }
    let ask_qty: Int = book.ask_qtys[ask_idx];
    let maker_id: Int = book.ask_ids[ask_idx];
    var fill = rem;
    if ask_qty < fill { fill = ask_qty; }
    if fill <= 0 { break; }
    _xchg_execute_trade(book, maker_id, taker_id, XCHG_SIDE_BUY, ask_price, fill);
    filled = filled + fill;
    rem = book.ord_remaining[taker_reg];
  }
  return filled;
}

// Sweep resting bids for taker `taker_id` while it crosses. Mirror of
// _xchg_match_buy with the same progress guarantee.
fn _xchg_match_sell(book: &mut XchgOrderBook, taker_id: Int, limit_price: Int, has_cap: Bool) -> Int {
  var filled = 0;
  let taker_reg = _xchg_reg_index(book, taker_id);
  var rem: Int = book.ord_remaining[taker_reg];
  while rem > 0 {
    let bid_idx = _xchg_best_bid_index(book);
    if bid_idx < 0 { break; }
    let bid_price: Int = book.bid_prices[bid_idx];
    if has_cap {
      if bid_price < limit_price { break; }
    }
    let bid_qty: Int = book.bid_qtys[bid_idx];
    let maker_id: Int = book.bid_ids[bid_idx];
    var fill = rem;
    if bid_qty < fill { fill = bid_qty; }
    if fill <= 0 { break; }
    _xchg_execute_trade(book, maker_id, taker_id, XCHG_SIDE_SELL, bid_price, fill);
    filled = filled + fill;
    rem = book.ord_remaining[taker_reg];
  }
  return filled;
}

// Shared submit path for limit and market orders. Validates, allocates the
// id, registers, matches, then rests (limit) or cancels (IOC market) the
// remainder. Returns the new id, or 0 on rejection.
fn _xchg_submit(book: &mut XchgOrderBook, side: Int, price: Int, qty: Int, is_market: Bool) -> Int {
  if !_xchg_valid_side(side) { return 0; }
  if qty <= 0 { return 0; }
  if !is_market {
    if price <= 0 { return 0; }
  }
  let id = book.next_order_id;
  book.next_order_id = id + 1;
  _xchg_register(book, id, side, price, qty);
  if side == XCHG_SIDE_BUY {
    if is_market { _xchg_match_buy(book, id, 0, false); }
    else { _xchg_match_buy(book, id, price, true); }
  } else {
    if is_market { _xchg_match_sell(book, id, 0, false); }
    else { _xchg_match_sell(book, id, price, true); }
  }
  let reg = _xchg_reg_index(book, id);
  let rem: Int = book.ord_remaining[reg];
  if rem == 0 {
    book.ord_status[reg] = XCHG_STATUS_FILLED;
  } else {
    if is_market {
      book.ord_status[reg] = XCHG_STATUS_CANCELLED;
    } else {
      _xchg_rest(book, id, side, price, rem);
    }
  }
  return id;
}

// Shared depth aggregation: scan the given price/qty vectors `want` times,
// each pass taking the next distinct price on the far side of the previous
// one (descending for bids, ascending for asks) and summing its qty. Progress:
// each emitted level sets `prev` strictly beyond the last, so at most the
// number of distinct levels iterations run; inner scans are index-bounded.
fn _xchg_depth_side(prices: &Vec[Int], qtys: &Vec[Int], want: Int, descending: Bool, out_px: &mut Vec[Int], out_qt: &mut Vec[Int]) {
  out_px.clear();
  out_qt.clear();
  if want <= 0 { return; }
  let n = prices.len();
  var prev = -1;
  var emitted = 0;
  while emitted < want {
    var best = -1;
    var best_idx = -1;
    var i = 0;
    while i < n {
      let p: Int = prices[i];
      var cand = false;
      if emitted == 0 { cand = true; }
      else {
        if descending { if p < prev { cand = true; } }
        else { if p > prev { cand = true; } }
      }
      if cand {
        if best_idx < 0 { best = p; best_idx = i; }
        else {
          if descending { if p > best { best = p; best_idx = i; } }
          else { if p < best { best = p; best_idx = i; } }
        }
      }
      i = i + 1;
    }
    if best_idx < 0 { break; }
    var total = 0;
    var j = 0;
    while j < n {
      let p2: Int = prices[j];
      if p2 == best {
        let q: Int = qtys[j];
        total = total + q;
      }
      j = j + 1;
    }
    out_px.push(best);
    out_qt.push(total);
    prev = best;
    emitted = emitted + 1;
  }
}

// --- public API: orders -----------------------------------------------------

/// Submit a limit order and match it against the opposite side.
/// A crossing remainder executes at each resting (maker) price in price-time
/// priority; a non-crossing remainder rests. Rejected (return 0, book
/// untouched) when the side is not XCHG_SIDE_BUY/XCHG_SIDE_SELL, price <= 0
/// or qty <= 0.
/// Params: book - the mutable book; side - XCHG_SIDE_*; price - limit price in
///         ticks (> 0); qty - size (> 0).
/// Returns: the new order id (>= 1), or 0 on rejection. Complexity: O(matches
/// plus resting orders scanned per match).
pub fn xchg_submit_limit(book: &mut XchgOrderBook, side: Int, price: Int, qty: Int) -> Int {
  return _xchg_submit(book, side, price, qty, false);
}

/// Submit an IOC market order and sweep the opposite side.
/// The order never rests: the filled part is FILLED, any remainder is
/// CANCELLED (its remaining qty stays on the registry for accounting).
/// Rejected (return 0, book untouched) when the side is invalid or qty <= 0.
/// Params: book - the mutable book; side - XCHG_SIDE_*; qty - size (> 0).
/// Returns: the new order id (>= 1), or 0 on rejection. Complexity: O(matches
/// plus resting orders scanned per match).
pub fn xchg_submit_market(book: &mut XchgOrderBook, side: Int, qty: Int) -> Int {
  return _xchg_submit(book, side, 0, qty, true);
}

/// Cancel a live order: remove it from the book and mark it CANCELLED.
/// The unfilled remainder stays on the registry; the filled qty is unchanged.
/// Params: book - the mutable book; order_id - the id to cancel.
/// Returns: true when an OPEN order was cancelled; false for an unknown or
/// already terminal id. Complexity: O(resting orders on that side).
pub fn xchg_cancel(book: &mut XchgOrderBook, order_id: Int) -> Bool {
  let reg = _xchg_reg_index(book, order_id);
  if reg < 0 { return false; }
  let st: Int = book.ord_status[reg];
  if st != XCHG_STATUS_OPEN { return false; }
  let side: Int = book.ord_sides[reg];
  if side == XCHG_SIDE_BUY {
    let slot = _xchg_bid_slot(book, order_id);
    if slot < 0 { return false; }
    _xchg_remove_bid(book, slot);
  } else {
    let slot = _xchg_ask_slot(book, order_id);
    if slot < 0 { return false; }
    _xchg_remove_ask(book, slot);
  }
  book.ord_status[reg] = XCHG_STATUS_CANCELLED;
  return true;
}

/// Cancel/replace a live order: cancel the old id and submit a new limit
/// order on the same side. The replacement is a new order and therefore
/// loses time priority (and may match immediately).
/// Rejected (return 0, the old order left untouched) when the old id is
/// unknown/terminal or the new price <= 0 / qty <= 0.
/// Params: book - the mutable book; order_id - the live order to replace;
///         price - new limit price in ticks (> 0); qty - new size (> 0).
/// Returns: the new order id (>= 1), or 0 on rejection. Complexity: O(cancel
/// plus submit).
pub fn xchg_replace(book: &mut XchgOrderBook, order_id: Int, price: Int, qty: Int) -> Int {
  if price <= 0 { return 0; }
  if qty <= 0 { return 0; }
  let reg = _xchg_reg_index(book, order_id);
  if reg < 0 { return 0; }
  let st: Int = book.ord_status[reg];
  if st != XCHG_STATUS_OPEN { return 0; }
  let side: Int = book.ord_sides[reg];
  let cancelled = xchg_cancel(book, order_id);
  if !cancelled { return 0; }
  return xchg_submit_limit(book, side, price, qty);
}

// --- public API: views ------------------------------------------------------

/// Best bid price in ticks, or XCHG_NONE when there is no bid.
/// Complexity: O(bids).
pub fn xchg_best_bid(book: &XchgOrderBook) -> Int {
  let idx = _xchg_best_bid_index(book);
  if idx < 0 { return XCHG_NONE; }
  let p: Int = book.bid_prices[idx];
  return p;
}

/// Best ask price in ticks, or XCHG_NONE when there is no ask.
/// Complexity: O(asks).
pub fn xchg_best_ask(book: &XchgOrderBook) -> Int {
  let idx = _xchg_best_ask_index(book);
  if idx < 0 { return XCHG_NONE; }
  let p: Int = book.ask_prices[idx];
  return p;
}

/// Registry status of `order_id` (XCHG_STATUS_*), or XCHG_NONE when unknown.
/// Complexity: O(1).
pub fn xchg_order_status(book: &XchgOrderBook, order_id: Int) -> Int {
  let reg = _xchg_reg_index(book, order_id);
  if reg < 0 { return XCHG_NONE; }
  let st: Int = book.ord_status[reg];
  return st;
}

/// Remaining (unfilled) qty of `order_id`, or XCHG_NONE when unknown.
/// Complexity: O(1).
pub fn xchg_order_remaining(book: &XchgOrderBook, order_id: Int) -> Int {
  let reg = _xchg_reg_index(book, order_id);
  if reg < 0 { return XCHG_NONE; }
  let rem: Int = book.ord_remaining[reg];
  return rem;
}

/// Number of live orders (resting bids + resting asks). Complexity: O(1).
pub fn xchg_open_order_count(book: &XchgOrderBook) -> Int {
  return book.bid_ids.len() + book.ask_ids.len();
}

/// Total resting bid qty. Complexity: O(bids).
pub fn xchg_open_bid_qty(book: &XchgOrderBook) -> Int {
  var total = 0;
  var i = 0;
  while i < book.bid_qtys.len() {
    let q: Int = book.bid_qtys[i];
    total = total + q;
    i = i + 1;
  }
  return total;
}

/// Total resting ask qty. Complexity: O(asks).
pub fn xchg_open_ask_qty(book: &XchgOrderBook) -> Int {
  var total = 0;
  var i = 0;
  while i < book.ask_qtys.len() {
    let q: Int = book.ask_qtys[i];
    total = total + q;
    i = i + 1;
  }
  return total;
}

/// Number of trades on the tape. Complexity: O(1).
pub fn xchg_trade_count(book: &XchgOrderBook) -> Int {
  return book.trade_seqs.len();
}

/// Price of the most recent trade, or XCHG_NONE when the tape is empty.
/// Complexity: O(1).
pub fn xchg_last_trade_price(book: &XchgOrderBook) -> Int {
  let n = book.trade_prices.len();
  if n == 0 { return XCHG_NONE; }
  let p: Int = book.trade_prices[n - 1];
  return p;
}

/// Accumulated maker fees over the tape. Complexity: O(1).
pub fn xchg_fees_maker_total(book: &XchgOrderBook) -> Int {
  return book.fees_maker_total;
}

/// Accumulated taker fees over the tape. Complexity: O(1).
pub fn xchg_fees_taker_total(book: &XchgOrderBook) -> Int {
  return book.fees_taker_total;
}

/// Copy of the tape sequence numbers (1..n in trade order). Complexity: O(n).
pub fn xchg_tape_seqs(book: &XchgOrderBook) -> Vec[Int] {
  return _xchg_copy(&book.trade_seqs);
}

/// Copy of the tape trade prices. Complexity: O(n).
pub fn xchg_tape_prices(book: &XchgOrderBook) -> Vec[Int] {
  return _xchg_copy(&book.trade_prices);
}

/// Copy of the tape trade quantities. Complexity: O(n).
pub fn xchg_tape_qtys(book: &XchgOrderBook) -> Vec[Int] {
  return _xchg_copy(&book.trade_qtys);
}

/// Copy of the tape taker sides (XCHG_SIDE_*). Complexity: O(n).
pub fn xchg_tape_taker_sides(book: &XchgOrderBook) -> Vec[Int] {
  return _xchg_copy(&book.trade_taker_sides);
}

/// Copy of the tape maker order ids. Complexity: O(n).
pub fn xchg_tape_maker_ids(book: &XchgOrderBook) -> Vec[Int] {
  return _xchg_copy(&book.trade_maker_ids);
}

/// Copy of the tape taker order ids. Complexity: O(n).
pub fn xchg_tape_taker_ids(book: &XchgOrderBook) -> Vec[Int] {
  return _xchg_copy(&book.trade_taker_ids);
}

/// Copy of the tape maker fees. Complexity: O(n).
pub fn xchg_tape_maker_fees(book: &XchgOrderBook) -> Vec[Int] {
  return _xchg_copy(&book.trade_maker_fees);
}

/// Copy of the tape taker fees. Complexity: O(n).
pub fn xchg_tape_taker_fees(book: &XchgOrderBook) -> Vec[Int] {
  return _xchg_copy(&book.trade_taker_fees);
}

/// Top-`levels` aggregated bid depth, highest price first, ties aggregated.
/// A non-positive `levels` yields empty vectors.
/// Params: book - the book; levels - maximum number of price levels.
/// Returns: XchgDepth with parallel prices/qtys. Complexity: O(levels * bids).
pub fn xchg_depth_bids(book: &XchgOrderBook, levels: Int) -> XchgDepth {
  var px = Vec[Int].new();
  var qt = Vec[Int].new();
  _xchg_depth_side(&book.bid_prices, &book.bid_qtys, levels, true, &mut px, &mut qt);
  return XchgDepth{ prices: px; qtys: qt };
}

/// Top-`levels` aggregated ask depth, lowest price first, ties aggregated.
/// A non-positive `levels` yields empty vectors.
/// Params: book - the book; levels - maximum number of price levels.
/// Returns: XchgDepth with parallel prices/qtys. Complexity: O(levels * asks).
pub fn xchg_depth_asks(book: &XchgOrderBook, levels: Int) -> XchgDepth {
  var px = Vec[Int].new();
  var qt = Vec[Int].new();
  _xchg_depth_side(&book.ask_prices, &book.ask_qtys, levels, false, &mut px, &mut qt);
  return XchgDepth{ prices: px; qtys: qt };
}

/// OHLCV candles over the trade tape with explicit tick buckets.
/// bucket = trade_price / bucket_ticks (truncation; positive prices and
/// bucket_ticks make this the floor). Candles appear in first-touch order;
/// a later trade in an existing bucket updates high/low/close/volume/trades.
/// A non-positive `bucket_ticks` yields empty candles.
/// Params: book - the book whose tape is aggregated; bucket_ticks - bucket
///         width in ticks (> 0 for a non-empty result).
/// Returns: XchgCandles. Complexity: O(trades * candles).
pub fn xchg_candles(book: &XchgOrderBook, bucket_ticks: Int) -> XchgCandles {
  var bucket = Vec[Int].new();
  var op = Vec[Int].new();
  var hi = Vec[Int].new();
  var lo = Vec[Int].new();
  var cl = Vec[Int].new();
  var vol = Vec[Int].new();
  var cnt = Vec[Int].new();
  if bucket_ticks > 0 {
    var i = 0;
    while i < book.trade_seqs.len() {
      let price: Int = book.trade_prices[i];
      let qty: Int = book.trade_qtys[i];
      let b = price / bucket_ticks;
      var idx = -1;
      var k = 0;
      while k < bucket.len() {
        let curb: Int = bucket[k];
        if curb == b { idx = k; }
        k = k + 1;
      }
      if idx < 0 {
        bucket.push(b);
        op.push(price);
        hi.push(price);
        lo.push(price);
        cl.push(price);
        vol.push(qty);
        cnt.push(1);
      } else {
        let h: Int = hi[idx];
        if price > h { hi[idx] = price; }
        let l: Int = lo[idx];
        if price < l { lo[idx] = price; }
        cl[idx] = price;
        let v: Int = vol[idx];
        vol[idx] = v + qty;
        let c: Int = cnt[idx];
        cnt[idx] = c + 1;
      }
      i = i + 1;
    }
  }
  return XchgCandles{
    bucket: bucket;
    open_px: op;
    high_px: hi;
    low_px: lo;
    close_px: cl;
    volume: vol;
    trades: cnt;
  };
}

// --- invariant checker ------------------------------------------------------

// Parallel vector lengths, id space and fee-schedule sanity.
fn _xchg_inv_shape_ok(b: &XchgOrderBook) -> Bool {
  let nb = b.bid_ids.len();
  if b.bid_prices.len() != nb { return false; }
  if b.bid_qtys.len() != nb { return false; }
  let na = b.ask_ids.len();
  if b.ask_prices.len() != na { return false; }
  if b.ask_qtys.len() != na { return false; }
  let nr = b.ord_ids.len();
  if b.ord_sides.len() != nr { return false; }
  if b.ord_prices.len() != nr { return false; }
  if b.ord_qtys.len() != nr { return false; }
  if b.ord_remaining.len() != nr { return false; }
  if b.ord_status.len() != nr { return false; }
  let nt = b.trade_seqs.len();
  if b.trade_prices.len() != nt { return false; }
  if b.trade_qtys.len() != nt { return false; }
  if b.trade_taker_sides.len() != nt { return false; }
  if b.trade_maker_ids.len() != nt { return false; }
  if b.trade_taker_ids.len() != nt { return false; }
  if b.trade_maker_fees.len() != nt { return false; }
  if b.trade_taker_fees.len() != nt { return false; }
  if b.next_order_id != nr + 1 { return false; }
  if b.maker_fee_bps < 0 { return false; }
  if b.taker_fee_bps < 0 { return false; }
  if b.fees_maker_total < 0 { return false; }
  if b.fees_taker_total < 0 { return false; }
  return true;
}

// Registry rows are sequential, bounded and consistent with the resting
// vectors: every OPEN order appears exactly once on its side with the same
// qty; FILLED implies zero remainder; CANCELLED is terminal.
fn _xchg_inv_registry_ok(b: &XchgOrderBook) -> Bool {
  var i = 0;
  while i < b.ord_ids.len() {
    let id: Int = b.ord_ids[i];
    if id != i + 1 { return false; }
    let side: Int = b.ord_sides[i];
    if side != XCHG_SIDE_BUY && side != XCHG_SIDE_SELL { return false; }
    let price: Int = b.ord_prices[i];
    if price < 0 { return false; }
    let qty: Int = b.ord_qtys[i];
    if qty <= 0 { return false; }
    let rem: Int = b.ord_remaining[i];
    if rem < 0 { return false; }
    if rem > qty { return false; }
    let st: Int = b.ord_status[i];
    if st != XCHG_STATUS_OPEN && st != XCHG_STATUS_FILLED && st != XCHG_STATUS_CANCELLED { return false; }
    if st == XCHG_STATUS_FILLED {
      if rem != 0 { return false; }
    }
    if st == XCHG_STATUS_OPEN {
      if rem <= 0 { return false; }
      var found = 0;
      var j = 0;
      if side == XCHG_SIDE_BUY {
        while j < b.bid_ids.len() {
          let bid: Int = b.bid_ids[j];
          if bid == id { found = found + 1; }
          j = j + 1;
        }
      } else {
        while j < b.ask_ids.len() {
          let aid: Int = b.ask_ids[j];
          if aid == id { found = found + 1; }
          j = j + 1;
        }
      }
      if found != 1 { return false; }
      if side == XCHG_SIDE_BUY {
        let slot = _xchg_bid_slot(b, id);
        if slot < 0 { return false; }
        let rq: Int = b.bid_qtys[slot];
        if rq != rem { return false; }
      } else {
        let slot = _xchg_ask_slot(b, id);
        if slot < 0 { return false; }
        let rq: Int = b.ask_qtys[slot];
        if rq != rem { return false; }
      }
    }
    i = i + 1;
  }
  return true;
}

// Resting rows are positive and point at an OPEN registry order with the
// matching side; the book is uncrossed (best bid < best ask).
fn _xchg_inv_resting_ok(b: &XchgOrderBook) -> Bool {
  var i = 0;
  while i < b.bid_ids.len() {
    let id: Int = b.bid_ids[i];
    let px: Int = b.bid_prices[i];
    let q: Int = b.bid_qtys[i];
    if id < 1 { return false; }
    if px <= 0 { return false; }
    if q <= 0 { return false; }
    let reg = _xchg_reg_index(b, id);
    if reg < 0 { return false; }
    let side: Int = b.ord_sides[reg];
    if side != XCHG_SIDE_BUY { return false; }
    let st: Int = b.ord_status[reg];
    if st != XCHG_STATUS_OPEN { return false; }
    i = i + 1;
  }
  var j = 0;
  while j < b.ask_ids.len() {
    let id: Int = b.ask_ids[j];
    let px: Int = b.ask_prices[j];
    let q: Int = b.ask_qtys[j];
    if id < 1 { return false; }
    if px <= 0 { return false; }
    if q <= 0 { return false; }
    let reg = _xchg_reg_index(b, id);
    if reg < 0 { return false; }
    let side: Int = b.ord_sides[reg];
    if side != XCHG_SIDE_SELL { return false; }
    let st: Int = b.ord_status[reg];
    if st != XCHG_STATUS_OPEN { return false; }
    j = j + 1;
  }
  let bi = _xchg_best_bid_index(b);
  let ai = _xchg_best_ask_index(b);
  if bi >= 0 && ai >= 0 {
    let bp: Int = b.bid_prices[bi];
    let ap: Int = b.ask_prices[ai];
    if bp >= ap { return false; }
  }
  return true;
}

// Tape rows: sequential sequence numbers, positive price/qty, valid taker
// side, registered maker/taker on opposite sides, exact fee formulas and
// fee totals equal to the summed tape fees.
fn _xchg_inv_tape_ok(b: &XchgOrderBook) -> Bool {
  var maker_sum = 0;
  var taker_sum = 0;
  var i = 0;
  while i < b.trade_seqs.len() {
    let seq: Int = b.trade_seqs[i];
    if seq != i + 1 { return false; }
    let price: Int = b.trade_prices[i];
    if price <= 0 { return false; }
    let qty: Int = b.trade_qtys[i];
    if qty <= 0 { return false; }
    let ts: Int = b.trade_taker_sides[i];
    if ts != XCHG_SIDE_BUY && ts != XCHG_SIDE_SELL { return false; }
    let mid: Int = b.trade_maker_ids[i];
    let tid: Int = b.trade_taker_ids[i];
    if mid == tid { return false; }
    let mreg = _xchg_reg_index(b, mid);
    if mreg < 0 { return false; }
    let treg = _xchg_reg_index(b, tid);
    if treg < 0 { return false; }
    let mside: Int = b.ord_sides[mreg];
    if mside == ts { return false; }
    let mfee: Int = b.trade_maker_fees[i];
    if mfee != xchg_fee(qty * price, b.maker_fee_bps) { return false; }
    let tfee: Int = b.trade_taker_fees[i];
    if tfee != xchg_fee(qty * price, b.taker_fee_bps) { return false; }
    maker_sum = maker_sum + mfee;
    taker_sum = taker_sum + tfee;
    i = i + 1;
  }
  if maker_sum != b.fees_maker_total { return false; }
  if taker_sum != b.fees_taker_total { return false; }
  return true;
}

// Fill accounting: for every order, original qty minus remaining equals the
// summed tape qty of every trade it participated in; summed across orders
// that is exactly twice the tape volume (each trade has one maker and one
// taker row).
fn _xchg_inv_accounting_ok(b: &XchgOrderBook) -> Bool {
  var sum_filled = 0;
  var i = 0;
  while i < b.ord_ids.len() {
    let id: Int = b.ord_ids[i];
    let qty: Int = b.ord_qtys[i];
    let rem: Int = b.ord_remaining[i];
    let filled = qty - rem;
    var part = 0;
    var j = 0;
    while j < b.trade_qtys.len() {
      let mid: Int = b.trade_maker_ids[j];
      let tid: Int = b.trade_taker_ids[j];
      let tq: Int = b.trade_qtys[j];
      if mid == id { part = part + tq; }
      if tid == id { part = part + tq; }
      j = j + 1;
    }
    if part != filled { return false; }
    sum_filled = sum_filled + filled;
    i = i + 1;
  }
  var volume = 0;
  var k = 0;
  while k < b.trade_qtys.len() {
    let tq2: Int = b.trade_qtys[k];
    volume = volume + tq2;
    k = k + 1;
  }
  if sum_filled != 2 * volume { return false; }
  return true;
}

/// Full structural and accounting invariant check.
/// True when: all parallel vectors match in length; ids are sequential
/// (ord_ids[i] == i + 1, next_order_id == count + 1); every registry row is
/// bounded (0 <= remaining <= qty) with a valid status; every OPEN order
/// rests exactly once with its remaining qty and every resting row points at
/// an OPEN order of the matching side; the book is uncrossed; tape sequence
/// numbers are 1..n, prices/qties positive, maker and taker differ, are
/// registered and on opposite sides, and every trade fee matches the fee
/// schedule with totals equal to the tape sums; and each order's filled qty
/// equals its summed tape participation (so summed fills == 2 * volume).
/// Complexity: O(orders * trades + resting).
pub fn xchg_invariant_ok(book: &XchgOrderBook) -> Bool {
  if !_xchg_inv_shape_ok(book) { return false; }
  if !_xchg_inv_registry_ok(book) { return false; }
  if !_xchg_inv_resting_ok(book) { return false; }
  if !_xchg_inv_tape_ok(book) { return false; }
  if !_xchg_inv_accounting_ok(book) { return false; }
  return true;
}
