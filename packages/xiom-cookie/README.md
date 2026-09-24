# xiom.cookie

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** `Cookie` request-header parsing and serialization; `Set-Cookie`
> response-header parsing and serialization.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## Scope

`xiom.cookie` is a small, dependency-free HTTP cookie codec over in-memory
`Str` values. It parses a request `Cookie` line into a flat jar (two parallel
`Vec[Str]`), parses a `Set-Cookie` line into a flat `SetCookie` struct, and
renders both back. There is no FFI, no file I/O, no time handling and no
global state. `SPEC.md` has the full grammar, attribute semantics, error
catalog and test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `cookie_parse_request(line)` | `CookieJar` | Split a request `Cookie` line on `;`; trim each segment; keep `name=value` pairs in first-seen order. Segments without `=`, segments with an empty name and later duplicates of a name are skipped (first occurrence wins). |
| `cookie_get(jar, name)` | `Option[Str]` | Value of the first entry with byte-exact (case-sensitive) `name`; `None` when absent. |
| `cookie_count(jar)` | `Int` | Number of usable entries (min of the two parallel vector lengths). |
| `cookie_serialize_request(jar)` | `Str` | Render the jar as `"a=1; b=2"` in entry order; `""` for an empty jar. |
| `cookie_parse_set(line)` | `Result[SetCookie, Str]` | Parse a `Set-Cookie` line: a required first `name=value` pair plus optional attributes. `Err("cookie: ...")` when the first pair is missing or has an empty name. |
| `cookie_serialize_set(c)` | `Str` | Render `"name=value; Path=...; Domain=...; Max-Age=N; Secure; HttpOnly; SameSite=..."` in that order, omitting empty attributes and omitting `Max-Age` when `max_age < 0`. |

### SetCookie

| Field | Type | Meaning |
|---|---|---|
| `name` | `Str` | Cookie name (non-empty after trimming). |
| `value` | `Str` | Cookie value; may be empty and may contain `=`. |
| `path` | `Str` | `Path` attribute, `""` when absent. |
| `domain` | `Str` | `Domain` attribute, `""` when absent. |
| `max_age` | `Int` | `Max-Age` in seconds, `-1` when absent or malformed. |
| `secure` | `Bool` | Bare `Secure` attribute present. |
| `http_only` | `Bool` | Bare `HttpOnly` attribute present. |
| `same_site` | `Str` | `SameSite` value; known values canonicalized (`Strict`/`Lax`/`None`), others kept raw; `""` when absent. |

## Attributes

| Attribute | Recognition | Semantics |
|---|---|---|
| `Path` | case-insensitive name, `=value` | Stored trimmed; last duplicate wins. |
| `Domain` | case-insensitive name, `=value` | Stored trimmed; last duplicate wins. |
| `Max-Age` | case-insensitive name, `=value` | Optional `+`/`-` sign and 1..18 decimal digits; otherwise ignored. Negative values serialize omitted. |
| `Secure` | case-insensitive bare name | Sets `secure = true`; `Secure=...` is not recognized. |
| `HttpOnly` | case-insensitive bare name | Sets `http_only = true`; `HttpOnly=...` is not recognized. |
| `SameSite` | case-insensitive name, `=value` | `Strict`/`Lax`/`None` matched case-insensitively and stored canonically; any other value kept raw. |
| anything else | -- | Ignored. |

## Usage

```xi
use xiom.cookie;
use xiom.io;

fn main() -> Int {
  var jar = cookie_parse_request("sid=abc123; theme=dark");
  io.println(cookie_serialize_request(&jar));   // "sid=abc123; theme=dark"
  match cookie_get(&jar, "sid") {
    Some(v) => { io.println(v); },              // "abc123"
    None => { io.println("missing"); },
  }
  let r = cookie_parse_set("sid=abc123; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Lax");
  match r {
    Ok(c) => { io.println(cookie_serialize_set(&c)); },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.cookie
```

Expected tail: 20 `[PASS]` lines, `xiom.cookie: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No quoting or escaping:** values are taken literally between `=` and the
  next `;`; there is no RFC 6265 quoted-string form and no `\`-escaping.
- **No percent-decoding:** `%20` and friends stay as written.
- **No Netscape cookie file format:** only HTTP header values are handled; the
  `domain\tflag\tpath\tsecure\texpiry\tname\tvalue` text format is out of
  scope.
- **No expiry math or time parsing:** `Max-Age` is kept as a raw `Int`;
  `Expires` and all other date attributes are ignored, and no conversion to
  wall-clock time happens.
- **Last duplicate attribute wins** (request pairs, by contrast, keep the
  first occurrence); `cookie_parse_set` applies attributes left to right.
- **No validation of `name`, `value`, `Path` or `Domain` syntax:** any bytes
  other than `;` splitting are accepted as-is.
- **Linear lookups:** `cookie_get` scans the jar; large jars want an external
  index.

See `SPEC.md` for the full grammar, attribute and error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
