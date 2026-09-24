# xiom.cookie -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.cookie` (`src/cookie.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free HTTP cookie codec for in-memory `Str` header values:

- `cookie_parse_request` / `cookie_serialize_request` -- request `Cookie`
  header <-> `CookieJar`,
- `cookie_get` / `cookie_count` -- jar inspection,
- `cookie_parse_set` / `cookie_serialize_set` -- `Set-Cookie` header <->
  `SetCookie`.

Quoting, percent-decoding, the Netscape cookie file format, `Expires` and any
other date handling, and cookie-jar storage/matching policy are non-goals (see
section 10).

## 2. Data model

```xi
pub type CookieJar = {
  names: Vec[Str];   // name of each request pair
  values: Vec[Str];  // value of each request pair
}

pub type SetCookie = {
  name: Str;
  value: Str;
  path: Str;        // "" when absent
  domain: Str;      // "" when absent
  max_age: Int;     // -1 when absent or malformed
  secure: Bool;
  http_only: Bool;
  same_site: Str;   // "" when absent
}
```

`Vec[StructType]` is not usable in this compiler, so the jar is deliberately
flat: entry i is `(names[i], values[i])`. A name occurs at most once because
parsing keeps the first occurrence. A hand-built jar that is ragged (unequal
vector lengths) is read only up to the shortest vector.

## 3. Grammar

```
request        = segment *( ";" segment )
segment        = ws* name ws* "=" ws* value? ws*     ; first '=' splits
name           = 1*byte                             ; non-empty after trim
value          = *byte                              ; may be empty

set-cookie     = pair *( ";" attribute )
pair           = ws* name ws* "=" ws* value? ws*     ; required; first '=' splits
attribute      = ws* flag / avpair ws*
flag           = "Secure" / "HttpOnly"               ; case-insensitive
avpair         = attrname ws* "=" ws* value? ws*
attrname       = "Path" / "Domain" / "Max-Age" / "SameSite" / other
ws             = SP | TAB | CR | LF | VT | FF       ; whatever str_trim strips
```

Segments and attributes are located by scanning for `;` (0x3B); the first
`=` (0x3D) in a segment splits name and value. Everything is byte-oriented;
non-ASCII bytes pass through verbatim.

## 4. Request semantics

1. **Splitting.** The line is split on every `;`. A trailing `;` produces a
   final empty segment that is skipped.
2. **Trimming.** The segment and both sides of the first `=` are trimmed with
   `xiom.string.str_trim`.
3. **Skipping.** A segment is skipped when it is empty after trimming, when it
   contains no `=`, or when its trimmed name is empty. Skipping is never an
   error.
4. **Duplicates.** The first occurrence of a name wins; later occurrences are
   skipped. Names are compared byte-exactly and case-sensitively
   (`str_compare`), so `A` and `a` are different names.
5. **Empty values.** `a=` stores name `a` with value `""`.
6. **Order.** Entries keep first-seen order. `cookie_serialize_request`
   renders `name=value` joined by `"; "`; `""` for an empty jar (no trailing
   separator).

## 5. Set-Cookie semantics

1. **First pair.** The text before the first `;` (trimmed) must contain `=` and
   a non-empty trimmed name, otherwise `Err` (section 7). The value is the
   text after the first `=`, trimmed; it may be empty and may itself contain
   `=`.
2. **Attributes.** Each following segment is trimmed. With no `=`, the whole
   segment is matched case-insensitively against `Secure` and `HttpOnly`. With
   `=`, the name before the first `=` is trimmed and lowercased before
   matching; the value after it is trimmed.
3. **Path / Domain.** Stored trimmed. Last duplicate wins.
4. **Max-Age.** Applied only when the value is an optional `+`/`-` sign
   followed by 1..18 ASCII digits; the sign is honored, so `Max-Age=-1` stores
   `-1`. Any other value (`abc`, `12x`, ``, `-`, `1 2`, 19+ digits) leaves the
   attribute unapplied (`max_age` stays at its default `-1`). Later
   attributes still apply after an invalid Max-Age.
5. **Secure / HttpOnly.** Recognized only in the bare form; `Secure=1` and
   `HttpOnly=1` are ignored.
6. **SameSite.** Compared case-insensitively against `strict`, `lax` and
   `none` and stored canonically as `Strict`, `Lax`, `None`; any other value
   (including an empty one) is stored raw. `SameSite = Lax` trims around the
   `=` and stores `Lax`.
7. **Unknown attributes.** Ignored.
8. **Duplicates.** Attributes are applied left to right, so the last
   occurrence of an attribute wins.
9. **Serialization order.** `name=value`, then `; Path=`, `; Domain=`,
   `; Max-Age=N`, `; Secure`, `; HttpOnly`, `; SameSite=`, each emitted only
   when applicable: `path`, `domain` and `same_site` when non-empty, `max_age`
   when `>= 0`, flags when true. `name=value` is always emitted, even with an
   empty value. So `parse` then `serialize` round-trips a header whose
   attributes are already in this exact spelling and order.

## 6. API signatures

