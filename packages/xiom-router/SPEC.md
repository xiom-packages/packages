# xiom.router -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.63.1 on
2026-10-05; not published).
Manifest: `package.xi` (`xiom.router`, version `0.1.0`).
Module: `src/router.xi` (`module xiom.router`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.compare`). No FFI.

## 1. Scope

A pure-XIOM, stdlib-only deterministic HTTP route table over in-memory
`Str` values. Routes are appended in order and looked up by method + path;
the first registered route whose pattern matches the path shape and whose
method equals the queried method wins. Three public types and seven public
functions:

```xi
pub type RouteParam = { name: Str; value: Str; }
pub type RouteMatch = { code: Int; index: Int; params: Vec[RouteParam]; }
pub type Router = { methods: Vec[Str]; patterns: Vec[Str]; }

pub fn router_new() -> Router
pub fn router_add(r: &mut Router, method: Str, pattern: Str) -> Result[Int, Str]
pub fn router_match(r: &Router, method: Str, path: Str) -> RouteMatch
pub fn router_allowed_methods(r: &Router, path: Str) -> Vec[Str]
pub fn router_count(r: &Router) -> Int
pub fn router_method(r: &Router, i: Int) -> Result[Str, Str]
pub fn router_pattern(r: &Router, i: Int) -> Result[Str, Str]
```

Private helpers: `_split_path`, `_path_shape_matches`, `_capture`,
`_is_param_segment`, `_contains_str`, `_byte_at_i`. The route table is two
parallel `Vec[Str]` fields pushed together, so `methods.len() ==
patterns.len()` always holds.

## 2. Non-goals

- **No specificity ranking**: registration order alone decides; static-vs-
  parameter patterns have no priority.
- **No wildcards, regex, catch-alls or path normalization**: pattern
  segments are literals or `:name` parameters only.
- **No percent-decoding, no query handling**: raw bytes are compared and
  captured as-is; the caller strips the query string.
- **No method normalization or validation**: methods are byte-exact strings;
  any non-empty byte string is legal.
- **No request/response types, handlers, middleware or server**: this is the
  lookup table, not a dispatcher or transport.
- **No persistence, I/O, FFI or global state.**

## 3. Path grammar and splitting

`_split_path(p)` produces the segment vector:

1. `p == ""` yields the empty vector.
2. One leading `/` is stripped when present.
3. The remainder is split on `/`; the final segment is the remainder after
   the last `/` (possibly empty).
4. If nothing remains after the leading `/` (the path was `"/"`), the
   vector is empty.

Consequences:

| Input | Segments | Note |
|---|---|---|
| `""` | `[]` | zero segments (documented; matches a root pattern) |
| `"/"` | `[]` | the root pattern has zero segments |
| `"/a"` | `["a"]` | |
| `"/a/"` | `["a", ""]` | trailing slash is significant |
| `"/a/b"` | `["a", "b"]` | |
| `"/a//b"` | `["a", "", "b"]` | interior empty segment is a literal `""` |
| `"a/b"` | `["a", "b"]` | no leading `/`; split as-is (not validated) |

A pattern segment is a **parameter** when it is at least 2 bytes long and
its first byte is `:` (58). The parameter name is the segment text after the
leading `:`; names are not restricted further (a name may contain `:`, `/`
cannot occur, and any other bytes are allowed). A single-byte `:` segment is
not a parameter; it is rejected by `router_add` as an empty parameter name.

## 4. Matching semantics

`router_match(r, method, path)` walks routes in registration order:

- Let `pat = patterns[i]`. `pat` matches the path **shape** when
  `_split_path(pat)` and `_split_path(path)` have equal length and every
  pair is:
  - parameter segment (pattern side) vs. a **non-empty** path segment, or
  - literal segment (pattern side) vs. byte-for-byte equal path segment.
- The first `i` whose pattern shape-matches and whose `methods[i]` equals
  `method` (byte-exact via `str_compare`) yields
  `RouteMatch{ code: 200; index: i; params: _capture(patterns[i], path) }`.
- If no such route exists but at least one pattern shape-matched, the result
  is `RouteMatch{ code: 405; index: -1; params: [] }`.
- If no pattern shape-matched, the result is
  `RouteMatch{ code: 404; index: -1; params: [] }`.

An empty path segment satisfies only a literal empty segment, never a
parameter. Because the empty path `""` has zero segments, it shape-matches
the root pattern `"/"` (a documented edge; HTTP request targets are never
empty).

`router_allowed_methods(r, path)` returns the methods of **every** pattern
whose path shape matches `path`, in registration order, deduplicated by
byte-exact comparison (first occurrence wins). It is the Allow-list input
for a 405 response and is empty for 404-shaped paths.

## 5. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `router_new()` | none | empty `Router` | none |
| `router_add(r, method, pattern)` | non-empty method; pattern starting with `/` with no bare `:` segment | `Ok(index)`, the new registration index (0-based, consecutive) | `router: empty method`, `router: pattern must start with '/'`, `router: empty parameter name`; nothing is registered on Err |
| `router_match(r, method, path)` | any method/path strings; `path` without its query string | `RouteMatch` with code 200/404/405, index and params as in section 4 | none |
| `router_allowed_methods(r, path)` | any path string | methods of all shape-matching patterns, registration order, deduplicated | none |
| `router_count(r)` | none | number of registered routes | none |
| `router_method(r, i)` | index | `Ok(method)` for `0 <= i < router_count(r)` | `router: index out of range` |
| `router_pattern(r, i)` | index | `Ok(pattern)` for `0 <= i < router_count(r)` | `router: index out of range` |

Invariants:

- `router_add` pushes both vectors together, so `router_count(r)` equals
  both `methods.len()` and `patterns.len()` at all observable times.
- A failed `router_add` leaves the table byte-for-byte unchanged.
- 404 and 405 `RouteMatch` values always carry `index == -1` and an empty
  `params`.
- A 200 `RouteMatch` always carries `0 <= index < router_count(r)` and
  `_capture` of the matching pair.
- `params` are in path order (left to right).

## 6. Test plan

`tests/test_conformance.xi` (module `router_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality goes through
`xiom.string.compare.str_compare` via the local `streq` helper; every Vec
element read is bound to a typed local.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | exact match | `GET /users` -> 200, index 0, no params; count 1 |
| t2 | first-match order | `/users/:id` before `/users/me` captures `me`; the reverse order yields the literal with no params |
| t3 | param capture single | `/users/:id` vs `/users/42` -> one param `id=42` |
| t4 | param capture multiple | `/:a/b/:c` vs `/x/b/z` -> `a=x`, `c=z` in order; literal `b` must match |
| t5 | param rejects empty segment | `/a/:p` does not match `/a/` (404, empty Allow-list) or `/a` |
| t6 | 404 | unknown path and segment-count mismatches both 404 with index -1, empty params |
| t7 | 405 + Allow | `GET`+`POST` on `/x`, `PUT` -> 405, `Allow = [GET, POST]`; `GET` still 200 |
| t8 | method case sensitivity | lowercase-registered `get` does not match `GET`/`Get` (405), matches `get` (200) |
| t9 | root route | `/` is a zero-segment pattern; `/x` is 404; the empty path also matches root; Allow has one entry |
| t10 | trailing slash | `/a` vs `/a/` are distinct routes with distinct indices |
| t11 | multi-segment | five-segment pattern with two captures; a shorter path is 404 |
| t12 | router_add validation | empty method; empty pattern; missing leading `/`; bare `:` segments; count unchanged; `x:` is a valid literal |
| t13 | add indices | three adds return 0, 1, 2; count 3 |
| t14 | accessors | in-range `Ok` values; `-1` and `count` are `router: index out of range` on both accessors |
| t15 | 405 on param pattern | `DELETE /u/7` -> 405 with empty params and Allow `[GET, POST]` |
| t16 | Allow dedup | `GET, GET, POST` -> `[GET, POST]` |
| t17 | Allow order | `POST` registered before `GET` -> `[POST, GET]` |
| t18 | Allow empty | non-matching path and segment-count mismatch -> empty vector |
| t19 | later method match | earlier shape match with another method does not stop the scan; `GET` wins at a later index, `DELETE` is 405 |
| t20 | literal empty segment | `/a//b` matches only `/a//b`; `/a/x/b` and `/a/b` are 404 |
| t21 | raw capture | `%2F` and `?y=1` are captured verbatim (no decoding, no query stripping) |
| t22 | composite + determinism | mixed table: 200/404/405, Allow list, repeated lookup agrees, count 4 |

Scripted expectation from the repository root:

```
& .\scripts\port.ps1 -Package xiom.router -TimeoutSec 60
# port: PASS (passed=22 failed=0 program_exit=0 exit=0)
```

## 7. Error catalog

Every message starts with the literal prefix `router: `. Messages are static
strings (no numbers are formatted into them).

| Message | Raised by | Trigger |
|---|---|---|
| `router: empty method` | `router_add` | `method.len() == 0` |
| `router: pattern must start with '/'` | `router_add` | `pattern.len() == 0` or first byte != 47 |
| `router: empty parameter name` | `router_add` | a segment is exactly `":"` (one byte) |
| `router: index out of range` | `router_method`, `router_pattern` | `i < 0` or `i >= router_count(r)` |

Validation precedence in `router_add`: empty method, then the pattern
leading-slash rule, then the scan for a bare `:` segment (left to right).
For example `router_add(r, "", ":")` reports `router: empty method`, while
`router_add(r, "GET", "a/:")` reports `router: pattern must start with '/'`.

## 8. Known limitations

- **First-match only.** No specificity, no longest-prefix preference; the
  table order is the routing policy.
- **Literal and `:name` segments only.** No `*`, regex, optional segments or
  catch-alls.
- **No decoding.** Percent-escapes and query strings stay in the captured
  value; the caller pre-processes the path.
- **No method validation.** Any non-empty byte string is a method; the table
  does not restrict the method alphabet.
- **String-only interface.** No typed parameter conversion; callers parse
  captured values themselves.
- **In-memory, O(routes) lookup per call.** No indexing, no caching.

## 9. Compiler / stdlib notes

The implementation follows the v0.63.1 package idioms:

- Free functions only; state travels by reference (`&mut Router` for
  registration, `&Router` for lookups) and lives in the public fields.
- Every byte read via `xiom.string.byte_at` is widened with
  `(x as Int) & 0xFF` before comparison (`_byte_at_i`); `'/'` and `':'`
  constants enter as 47 and 58 through the widened path.
- No `==` on `Str` anywhere: all comparisons go through
  `xiom.string.compare.str_compare`; `_contains_str` compares
  `Vec[Str]` elements after binding each to a typed local.
- Segment splits are exact `xiom.string.str_slice(p, start, end)` copies, so
  captured values are independent of the source string.
- `RouteParam` / `RouteMatch` struct literals are constructed inline, with
  the captured `Vec[RouteParam]` built locally first; `Result` values
  (`Ok`/`Err`) are constructed inline in `router_add`,
  `router_method` and `router_pattern`.
- Imports: `xiom.string` and `xiom.string.compare` only; the tests
  additionally use `xiom.test` and `xiom.io`.
- No contracts (`ensures:`/`requires:`) are declared in 0.1.0; the 22-check
  suite pins the behavior instead.
