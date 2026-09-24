# xiom.pagination

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** page/offset math and opaque cursor tokens for list endpoints.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.builder.sb_to_str` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.pagination` answers the arithmetic every list endpoint needs -- which
items belong to page N, how many pages exist, is there a next page -- and
wraps an `(offset, limit)` pair in one opaque token suitable for a
`?cursor=...` query parameter. Pages are 1-based and windows are half-open
`[start, end)`, so `end - start` is the number of items on the page. Cursor
tokens are base64url (RFC 4648 section 5, `-`/`_`, no `=`) over the ASCII
text `"<offset>:<limit>"`; encoding is implemented inside this package, so
the only dependency is `xiom.std`.

## API

| Function | Returns | Description |
|---|---|---|
| `page_offset(page, per_page)` | `Int` | `(page - 1) * per_page`; `0` for `page < 1` or `per_page < 1`; clamps to `Int` max instead of overflowing. |
| `page_count(total, per_page)` | `Int` | `ceil(total / per_page)`; `0` when `total <= 0` or `per_page < 1`. |
| `page_bounds(page, per_page, total)` | `(Int, Int)` | Half-open `[start, end)` clamped to `total`; `(0, 0)` when the page lies outside `1..page_last`. |
| `page_has_next(page, per_page, total)` | `Bool` | True iff `1 <= page < page_last(total, per_page)`. |
| `page_has_prev(page)` | `Bool` | `page > 1`. |
| `page_last(total, per_page)` | `Int` | Largest valid page number; `0` when there are no pages. |
| `page_clamp(page, total, per_page)` | `Int` | Clamps into `1..page_last`; returns `1` for an empty collection. |
| `cursor_encode(offset, limit)` | `Str` | Unpadded base64url of `"<offset>:<limit>"`; offset clamped `>= 0`, limit clamped `>= 1`. |
| `cursor_decode(token)` | `Result[(Int, Int), Str]` | `Ok((offset, limit))` for a canonical token; `Err("pagination: ...")` otherwise. |

## Usage

```xi
use xiom.pagination;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  let total = 95;
  io.println(convert.int_to_string(page_count(total, 10)));  // 10
  io.println(convert.int_to_string(page_last(total, 10)));   // 10
  io.println(convert.int_to_string(page_clamp(99, total, 10))); // 10

  let (start, end) = page_bounds(2, 10, total);
  io.println(convert.int_to_string(start));                  // 10
  io.println(convert.int_to_string(end));                    // 20

  let token = cursor_encode(20, 10);        // opaque, e.g. for ?cursor=
  match cursor_decode(token) {
    Ok(pair) => { io.println(convert.int_to_string(pair.0)); },  // 20
    Err(_) => {},
  }
  return 0;
}
```

## Cursors are opaque

- A cursor is **not signed and carries no integrity guarantee**. A client can
  forge or edit one; `cursor_decode` only proves the token is a well-formed
  `(offset, limit)` pair. Re-validate the pair against the data set (and the
  caller's authorization) before serving items.
- Do not parse tokens by hand: `cursor_decode` is the contract.
- Decoding is strict and canonical: URL-safe alphabet only (`-`, `_`), no
  `=`, no whitespace, exactly one `:`, unsigned decimal numbers without
  leading zeros, each no larger than `Int` max, `limit >= 1`. Anything else
  is `Err("pagination: ...")`.
- Encoding is deterministic: the same `(offset, limit)` always yields the
  same token. Tokens are neither encrypted nor expiring.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.pagination
```

Expected tail: 20 `[PASS]` lines, `xiom.pagination: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- Stateless integer arithmetic only: no live cursor over a result set, no
  sorting/filtering model, no database integration.
- Cursors are not signed, compressed, versioned or expiring. The format is
  documented as opaque, so changing the pair grammar would invalidate old
  tokens (breaking-change policy note).
- `page_bounds` returns `(0, 0)` -- not `(total, total)` -- for a page past
  the last one; use `page_last` when the end position is needed.
- FFI: none.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
