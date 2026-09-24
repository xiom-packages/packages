# xiom.uri -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.uri` (`src/uri.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free codec for in-memory `Str` URI references:

- `uri_parse` / `uri_to_string` -- RFC 3986 generic syntax <-> `Uri`,
- `uri_percent_decode` / `uri_percent_encode` -- percent escapes,
- `uri_host` / `uri_port` -- raw authority decomposition,
- `uri_query_get` -- first-match query parameter lookup,
- `uri_is_absolute` -- scheme presence.

Normalization, relative-reference resolution, IDN, host/port validation and
URI comparison are non-goals (see section 10).

## 2. Data model

```xi
pub type Uri = {
  scheme: Str;     // without ':', "" when absent
  authority: Str;  // raw (userinfo/host/port undivided), "" when absent
  path: Str;       // "" when absent
  query: Str;      // without '?', "" when absent
  fragment: Str;   // without '#', "" when absent
}
```

There is no field that records whether a component was absent versus present
but empty; both map to `""`. This is what makes `"http://"` (empty authority)
serialize as `"http:"` (section 10).

## 3. Grammar

```
URI-reference = [ scheme ":" ] [ "//" authority ] path [ "?" query ]
                [ "#" fragment ]
scheme        = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
authority     = *byte                     ; raw, up to '/', '?' or '#'
path          = *byte                     ; raw, up to '?' or '#'
query         = *byte                     ; raw, up to '#'
fragment      = *byte                     ; raw remainder
```

Recognition is byte-oriented and follows RFC 3986 appendix B: the first
occurrence among `:`, `/`, `?`, `#` decides whether a scheme is present.

## 4. Parsing semantics

1. **Scheme detection.** Scan for the first byte among `:`, `/`, `?`, `#`.
   - If it is `:`, the prefix is a scheme candidate. An empty prefix is
     `Err("uri: empty scheme")`; a prefix that is not
     `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )` is
     `Err("uri: invalid scheme")`. A valid scheme is stored without the `:`
     and parsing continues after it.
   - Otherwise (first byte is `/`, `?`, `#`, or none of them occurs) there
     is no scheme and the whole text is the remainder. This makes `":x"`
     an error, while `"/a:b"`, `"a/b:c"` and `"?x:y"` keep the `:` as an
     ordinary path/query byte.
2. **Authority.** When the remainder starts with `"//"`, the authority is
   the raw text up to the next `/`, `?` or `#` (possibly empty) and parsing
   continues at that byte. No userinfo/host/port split happens here.
3. **Path.** The path is the text up to the next `?` or `#` (or the rest).
4. **Query.** If a `?` was found before any `#`, the query is the text
   between it and the `#` (or the rest).
5. **Fragment.** If a `#` was found, the fragment is the remainder after it.
6. **No processing.** No percent-decoding, case folding, dot-segment removal
   or other normalization is applied; every component is stored byte-exact.
7. **Empty input.** `""` parses to `Uri{ scheme: "", authority: "", path:
   "", query: "", fragment: "" }` (the same-document reference).

`uri_to_string` reverses the split:

```
[ scheme ":" ] [ "//" authority ] path [ "?" query ] [ "#" fragment ]
```

where `scheme:`, `//authority`, `?query` and `#fragment` are emitted only
for non-empty fields. It is the exact inverse for the inputs parity-tested in
section 8, and lossy only for an empty-but-present authority (section 10).

## 5. Percent-encoding rules

Sets (RFC 3986 section 2):

- unreserved: `A-Z a-z 0-9 - . _ ~`
- reserved (gen-delims + sub-delims): `: / ? # [ ] @ ! $ & ' ( ) * + , ; =`

`uri_percent_decode(s)`:

- `%XX` is decoded with case-insensitive hex digits; each escape yields one
  raw byte. Other bytes pass through verbatim.
- `'+'` is a literal plus and is never converted to a space.
- `Err("uri: truncated percent escape")` when `%` is not followed by two
  bytes (including a trailing `%` and a one-digit tail).
