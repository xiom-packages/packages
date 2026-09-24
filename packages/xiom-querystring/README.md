# xiom.querystring

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** `application/x-www-form-urlencoded` parsing and serialization
> with multi-value support.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## Scope

`xiom.querystring` is a small, dependency-free query-string codec over
in-memory `Str` values. It parses `a=1&b=2` text into a `Query` (an ordered,
flat list of name/value pairs held as two parallel `Vec[Str]`), inspects it,
edits it without mutating the source, and renders it back. There is no FFI,
no file I/O and no global state. `SPEC.md` has the full rules, encoding
tables and test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `qs_parse(text)` | `Query` | Split `text` on `&`; drop one optional leading `?`; skip empty segments; decode `+`/`%XX` on both sides; a segment without `=` gets the value `""`. Empty names and values are preserved and names may repeat in order. |
| `qs_count(q)` | `Int` | Number of pairs (min of the two parallel vector lengths). |
| `qs_get(q, name)` | `Option[Str]` | Value of the **first** pair named `name` (byte-exact, case-sensitive); `None` when absent. |
| `qs_get_all(q, name)` | `Vec[Str]` | Values of **every** pair named `name`, in pair order; empty vector when absent. |
| `qs_has(q, name)` | `Bool` | True when at least one pair is named `name` (byte-exact, case-sensitive). |
| `qs_set(q, name, value)` | `Query` | **New** query: replaces the first match in place, appends when absent. The source is never mutated. |
| `qs_remove(q, name)` | `Query` | **New** query with every pair named `name` removed. The source is never mutated. |
| `qs_serialize(q)` | `Str` | Pairs joined with `&`, always `name=value`, each side form-encoded; `""` for an empty query. |
| `qs_encode_component(s)` | `Str` | Form-encode one component: space `%20` becomes `+`; everything outside `[A-Za-z0-9-._~]` becomes `%XX` (uppercase hex). |
| `qs_decode_component(s)` | `Str` | Form-decode one component: `+` becomes a space; well-formed `%XX` (either hex case) becomes its byte; malformed escapes stay literal. Never errors. |

### Query

| Field | Type | Meaning |
|---|---|---|
| `names` | `Vec[Str]` | Pair names, index-aligned with `values`. |
| `values` | `Vec[Str]` | Pair values. Entry `i` is the pair `names[i]=values[i]`. |

## Encoding rules

| Input byte | Encoded form |
|---|---|
| `A-Z a-z 0-9` | unchanged |
| `- _ . ~` | unchanged |
| space (`0x20`) | `+` |
| any other byte | `%XX`, uppercase hex (e.g. `+` -> `%2B`, `&` -> `%26`, `=` -> `%3D`, `/` -> `%2F`, `?` -> `%3F`) |

Decoding is the inverse: `+` -> space, `%XX` -> byte (hex in either case).
A `%` not followed by two hex digits is kept literally and scanning resumes
after it, so `%`, `%2`, `%zz` and `100%` all round-trip unchanged. The codec
is byte-wise; non-ASCII text is encoded per UTF-8 byte (round-trips
byte-exact).

## Usage

```xi
use xiom.querystring;
use xiom.io;

fn main() -> Int {
  var q = qs_parse("?tag=rust&tag=xiom&q=hello+world");
  io.println(qs_serialize(&q));            // "tag=rust&tag=xiom&q=hello+world"
  match qs_get(&q, "tag") {
    Some(v) => { io.println(v); },         // "rust"
    None => { io.println("missing"); },
  }
  let all = qs_get_all(&q, "tag");         // ["rust", "xiom"]
  io.println(qs_count(&q));                // 3
  let edited = qs_set(&q, "q", "hi there");
  io.println(qs_serialize(&edited));       // "tag=rust&tag=xiom&q=hi+there"
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.querystring
```

Expected tail: 20 `[PASS]` lines, `xiom.querystring: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Flat pairs only:** the model is an ordered list of name/value strings.
  There is no nesting and no array syntax; `a[]=1&a[]=2` is stored as three
  literal names (`a[]` twice) plus the encoded brackets, it is not expanded.
- **Order-preserving:** duplicates are never collapsed; `qs_get` takes the
  first match and `qs_get_all` returns all matches in order.
- **Byte-oriented decoding:** `%XX` produces raw bytes, so decoding a sequence
  that is not valid UTF-8 yields a `Str` with those bytes (encoding it back
  reproduces the `%XX` form). Non-ASCII `Str` round-trips byte-exact.
- **No error channel:** every function is total; malformed percent escapes are
  kept literally rather than reported. `qs_parse` never fails.
- **No trimming:** whitespace around names/values is significant and kept.
- **`&` is the only separator:** the legacy `;` separator of early HTML is not
  recognized; `;` stays inside the name or value.
- **One leading `?` only:** a `?` after the first byte is an ordinary byte.
- **Linear lookups:** `qs_get`/`qs_get_all`/`qs_has`/`qs_set`/`qs_remove` scan
  the pair vectors; large queries want an external index.
- **No validation of name/value syntax:** any bytes other than the `&`/`=`
  delimiters are accepted as-is.

See `SPEC.md` for the full rules and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