```xi
pub fn cookie_parse_request(line: Str) -> CookieJar
pub fn cookie_get(jar: &CookieJar, name: Str) -> Option[Str]
pub fn cookie_count(jar: &CookieJar) -> Int
pub fn cookie_serialize_request(jar: &CookieJar) -> Str
pub fn cookie_parse_set(line: Str) -> Result[SetCookie, Str]
pub fn cookie_serialize_set(c: &SetCookie) -> Str
```

Complexity: request parsing is `O(line length * jar size)` because duplicate
detection scans the names vector per segment (`O(line length)` with a hash
index); `cookie_get` is `O(entries)`; serialization is `O(output)`; Set-Cookie
parsing is `O(line length)`.

## 7. Error catalog

`cookie_parse_set` is the only fallible function. Every message starts with
`"cookie: "`:

| Message | Trigger |
|---|---|
| `cookie: missing name=value pair` | the first segment (trimmed) has no `=`: `""`, `"   "`, `"plain"`; also `"; a=1"`, whose first segment is empty |
| `cookie: empty cookie name` | the first segment has `=` but the trimmed name is empty: `"=v"`, `" =v ; Path=/"` |

`cookie_parse_request` never fails (malformed segments are skipped), and
`cookie_get` reports absence with `None`.

## 8. Test plan

`tests/test_conformance.xi` (module `cookie_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every `Str` comparison goes through
`xiom.string.compare`'s `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | request simple | three `name=value` pairs, count and values |
| t2 | request spaces | trim around names/values; `c` without `=` skipped |
| t3 | request multiple | four pairs keep order through serialization |
| t4 | request duplicates | first occurrence wins; later duplicates dropped |
| t5 | missing `=` | `junk`, empty segments and bare `c` skipped; `d=` keeps empty value |
| t6 | empty name | `=x`, `=`, empty name never stored; `cookie_get(jar, "")` is `None` |
| t7 | round-trip | serialize then parse preserves entries and text |
| t8 | get/count | empty jar inert; `""` serialize; ragged jar counts the minimum |
| t9 | set full | name/value and all six attributes parsed |
| t10 | case-insensitive | `pAtH`, `DOMAIN`, `max-age`, `sEcUrE`, `hTtPoNlY`, `sAmEsItE` |
| t11 | Max-Age valid | `3600`, `0`, `-1`, `+5`; `0` serialized, `-1` omitted |
| t12 | Max-Age invalid | `abc`, `12x`, ``, `-`, `1 2`, 19 digits ignored; later attributes apply |
| t13 | flags | bare `Secure`/`HttpOnly` set flags; `=1` forms ignored |
| t14 | SameSite | `lax`/`NONE`/`STRICT` canonicalized; `weird` raw; empty; spaces |
| t15 | missing pair Err | empty/blank/bare-word/pre-semicolon/empty-name inputs, exact messages |
| t16 | serialize omission | empty attributes omitted; full ordering pinned |
| t17 | `=` in value | request and Set-Cookie values keep internal `=` whole |
| t18 | empty request | `""`, blanks and separator-only input yield an empty jar |
| t19 | set round-trip | full header parse -> serialize -> parse preserves every field |
| t20 | name semantics | request names are case-sensitive; trim before dedup; trailing `;` |

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the proven v0.61.3
idioms from the sibling packages (`xiom.translation`, `xiom.csv`,
`xiom.validation`):

- `Vec[StructType]` is unsupported, so the jar is two parallel homogeneous
  vectors.
- `Ok`/`Err` for `Result[SetCookie, Str]` are constructed only in the leaf
  helpers `_ok_set`/`_err_set` (constructing Results directly inside other
  functions miscompiles on this compiler).
- `Str` equality goes through `xiom.string.compare.str_compare` (BUG 17: `==`
  on `Str` values read from `Vec[Str]` elements lowers to a pointer
  comparison); Vec elements are read into typed locals first.
- Bytes are read as `(string.byte_at(s, i) as Int) & 0xFF`; output is
  accumulated in a `xiom.string.builder` buffer (one allocation per rendered
  `Str`).
- The suite avoids inline lambdas, `mut` patterns, `Vec[fn]` dispatch and
  non-exhaustive `match`es by using one explicit `fn` per check and explicit
  `main` dispatch.
- Integer text is validated (`_is_int_text`) before conversion
  (`_int_value`), capped at 18 digits so the accumulator cannot overflow.

## 10. Known limitations

- No quoted-string values, no RFC 6265 quoting/escaping, no percent-decoding.
- No Netscape cookie file format (`domain\tflag\tpath\tsecure\texpiry\tname\tvalue`);
  only HTTP header values are parsed.
- No expiry math and no time parsing: `Expires` and every date attribute are
  ignored; `Max-Age` is a raw `Int` and is never compared to a clock.
- No syntactic validation of names, values, `Path` or `Domain` (empty names
  only are rejected); no attribute length limits.
- Duplicate attributes are last-wins, while duplicate request names are
  first-wins; both rules are pinned by the suite.
- Linear lookups; no index, no jar policy (domain/path matching, ordering by
  creation time, eviction) and no storage.
