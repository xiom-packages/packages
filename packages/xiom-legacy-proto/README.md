# xiom.legacy-proto

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** three legacy internet text-protocol codecs in one dependency-free
> module: Finger queries/responses (RFC 1288), Gopher menu documents
> (RFC 1436) and WHOIS response records (RFC 3912). Text in, text out:
> parse, canonical render and deterministic error catalogs.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.legacy-proto` turns legacy protocol wire text

```
user/W
1Floodgap Gopher	/	floodgap.com	70
Domain Name: EXAMPLE.COM
Name Server: NS1.EXAMPLE.COM
```

into flat structs and back. Every function is pure and deterministic: it
works on `Str` input, returns plain values, and never performs I/O or keeps
state. Malformed input yields a documented `Err("finger: ...")` /
`Err("gopher: ...")` / `Err("whois: ...")` message, never a crash.

Three codecs live in one module because they share one shape: a small,
line-oriented, ASCII-era text format whose interesting parts are line
ending handling, field splitting and exact error behavior.

- **Finger (RFC 1288).** Query lines (`user`, `user/W`) and responses that
  are either a single line or a CRLF-separated block ended by a lone `.`
  terminator line.
- **Gopher (RFC 1436).** Menu documents of `type display TAB selector TAB
  host TAB port` lines plus `"." display` info-text lines.
- **WHOIS (RFC 3912).** Response records of `Key: value` fields with
  repeated keys, continuation lines and `%`/`#` comment lines.

Non-goals: no networking, no sockets, no DNS, no URL parsing, no policy for
response sizes and no UTF-8 validation (bytes are opaque).

## API

Types:

| Type | Fields |
|---|---|
| `FingerQuery` | `username` ("" = default user), `verbose` (the long `/W` format) |
| `FingerResponse` | `lines`, `is_multiline`, `had_terminator` |
| `GopherItem` | `item_type` (one byte, "." = info text), `display`, `selector`, `host`, `port` (0..65535) |
| `GopherMenu` | `types`, `displays`, `selectors`, `hosts`, `ports` -- five parallel, equal-length vectors |
| `WhoisRecord` | `keys`, `values` (parallel, repeats preserved), `continuation_counts`, `continuations` (flattened), `comments` |

Constants: `FINGER_PORT_DEFAULT` (79), `GOPHER_PORT_DEFAULT` (70),
`WHOIS_PORT_DEFAULT` (43).

Finger functions:

| Function | Returns | Description |
|---|---|---|
| `finger_parse_query(query)` | `Result[FingerQuery, Str]` | Parse `[ user ] [ "/W" ]`; truncates at CR/LF, trims, errors on empty/interior whitespace. |
| `finger_render_query(q)` | `Str` | Canonical query: `username` + `/W` when verbose, then CRLF. |
| `finger_parse_response(text)` | `Result[FingerResponse, Str]` | Split the response into content lines; the first lone `.` ends it. |
| `finger_render_response(r)` | `Str` | Canonical response: every line + CRLF, then `.\r\n` when multi-line. |
| `finger_is_multiline(r)` | `Bool` | More than one content line, or a terminator was present. |
| `finger_line_count(r)` | `Int` | Number of content lines. |
| `finger_line(r, i)` | `Str` | Content line `i`; `""` out of range. |

Gopher functions:

| Function | Returns | Description |
|---|---|---|
| `gopher_parse_item(line)` | `Result[GopherItem, Str]` | Parse one menu line (type + display + TAB selector + TAB host + TAB port, or `"." display`). |
| `gopher_render_item(item)` | `Str` | Canonical line with escaped fields and CRLF. |
| `gopher_parse_menu(text)` | `Result[GopherMenu, Str]` | Parse a whole menu; a malformed line yields `gopher: line N: <reason>`. |
| `gopher_render_menu(m)` | `Str` | Canonical CRLF document; byte-stable across parse/render. |
| `gopher_item_count(m)` | `Int` | Number of items. |
| `gopher_item_type(m, i)` | `Str` | One-byte type of item `i`; `""` out of range. |
| `gopher_item_display(m, i)` | `Str` | Decoded display text of item `i`. |
| `gopher_item_selector(m, i)` | `Str` | Decoded selector of item `i` (`""` for info text). |
| `gopher_item_host(m, i)` | `Str` | Decoded host of item `i` (`""` for info text). |
| `gopher_item_port(m, i)` | `Int` | Port of item `i`; `-1` out of range. |
| `gopher_item_is_text(m, i)` | `Bool` | True when item `i` has type `"."`. |

