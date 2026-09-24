# xiom.uri

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** RFC 3986 URI-reference parsing and formatting, percent-encoding
> and component helpers (host, port, query lookup).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## Scope

`xiom.uri` is a small, dependency-free URI codec over in-memory `Str` values.
It splits a URI reference into scheme, authority, path, query and fragment
(the RFC 3986 appendix B algorithm), renders the components back, decodes and
encodes `%XX` escapes and exposes a few authority/query helpers. There is no
FFI, no file I/O, no networking and no global state. `SPEC.md` has the full
grammar, encoding rules, error catalog and test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `uri_parse(s)` | `Result[Uri, Str]` | Split a URI reference into the five components. The scheme is recognized only when a `:` appears before the first `/`, `?` or `#`; it must be `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`. `Err("uri: ...")` for an empty or malformed scheme; every other input parses. |
| `uri_to_string(u)` | `Str` | Inverse of `uri_parse`: `scheme:`, then `//authority` (only when the authority is non-empty), then path, `?query`, `#fragment`. |
| `uri_percent_decode(s)` | `Result[Str, Str]` | Decode `%XX` escapes (case-insensitive hex). `'+'` is **not** decoded to a space. `Err("uri: ...")` when a `%` is not followed by two hex digits. |
| `uri_percent_encode(s, encode_reserved)` | `Str` | Encode the UTF-8 bytes of `s`, one `%XX` per encoded byte with uppercase hex. `encode_reserved=false` keeps the unreserved **and** reserved sets literal; `true` keeps only unreserved. |
| `uri_host(u)` | `Str` | Authority minus userinfo (before the last `@`) and port (after `:`); IPv6 brackets are kept (`[::1]`). |
| `uri_port(u)` | `Int` | Port after `:` (or `]:` for IPv6); `-1` when absent, empty or non-numeric. |
| `uri_query_get(u, name)` | `Option[Str]` | First `name=value` pair in the query whose name matches byte-exactly and case-sensitively; the value is percent-decoded (kept literal when decoding fails). `None` when absent. |
| `uri_is_absolute(u)` | `Bool` | `true` when the scheme is non-empty. |

### Uri

| Field | Type | Meaning |
|---|---|---|
| `scheme` | `Str` | Scheme without `:`, `""` when absent. |
| `authority` | `Str` | Raw authority (userinfo/host/port undivided), `""` when absent. |
| `path` | `Str` | Path text, `""` when absent. |
| `query` | `Str` | Query without `?`, `""` when absent. |
| `fragment` | `Str` | Fragment without `#`, `""` when absent. |

## Grammar notes

- A scheme is recognized only when a `:` occurs before the first `/`, `?` or
  `#`. `"http://h/p"` has scheme `http`; `"/a:b"` and `"?x:y"` have no scheme
  and keep the `:` in the path/query.
- `//authority` is recognized immediately after the scheme separator (or at
  the start when there is no scheme) and runs to the next `/`, `?` or `#`.
- The path runs to the next `?` or `#`; the query runs to the next `#`; the
  fragment takes the rest. Nothing is normalized, decoded or re-encoded.
- `uri_to_string` adds `//` exactly when the authority is non-empty, so
  `"http://"` (empty authority) serializes as `"http:"` (documented).

## Usage

```xi
use xiom.uri;
use xiom.io;

fn main() -> Int {
  let r = uri_parse("https://user@example.com:8443/a/b?q=1#frag");
  match r {
    Ok(u) => {
      io.println(u.scheme);          // "https"
      io.println(u.authority);       // "user@example.com:8443"
      io.println(uri_host(&u));      // "example.com"
      io.println(uri_port(&u));      // 8443
      match uri_query_get(&u, "q") {
        Some(v) => { io.println(v); },   // "1"
        None => { io.println("missing"); },
      }
      io.println(uri_to_string(&u)); // the original text
    },
    Err(e) => { io.println(e); },
  }
  io.println(uri_percent_encode("a b/c", false));  // "a%20b/c"
  io.println(uri_percent_encode("a b/c", true));   // "a%20b%2Fc"
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.uri
```

Expected tail: 22 `[PASS]` lines, `xiom.uri: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No normalization or resolution:** no case folding, no dot-segment
  removal, no relative-reference resolution against a base, no default-port
  handling, no comparison/equality of URIs.
- **No IDN / punycode:** host names and other components stay raw bytes; no
  IDNA or Unicode normalization is applied.
- **Raw authority:** the parser does not validate userinfo/host/port syntax.
  `uri_host`/`uri_port` apply a documented split (last `@`, then last `:`
  outside an IPv6 bracket pair); bracketless IPv6 literals are unsupported.
- **Ports are not range-checked:** `uri_port` accepts any 1..18-digit run and
  does not enforce 0..65535.
- **Empty authority does not round-trip:** because the model cannot
  distinguish absent from empty, `"http://"` parses with `authority == ""`
  and serializes as `"http:"`; `"http:///p"` serializes as `"http:/p"`.
- **Percent decoding is byte-oriented:** decoded bytes are not re-validated
  as UTF-8 (for example `%FF` yields one raw 0xFF byte), and `+` is never a
  space (this is not `application/x-www-form-urlencoded`).
- **Query lookup is minimal:** pairs split on `&` only, names are matched
  raw and case-sensitively before decoding, and only the first match is
  returned.

See `SPEC.md` for the full grammar, encoding rules, error catalog and test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
