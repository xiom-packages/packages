# xiom.pagination -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.pagination` (`src/pagination.xi`). Pure XIOM, no FFI. Depends
only on `xiom.std` (`xiom.string`, `xiom.string.builder`, `xiom.convert`).

## 1. Scope

Two independent halves:

1. **Page math** over 1-based pages and half-open item windows:
   `page_offset`, `page_count`, `page_bounds`, `page_has_next`,
   `page_has_prev`, `page_last`, `page_clamp`.
2. **Opaque cursor tokens** carrying an `(offset, limit)` pair for list
   endpoints: `cursor_encode`, `cursor_decode`. base64url (RFC 4648
   section 5, `-`/`_`, no `=`) is implemented inside the package, so there is
   no sibling-package dependency.

## 2. Non-goals

- Sorting, filtering, or any query model beyond a numeric window.
- Live/stateful cursors over a database result set; tokens here are
  stateless position markers.
- Signed, encrypted, compressed, versioned or expiring tokens.
- Configurable alphabets or token formats.
- Any FFI, I/O, or registry integration.

## 3. Page model and clamping rules

1. **Basis.** Pages are 1-based. A page window is half-open `[start, end)`,
   so `end - start` is the number of items on the page (not `end - start - 1`).
2. **Invalid inputs.** `page < 1`, `per_page < 1`, `total <= 0` are never an
   error; each function applies its documented clamp.
3. **`page_offset(page, per_page)`** = `(page - 1) * per_page`; `0` when
   `page < 1` or `per_page < 1`. When the exact product would exceed the
   64-bit signed maximum `9223372036854775807`, the result is clamped to that
   maximum instead of wrapping. Overflow safety is checked by comparing
   `page - 1` against `Int max / per_page` before multiplying.
4. **`page_count(total, per_page)`** = `ceil(total / per_page)`; `0` when
   `total <= 0` or `per_page < 1`. Computed as floor division plus one when a
   remainder exists, so no intermediate addition can overflow.
   `page_last(total, per_page)` is exactly `page_count(total, per_page)`.
5. **`page_bounds(page, per_page, total)`** returns `(start, end)` with
   `start = page_offset(page, per_page)` and
   `end = min(start + per_page, total)` for `1 <= page <= page_last`;
   `end` is exclusive and `0 <= start < end <= total`. Any page outside
   `1..page_last` (including `per_page < 1` or `total <= 0`) yields
   `(0, 0)`. The end is clamped by comparison (`per_page > total - start`)
   before any addition, so a huge `per_page` cannot overflow.
6. **`page_has_next(page, per_page, total)`** is true iff
   `1 <= page < page_last(total, per_page)`.
   **`page_has_prev(page)`** is `page > 1`.
7. **`page_clamp(page, total, per_page)`** maps `page` into `1..page_last`:
   `page < 1` becomes `1`, `page > page_last` becomes `page_last`. For an
   empty collection (`total <= 0` or `per_page < 1`, so `page_last == 0`)
   it returns `1` -- the documented convention that page 1 is "the" page of
   an empty collection.
8. **Empty collection.** `page_count = page_last = 0`; `page_bounds` is
   `(0, 0)`; `page_has_next` is false; `page_clamp` is `1`.

### Pinned examples

| Call | Result |
|---|---|
| `page_offset(3, 10)` | `20` |
| `page_offset(0, 10)` | `0` |
| `page_offset(9223372036854775807, 2)` | `9223372036854775807` (clamped) |
| `page_count(101, 10)` | `11` |
| `page_bounds(1, 10, 100)` | `(0, 10)` |
| `page_bounds(10, 10, 95)` | `(90, 95)` |
| `page_bounds(11, 10, 100)` | `(0, 0)` |
| `page_clamp(99, 100, 10)` | `10` |
| `page_clamp(7, 0, 10)` | `1` |

## 4. Cursor token grammar

```
token   = base64url_nopad( pair )
pair    = offset ":" limit
offset  = "0" | nonzero *digit            ; >= 0, no sign, no leading zeros
limit   = nonzero *digit                  ; >= 1, no sign, no leading zeros
base64url_nopad = data | data ( "=" excluded )
data    = 2..* ( ALPHA / DIGIT / "-" / "_" ), length % 4 != 1
```

- `cursor_encode(offset, limit)` clamps `offset` to `>= 0` and `limit` to
  `>= 1`, renders `"<offset>:<limit>"` in ASCII, and encodes it as unpadded
  base64url. A 1-byte tail becomes 2 characters, a 2-byte tail 3 characters;
  the output length is `ceil(bytes / 3) * 4 <= 3 mod 4`.