WHOIS functions:

| Function | Returns | Description |
|---|---|---|
| `whois_parse(text)` | `Result[WhoisRecord, Str]` | Parse fields, continuations and comments; blank lines are skipped, the first colon splits. |
| `whois_render(r)` | `Str` | Canonical CRLF record: comments first, then fields with their continuations. |
| `whois_field_count(r)` | `Int` | Number of fields (repeats counted). |
| `whois_key(r, i)` | `Str` | Key of field `i`; `""` out of range. |
| `whois_value(r, i)` | `Str` | Value of field `i`; `""` out of range or empty. |
| `whois_continuation_count(r, i)` | `Int` | Continuation lines attached to field `i`; `0` out of range. |
| `whois_continuation(r, i, j)` | `Str` | Continuation line `j` of field `i`; `""` out of range. |
| `whois_comment_count(r)` | `Int` | Number of `%`/`#` comment lines. |
| `whois_comment(r, i)` | `Str` | Comment line `i` with its marker; `""` out of range. |
| `whois_count(r, key)` | `Int` | Occurrences of a byte-exact key. |
| `whois_field(r, key)` | `Option[Str]` | Value of the final occurrence of `key`; `None` when absent. |

## Quick start

```xi
use xiom.legacy_proto;
use xiom.io;

fn main() -> Int {
  match finger_parse_query("ada/W") {
    Ok(q) => { io.println(finger_render_query(&q)); },  // ada/W
    Err(e) => { io.println(e); },
  }
  let item = gopher_parse_item("1Floodgap Gopher\t/\tfloodgap.com\t70\r\n");
  match item {
    Ok(it) => { io.println(gopher_render_item(&it)); },
    Err(e2) => { io.println(e2); },
  }
  match whois_parse("Name Server: NS1.EXAMPLE.COM\r\nName Server: NS2.EXAMPLE.COM\r\n") {
    Ok(rec) => {
      io.println(whois_count(&rec, "Name Server"));            // 2
      match whois_field(&rec, "Name Server") {
        Some(v) => { io.println(v); },                         // NS2.EXAMPLE.COM
        None => { io.println("absent"); },
      }
    },
    Err(e3) => { io.println(e3); },
  }
  return 0;
}
```

## Install / publish

```
xiom pkg install xiom.legacy-proto@0.1.0   # consumer (once published)
xiom pkg publish                           # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Until the first registry release, build and test the package from this
repository with `.\scripts\port.ps1 -Package xiom.legacy-proto`; consumers
inside the monorepo can depend on `xiom.legacy-proto` directly.

## Error model

Every fallible entry point returns `Err(Str)` whose message starts with the
protocol name (`finger: `, `gopher: `, `whois: `) and is deterministic: no
line numbers except `gopher: line N: ...`, no hidden state. The full catalog
is in `SPEC.md` section 9.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.legacy-proto
```

Expected tail: 24 `[PASS]` lines, `xiom.legacy_proto: all tests passed`,
then `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No networking:** the codecs only parse and build text; sockets, DNS and
  connection policy belong to the caller.
- **Byte-oriented, no UTF-8 policy:** bytes are opaque and are never
  validated, normalized or transcoded.
- **Canonical rendering:** parse -> render is byte-exact for canonical
  wire text; non-canonical input is normalized (line endings become CRLF,
  multi-line Finger responses gain their `.` terminator, Gopher escapes are
  canonicalized, WHOIS comments move before fields and blank lines are
  dropped).
- **Gopher escaping is a codec convention:** RFC 1436 defines no escaping,
  so the codec pins one (`\t`, `\n`, `\r`, `\\`) to stay lossless; unknown
  escapes keep both bytes verbatim.
- **Lenient line endings:** CRLF, LF and CR are all accepted everywhere; a
  final unterminated line is accepted.
- **No response-size limits and no policy:** line lengths, menu sizes and
  WHOIS record sizes are not checked or capped.

See `SPEC.md` for the exact grammars, parsing decisions, escaping rules,
error catalog and test matrix. License: MIT OR Apache-2.0 (see the
repository root `LICENSE`).
