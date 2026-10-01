# xiom.exchanger -- specification

Module `xiom.exchanger`. Pure XIOM (stdlib `xiom.std` only in tests), no FFI.
Every quantity is `Int`; every division truncates toward zero (native `/`).
The engine is deterministic: the same call sequence on the same state always
produces the same state, trades and fees.

## 1. Constants and types

| Constant | Value | Meaning |
|---|---|---|
| `XCHG_SIDE_BUY` | 0 | Bid side. |
| `XCHG_SIDE_SELL` | 1 | Ask side. |
| `XCHG_STATUS_OPEN` | 0 | Live on the book. |
| `XCHG_STATUS_FILLED` | 1 | Fully filled (remaining == 0). |
| `XCHG_STATUS_CANCELLED` | 2 | Cancelled outright or IOC market remainder. |
| `XCHG_NONE` | -1 | No price / unknown order / empty result. |

`XchgOrderBook` (all fields implementation details; use the functions):

- `bid_ids`, `bid_prices`, `bid_qtys` -- parallel resting bid vectors, arrival
  order; index order is time priority within a price level.
- `ask_ids`, `ask_prices`, `ask_qtys` -- parallel resting ask vectors.
- `ord_ids`, `ord_sides`, `ord_prices`, `ord_qtys`, `ord_remaining`,
  `ord_status` -- append-only registry of every accepted order. `ord_ids[i]`
  is always `i + 1` (ids are dense from 1); `ord_prices` stores the submitted
  price (0 for market orders).
- `trade_seqs`, `trade_prices`, `trade_qtys`, `trade_taker_sides`,
  `trade_maker_ids`, `trade_taker_ids`, `trade_maker_fees`,
  `trade_taker_fees` -- the tape, one row per fill.
- `maker_fee_bps`, `taker_fee_bps` -- fee schedule.
- `fees_maker_total`, `fees_taker_total` -- accumulated fees.
- `next_order_id` -- always `ord_ids.len() + 1`.

`XchgDepth = { prices: Vec[Int]; qtys: Vec[Int]; }` -- aggregated levels.

`XchgCandles = { bucket; open_px; high_px; low_px; close_px; volume; trades }`
-- parallel candle columns.

## 2. Order entry and matching

### 2.1 Limit orders -- `xchg_submit_limit(book, side, price, qty) -> Int`

Validation (any failure returns 0 and leaves the book untouched): `side` must
be 0 or 1; `price > 0`; `qty > 0`. On success an id is allocated (>= 1), a
registry row is appended with `remaining = qty` and status OPEN, then:

1. While the order crosses the opposite side's best price, it trades against
   the best maker in **price-time priority**: best price first, earliest
   arrival among equal prices.
2. Each fill executes at the **maker's resting price** (price improvement is
   kept by the taker), for `min(taker remaining, maker remaining)`.
3. A fully filled maker is removed from the book and marked FILLED; a
   partially filled maker stays with its resting qty reduced.
4. The taker's registry remaining decreases per fill. If it reaches 0 the
   order is FILLED; otherwise it rests at its limit price with the remainder
   (status OPEN).

A buy with `price >= best ask` crosses; a sell with `price <= best bid`
crosses. Non-crossing orders rest immediately.

### 2.2 Market orders -- `xchg_submit_market(book, side, qty) -> Int`

Validation: valid side and `qty > 0`, else 0. The order is immediate-or-cancel:
it sweeps the opposite side at each maker price (no price cap), then any
unfilled remainder is marked CANCELLED and never rests. Its registry row keeps
the remaining qty for accounting. Filled fully -> FILLED.

### 2.3 Cancel -- `xchg_cancel(book, order_id) -> Bool`

Removes an OPEN order from its resting side and marks it CANCELLED, keeping
its remaining qty on the registry. Returns false (no change) for an unknown id
or any non-OPEN (FILLED/CANCELLED) order.

### 2.4 Cancel/replace -- `xchg_replace(book, order_id, price, qty) -> Int`

Equivalent to cancel + submit on the same side: the replacement gets a **new
id and loses time priority**, and may match immediately. Returns 0 and leaves
the old order untouched when the old id is unknown/terminal or `price <= 0` /
`qty <= 0`. On success the old order is CANCELLED and the new limit order id is
returned.

### 2.5 Rejections

Invalid submissions allocate no id and mutate nothing:

| Function | Rejected when |
|---|---|
| `xchg_submit_limit` | side not 0/1, price <= 0, qty <= 0 |
| `xchg_submit_market` | side not 0/1, qty <= 0 |
| `xchg_replace` | old id unknown/terminal, new price <= 0 or qty <= 0 |
| `xchg_cancel` | id unknown or not OPEN |

## 3. Fees