- `Err("uri: invalid percent escape")` when either following byte is not
  `0-9 a-f A-F`.
- Output bytes are not re-validated as UTF-8: `%FF` yields one 0xFF byte.

`uri_percent_encode(s, encode_reserved)`:

- Works on the UTF-8 bytes of `s`, one output escape per input byte.
- `encode_reserved = false`: bytes in the unreserved **or** reserved set are
  copied literally; everything else becomes `%XX` (so `/`, `?`, `=`, `&`,
  `+`, `:` stay readable).
- `encode_reserved = true`: only unreserved bytes are copied literally;
  every other byte becomes `%XX` (including space, `%`, `/`, `+`, `:` and
  all non-ASCII bytes).
- Hex digits are uppercase (`%C3%A9`, never `%c3%a9`).
- Encoding is total (no error case) and `decode(encode(s)) == s` in both
  modes, because `%` itself is always encoded.

## 6. API signatures

```xi
pub fn uri_parse(s: Str) -> Result[Uri, Str]
pub fn uri_to_string(u: &Uri) -> Str
pub fn uri_percent_decode(s: Str) -> Result[Str, Str]
pub fn uri_percent_encode(s: Str, encode_reserved: Bool) -> Str
pub fn uri_host(u: &Uri) -> Str
pub fn uri_port(u: &Uri) -> Int
pub fn uri_query_get(u: &Uri, name: Str) -> Option[Str]
pub fn uri_is_absolute(u: &Uri) -> Bool
```

Complexity: all functions are `O(n)` in their input (the query lookup scans
the query once; `uri_host`/`uri_port` scan the authority once).

### Component helper semantics

- `uri_host`: drop everything through the **last** `@` (userinfo), then, if
  the rest starts with `[`, return through the matching `]` (brackets kept);
  otherwise return everything before the **last** `:` (port separator).
  `"user:pass@host:8080"` -> `"host"`; `"[::1]:443"` -> `"[::1]"`.
- `uri_port`: for a bracketed host, require `]:` and parse the digits after
  it; otherwise parse the digits after the last `:`. `-1` when there is no
  separator, the digits are empty or any character is not a decimal digit,
  or the digit run exceeds 18 (overflow guard). No 0..65535 range check.
- `uri_query_get`: split the query on `&`, skip empty segments, split each
  segment at the first `=`, compare the raw name byte-exactly
  (case-sensitive, before decoding) and return the first hit. A pair without
  `=` yields `Some("")`. The value is percent-decoded; on a decode error the
  raw value is returned literally. `None` when the query is empty or the
  name is absent.

## 7. Error catalog

Fallible functions return `Err` messages that all start with `"uri: "`:

| Message | Trigger |
|---|---|
| `uri: empty scheme` | the text starts with `:` (e.g. `":x"`, `":"`) |
| `uri: invalid scheme` | a scheme candidate before the first `:` is not `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`: `"1abc:x"`, `"a_b:x"`, `"a b:x"`, `"ht%tp:x"` |
| `uri: truncated percent escape` | `"%"`, `"abc%"`, `"%2"`, any `%` with fewer than two following bytes |
| `uri: invalid percent escape` | `"%2G"`, `"%GG"`, `"100%x"`, any `%` followed by a non-hex byte |

`uri_to_string`, `uri_percent_encode`, the host/port helpers, the query
lookup and `uri_is_absolute` are infallible.

## 8. Test plan

