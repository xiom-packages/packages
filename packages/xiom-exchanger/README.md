# xiom.exchanger

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** one pure-XIOM module implementing a deterministic integer limit
> order book: price-time matching, partial fills, maker/taker fees in basis
> points, cancel/replace, a sequence-numbered trade tape, top-N depth
> snapshots, OHLCV candles over explicit tick buckets and an invariant checker.
> **Deps:** none (the library imports nothing; tests use `xiom.std` modules).

## What it is

`xiom.exchanger` is a synchronous matching core, not a full exchange: there is
no clock, no threading, no I/O, no FFI and no global state. The caller owns an
`XchgOrderBook` value and drives it with total, deterministic functions.
Everything is `Int`:

- prices are integer ticks,
- all money values (fees, notionals) are integer notional units,
- every division truncates toward zero, and each rounding point is pinned by a
  conformance test.

The engine keeps:

- resting bids and asks as parallel `Vec[Int]` fields in arrival order (index
  order is time priority within a price level),
- an append-only order registry with status and remaining qty for every
  accepted order,
- a trade tape where trade `i` has sequence number `i + 1`,
- aggregate fee counters for maker and taker.

## API

| Function | Returns | Description |
|---|---|---|
| `xchg_book_new(maker_bps, taker_bps)` | `XchgOrderBook` | Empty book; negative bps clamp to 0. |
| `xchg_submit_limit(book, side, price, qty)` | `Int` | Submit a limit order; returns id (>= 1) or 0 on rejection. |
| `xchg_submit_market(book, side, qty)` | `Int` | Submit an IOC market order; returns id (>= 1) or 0. |
| `xchg_cancel(book, id)` | `Bool` | Cancel a live order once. |
| `xchg_replace(book, id, price, qty)` | `Int` | Cancel/replace; returns the new id or 0. |
| `xchg_best_bid(book)` / `xchg_best_ask(book)` | `Int` | Best price or `XCHG_NONE`. |
| `xchg_order_status(book, id)` | `Int` | `XCHG_STATUS_*` or `XCHG_NONE`. |
| `xchg_order_remaining(book, id)` | `Int` | Unfilled qty or `XCHG_NONE`. |
| `xchg_open_order_count(book)` | `Int` | Live resting orders. |
| `xchg_open_bid_qty(book)` / `xchg_open_ask_qty(book)` | `Int` | Resting qty sums. |
| `xchg_trade_count(book)` | `Int` | Tape length. |
| `xchg_last_trade_price(book)` | `Int` | Last trade price or `XCHG_NONE`. |
| `xchg_fees_maker_total(book)` / `xchg_fees_taker_total(book)` | `Int` | Fee counters. |
| `xchg_tape_*` | `Vec[Int]` | Copies of the tape columns (seqs, prices, qtys, sides, ids, fees). |
| `xchg_depth_bids(book, levels)` / `xchg_depth_asks(book, levels)` | `XchgDepth` | Top-N aggregated levels. |
| `xchg_candles(book, bucket_ticks)` | `XchgCandles` | OHLCV over tick buckets. |
| `xchg_fee(notional, bps)` | `Int` | `notional * bps / 10000`. |
| `xchg_invariant_ok(book)` | `Bool` | Full structural + accounting check. |

Constants: `XCHG_SIDE_BUY` (0), `XCHG_SIDE_SELL` (1), `XCHG_STATUS_OPEN` (0),
`XCHG_STATUS_FILLED` (1), `XCHG_STATUS_CANCELLED` (2), `XCHG_NONE` (-1).

```xi
use xiom.io; use xiom.core; use xiom.exchanger;
var b = xchg_book_new(2, 5);
let ask = xchg_submit_limit(&mut b, XCHG_SIDE_SELL, 100, 8);
let bid = xchg_submit_limit(&mut b, XCHG_SIDE_BUY, 103, 3);
io.println(core.to_string(xchg_best_ask(&b)));             // 100
io.println(core.to_string(xchg_order_remaining(&b, ask))); // 5
```

## Semantics in one paragraph

Best price first, ties by arrival (a replace loses priority). A crossing limit
order executes at each resting maker price, then rests its remainder. A market
order is IOC: it sweeps any liquidity and cancels its remainder. Every trade
charges `fee = qty * price * bps / 10000` truncated toward zero to both sides.
Candles bucket trades by `price / bucket_ticks`, first-touch order, with later
trades updating high/low/close/volume/trades in place. `SPEC.md` has the exact
rules and the full invariant list.

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 24 `[PASS]` lines, then `xiom.exchanger: all tests passed`, exit 0.

## Install / publish

```
xiom pkg install xiom.exchanger@0.1.0     # consumer
xiom pkg publish                          # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