Schedule set by `xchg_book_new(maker_fee_bps, taker_fee_bps)`; negative bps
clamp to 0, values above 10000 are accepted unchanged.

For a fill of `qty` at price `price`, with `notional = qty * price`:

```
fee(notional, bps) = notional * bps / 10000        // truncates toward zero
```

Both sides are charged on every trade: the resting order pays
`maker_fee_bps`, the incoming order pays `taker_fee_bps`. Per-trade fees are on
the tape; `fees_maker_total` / `fees_taker_total` are the running sums.
Examples (pinned by tests): `xchg_fee(3000, 2) = 0`, `xchg_fee(3000, 5) = 1`,
`xchg_fee(7000, 2) = 1`, `xchg_fee(7000, 5) = 3`, `xchg_fee(9999, 5) = 4`.

## 4. Trade tape

Trade `i` (0-based) has sequence number `i + 1`; `xchg_trade_count` is the
number of trades and `xchg_last_trade_price` is the price of the last row
(`XCHG_NONE` when empty). Each row records maker id, taker id, taker side,
price, qty and both fees. `xchg_tape_*` return copies of the columns.

## 5. Depth snapshots

`xchg_depth_bids(book, levels)` aggregates resting bid qty per distinct price
and returns the `levels` highest prices, descending. `xchg_depth_asks` returns
the `levels` lowest prices, ascending. Ties are aggregated; `levels <= 0`
yields empty vectors. A level appears only if the book has orders at it.

## 6. Candles

`xchg_candles(book, bucket_ticks)` folds the tape (in execution order) into
OHLCV candles:

- `bucket = price / bucket_ticks` (truncation; for positive prices and
  `bucket_ticks >= 1` this is the floor). `bucket_ticks <= 0` yields empty
  candles.
- Candles are emitted in **first-touch order** (the order buckets first
  appear on the tape), not sorted by bucket index.
- The first trade in a bucket sets open/high/low/close; a later trade in the
  same bucket updates `high = max(high, price)`, `low = min(low, price)`,
  `close = price`, `volume += qty`, `trades += 1` in place.
- Example (pinned): prices 150, 350, 360 with `bucket_ticks = 100` produce
  bucket 1 (open 150, close 150) then bucket 3 (open 350, high 360, close
  360); a later 356 trade updates bucket 3 to high 360, close 356.

## 7. Invariant checker

`xchg_invariant_ok(book)` returns true iff all of the following hold:

1. Every set of parallel vectors has equal lengths (3 resting per side, 6
   registry, 8 tape); `next_order_id == registry count + 1`; both fee
   schedules and both fee totals are >= 0.
2. Registry rows: `ord_ids[i] == i + 1`; sides are 0/1; prices >= 0; qty > 0;
   `0 <= remaining <= qty`; status in {OPEN, FILLED, CANCELLED}; FILLED
   implies `remaining == 0`; OPEN implies `remaining > 0`; each OPEN order
   appears exactly once on its side with resting qty equal to `remaining`.
3. Resting rows: id >= 1, price > 0, qty > 0, and each points at an OPEN
   registry order of the matching side; the book is uncrossed
   (`best bid < best ask` when both exist).
4. Tape: `trade_seqs[i] == i + 1`; price > 0; qty > 0; taker side 0/1; maker
   and taker ids differ, are registered and on opposite sides; each row's
   maker/taker fee equals `fee(qty * price, maker/taker_bps)`; the fee totals
   equal the summed tape fees.
5. Accounting: for every order, `qty - remaining` equals the summed tape qty
   of all trades it participated in; summed over all orders this equals
   `2 * tape volume` (each trade has exactly one maker and one taker row).

## 8. Complexity and termination

| Function | Complexity |
|---|---|
| `xchg_book_new`, `xchg_fee`, accessors | O(1) |
| `xchg_submit_limit` / `xchg_submit_market` | O(fills * resting scan) |
| `xchg_cancel`, `xchg_replace` | O(resting on that side) / O(cancel + submit) |
| `xchg_best_bid`, `xchg_best_ask` | O(bids) / O(asks) |
| `xchg_depth_bids`, `xchg_depth_asks` | O(levels * resting) |
| `xchg_candles` | O(trades * candles) |
| `xchg_invariant_ok` | O(orders * trades + resting) |

Every loop advances an index or a strictly monotonic price level toward a
fixed bound, and every match fills at least one unit or empties one maker
level, so every call terminates; the 24-check suite runs in seconds.

## 9. Not modelled

No order types beyond limit/market (no stop, iceberg, pegged), no self-trade
prevention, no auction/opening crosses, no margin or position tracking, no
persistence, no time-in-force other than IOC markets. Fees are flat bps of
notional with truncation; no fee tiers or rebates.