- `cursor_decode(token)` validates in this order, first failure wins:
  1. empty token;
  2. every byte inside the URL-safe alphabet (`+`, `/` and `=` are invalid:
     cursors are unpadded and URL-safe);
  3. character count not `1 (mod 4)`;
  4. decoding to bytes, then shape: exactly one `:`, both sides non-empty,
     every other byte an ASCII digit;
  5. canonical numbers: no leading zeros (`"0"` is the only accepted zero
     form for the offset; the limit cannot start with `0`, which also
     enforces `limit >= 1`);
  6. range: each value `<= 9223372036854775807`.
- Trailing bits of a 2- or 3-character tail are ignored on decode
  (non-canonical encodings map to the same bytes), matching `xiom.codec`'s
  base64url decoder.
- **Integrity.** Tokens are opaque and **not signed**: decoding proves only a
  well-formed pair, never authenticity. Callers must re-validate the pair
  against their data and authorization rules. Encoding is deterministic; the
  format carries no version, expiry or encryption.
- Pinned tokens: `("0", 10)` -> `"MDoxMA"`, `(123, 50)` -> `"MTIzOjUw"`,
  `(9223372036854775807, 1)` ->
  `"OTIyMzM3MjAzNjg1NDc3NTgwNzox"`, `(0, 1)` -> `"MDox"`.

## 5. API reference

All functions are free functions on `xiom.pagination` (no methods, no FFI).

| Function | Signature | Notes |
|---|---|---|
| `page_offset` | `(Int, Int) -> Int` | Overflow clamps to `Int` max. |
| `page_count` | `(Int, Int) -> Int` | Ceiling division; `0` for empty input. |
| `page_bounds` | `(Int, Int, Int) -> (Int, Int)` | `(start, end)` half-open, `(0, 0)` outside `1..last`. |
| `page_has_next` | `(Int, Int, Int) -> Bool` | `page < page_last`. |
| `page_has_prev` | `(Int) -> Bool` | `page > 1`. |
| `page_last` | `(Int, Int) -> Int` | `page_count`; `0` when none. |
| `page_clamp` | `(Int, Int, Int) -> Int` | Argument order `(page, total, per_page)`. |
| `cursor_encode` | `(Int, Int) -> Str` | Negative offset -> `0`; limit < 1 -> `1`. |
| `cursor_decode` | `(Str) -> Result[(Int, Int), Str]` | Canonical tokens only. |

## 6. Error catalog

`cursor_decode` errors are `Err(message)` with these exact messages:

| Message | Trigger |
|---|---|
| `pagination: empty cursor` | `token` has length 0. |
| `pagination: invalid cursor character` | A byte outside `A-Z a-z 0-9 - _` (`+`, `/`, `=`, whitespace, any non-ASCII byte). |
| `pagination: invalid cursor length` | Character count is `1 (mod 4)` (impossible base64 length). |
| `pagination: invalid cursor shape` | Decoded bytes are not `digits ":" digits` (missing/extra `:`, empty side, non-digit byte, zero limit). |
| `pagination: non-canonical cursor` | Leading zero in a number (`"00:10"`, `"0:0"`, `"0:01"`). |
| `pagination: cursor value out of range` | A parsed value exceeds `9223372036854775807`. |

All page-math functions are infallible.

## 7. Test plan

Suite: `tests/test_conformance.xi`, module `pagination_tests`, `fn main() ->
Int` returning the failed-test count. 20 checks:

| # | Check |
|---|---|
| 1 | `page_offset` basics and invalid inputs (`0`). |
| 2 | `page_offset` overflow boundary (clamp to `Int` max, exact `(2, max)` product). |
| 3 | `page_count` exact division and empty inputs. |
| 4 | `page_count` ceiling and `Int`-max values. |
| 5 | `page_bounds` first/middle windows. |
| 6 | `page_bounds` last page clamped to total, huge-`per_page` overflow path. |
| 7 | `page_bounds` out-of-range page and invalid inputs -> `(0, 0)`. |
| 8 | `page_has_next` true exactly while `page < last`. |
| 9 | `page_has_prev` is `page > 1`. |
| 10 | `page_last` and `0` when there are no pages. |
| 11 | `page_clamp` into `1..last`, `1` when empty. |
| 12 | Cursor round-trips (`0:10`, `123:50`, `0:1`, `1:1`, `999:1000`). |
| 13 | Cursor large values and pinned known tokens. |
| 14 | Cursor bad alphabet and padding are `Err`. |
| 15 | Cursor bad shape, empty token, leading zeros, zero limit, overflow are `Err`. |
| 16 | Negative offset/limit clamping on encode. |
| 17 | Cursor output is canonical, unpadded, URL-safe. |
| 18 | Empty collection: no pages, clamp reports page 1. |
| 19 | Consistency: bounds tile `[0, total)` and match `page_offset`. |
| 20 | Consistency: `has_next`/`has_prev` agree with `page_last`. |

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.pagination
```

Expected tail: 20 `[PASS]` lines, `xiom.pagination: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

Note: check 19 asserts the mathematically correct end-exclusive window size
`end - start == per_page`; the task brief's "per_page - 1" wording matches an
inclusive-end reading, which this package does not use.