`tests/test_conformance.xi` (module `uri_tests`) runs 22 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Every `Str` comparison goes through
`xiom.string.compare`'s `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | full URL split | `https://user:pass@example.com:8080/path/to?x=1&y=2#frag` -> all five fields |
| t2 | mailto | no authority; scheme + path only |
| t3 | relative path | `docs/guide.html`, no scheme/authority |
| t4 | query-only | `?q=hello&lang=en` |
| t5 | fragment-only | `#section-2` |
| t6 | round-trips | parse -> to_string for https, mailto and `/assets/app.js?v=2` |
| t7 | decode mixed case | `%48%65llo%20World`, `%2f%2F`, `%41%62%43`, `%68%C3%A9llo`, plain, empty |
| t8 | decode malformed | truncated (`%`, `abc%`, `%2`) and invalid (`%2G`, `%GG`, `100%x`) with exact messages |
| t9 | decode `+` | `a+b` -> `a+b`, `%2B` -> `+`, `+%20+` -> `+ +` |
| t10 | encode mode false | reserved kept literal; `%` and space encoded; `é` -> `%C3%A9` |
| t11 | encode mode true | full reserved set encoded, uppercase hex, `+` -> `%2B` |
| t12 | unicode bytes | `héllo` and 4-byte emoji encoded byte-wise in both modes; decode back |
| t13 | host | `user:pass@host:8080`, `user@example.com`, IPv6 with userinfo, empty |
| t14 | IPv6 host/port | `[::1]:443`, `[2001:db8::1]`, `[::1]:`, `[::1]:abc` |
| t15 | port | present, absent, empty, non-numeric, with userinfo, 65535, empty authority |
| t16 | query_get | first match wins, value decoded, missing/case-mismatch None, bare flag |
| t17 | query_get raw | invalid escape kept literal, raw name match, `+` literal |
| t18 | is_absolute | scheme non-empty: http/mailto true; path/query/fragment/empty false |
| t19 | malformed schemes | exact empty-scheme message, four invalid-scheme cases, valid `a+b.c-d` |
| t20 | empty input | five empty components; `""` round-trips; `":"` errors |
| t21 | appendix-B `:` | `:` after the first `/` is path/query (three forms + one mixed URL) |
| t22 | encode/decode + to_string | both-mode round trips (ASCII, unicode, reserved, `%`, `+`) and the non-empty-authority `//` rule |

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the proven v0.61.3
idioms from the sibling packages (`xiom.codec`, `xiom.cookie`, `xiom.csv`):

- free functions only, byte-wise scanning with
  `(string.byte_at(s, i) as Int) & 0xFF` before any comparison;
- output accumulated in a `xiom.string.builder` buffer
  (`sb_push_byte`/`sb_push_str`, one `sb_to_str` allocation per result);
- `Ok`/`Err` for `Result[Uri, Str]` and `Result[Str, Str]` constructed only
  in the leaf helpers `_ok_uri`/`_err_uri`/`_ok_str`/`_err_str`;
- `Str` equality only through `str_compare` (BUG 17); the module never uses
  `==` on `Str`;
- no `Vec[StructType]`, no inline lambdas, no `Vec[fn]` dispatch, no `mut`
  patterns; every `match` is exhaustive and the suite dispatches through one
  explicit `fn` per check in `main`;
- `uri_port` caps the digit run at 18 so the accumulator cannot overflow.

## 10. Known limitations

- No normalization (scheme/host case, percent-escape case, dot segments,
  default ports), no relative-reference resolution, no URI comparison.
- No IDN/IDNA, no Unicode normalization: bytes are preserved verbatim.
- Raw authority: no userinfo/host/port validation; `uri_host`/`uri_port`
  use the last `@` and the last `:` (outside IPv6 brackets) as separators;
  bracketless IPv6 literals are unsupported and split at the last colon.
- `uri_port` does not enforce 0..65535 and silently treats a >18-digit run
  as invalid.
- An empty-but-present authority is indistinguishable from an absent one:
  `"http://"` -> `authority == ""` -> `"http:"`, and `"http:///p"` ->
  `"http:/p"`. There is no round trip through an empty authority.
- Percent decoding is byte-oriented and does not validate UTF-8; `+` is
  never a space (not `application/x-www-form-urlencoded`).
- Query lookup splits on `&` only, matches names raw/case-sensitively, and
  returns only the first match; no `;` separators, no form decoding, no
  multi-value retrieval.
