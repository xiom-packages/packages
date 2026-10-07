# xiom.querystring -- Specification

Version: 0.1.2 (stable; published on the XIOM registry).
Module: `xiom.querystring` (`src/querystring.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free `application/x-www-form-urlencoded` codec over
in-memory `Str` values:

- parse a query string into an ordered `Query` (`qs_parse`),
- inspect it (`qs_count`, `qs_get`, `qs_get_all`, `qs_has`),
- edit it immutably (`qs_set`, `qs_remove`),
- serialize it (`qs_serialize`),
- encode/decode individual components (`qs_encode_component`,
  `qs_decode_component`).

The whole API is **error-free**: no function returns `Result`, and no input
makes a function fail. Malformed percent escapes are kept literally.

## 2. Non-goals

- Nested structures or array syntax (`a[b]=1`, `a[]=1`): names are flat bytes.
- Key collapsing or map semantics: duplicates are preserved in order.
- Configurable separators: `&` splits pairs and the first `=` splits one pair.
- The HTML 3.2 `;` pair separator.
- Percent-encoding validation: malformed escapes pass through.
- Streaming parsers, FFI, file I/O, or registry integration.

## 3. Grammar and rules

Informal grammar:

```
query   = [ "?" ] segment *( "&" segment )
segment = decoded-name [ "=" decoded-value ]     ; split at the FIRST '='
decoded = *( UTF8-byte | "+" | "%" HEX HEX )     ; "+" -> space
empty segment is skipped
```

Decisions (each one is covered by the conformance suite):

1. **Order and duplicates.** `Query` is two index-aligned `Vec[Str]`; entry i
   is `names[i]=values[i]`. Parsing preserves every pair in first-seen order;
   duplicates are kept and never merged. `qs_count` is the minimum of the two
   vector lengths, so a hand-built ragged query never over-counts.
2. **Leading `?`.** Exactly one optional `?` at byte 0 is dropped. Any other
   `?` is an ordinary byte (`a=1?b=2` is one pair with value `1?b=2`; a name
   may even start with `?`).
3. **Separators.** Pairs split on `&` only. A segment without `=` is a pair
   whose value is `""` (`flag` -> `flag=` after serialization).
4. **Empty segments.** An empty segment (between two `&`, or before/after a
   single `&`) is skipped. `""`, `"&"`, `"&&"` and `"?"` all parse to zero
   pairs.
5. **Empty names and values.** `=v`, `a=` and `=` are real pairs; empty names
   and empty values are preserved. Only empty *segments* vanish.
6. **Decoding.** `+` decodes to a space; a well-formed `%XX` (hex in either
   case) decodes to that byte. A `%` not followed by two hex digits is kept
   literally and scanning resumes at the next byte: `%`, `%2`, `%zz`, `100%`
   and `%4G1` all pass through unchanged. Decoding is byte-wise; a decoded
   byte sequence is not re-validated as UTF-8.
7. **Name matching.** Byte-exact and case-sensitive; implemented with
   `xiom.string.compare.str_compare` (BUG 17: `==` on `Str` read from
   `Vec[Str]` lowers to a pointer comparison), so `k`, `K` and `key` are
   distinct names.
8. **`qs_set`.** Returns a NEW query. The first pair whose name matches gets
   `value` in place; later duplicates are untouched. When no pair matches,
   `name=value` is appended. The source query is never mutated.
9. **`qs_remove`.** Returns a NEW query with every pair whose name matches
   removed; other pairs keep their relative order. The source is never
   mutated.
10. **Serialization.** Pairs join with `&`; each pair always renders
    `name=value`, even when the value is empty. Both sides are form-encoded:
    space -> `+`; unreserved bytes `[A-Za-z0-9-._~]` pass through; every other
    byte becomes `%XX` with **uppercase** hex digits. An empty query renders
    `""`.
11. **Round trip.** `qs_parse(qs_serialize(q))` reproduces `q` pair for pair
    for any query produced by `qs_parse`. For components, decoding canonical
    output and re-encoding is stable: `qs_encode_component(
    qs_decode_component(x)) == x` when `x` is already canonical.
12. **Encoding model.** `Str` is treated as a byte buffer. Encoding scans the
    UTF-8 bytes, so multi-byte characters emit one `%XX` per byte and
    round-trip byte-exact.

## 4. API signatures

```xi
pub type Query = {
  names: Vec[Str];
  values: Vec[Str];
}

pub fn qs_parse(text: Str) -> Query
pub fn qs_count(q: &Query) -> Int
pub fn qs_get(q: &Query, name: Str) -> Option[Str]
pub fn qs_get_all(q: &Query, name: Str) -> Vec[Str]
pub fn qs_has(q: &Query, name: Str) -> Bool
pub fn qs_set(q: &Query, name: Str, value: Str) -> Query
pub fn qs_remove(q: &Query, name: Str) -> Query
pub fn qs_serialize(q: &Query) -> Str
pub fn qs_encode_component(s: Str) -> Str
pub fn qs_decode_component(s: Str) -> Str
```

Complexity: parsing and serialization are O(text length); inspection and
edits are O(pairs); component encode/decode is O(s.len()).

## 5. Error-free API notes

There is no error type and no failure mode:

- `qs_parse("")`, `qs_parse("?")` and `qs_parse("&&&")` return an empty query.
- `qs_get` returns `Option[Str]` (`None` when absent); `qs_get_all` returns an
  empty vector when absent; `qs_has` returns `Bool`.
- `qs_decode_component` never rejects input; malformed escapes stay literal.
- `qs_encode_component` never rejects input; every byte is representable.
- `qs_set`/`qs_remove` are pure: they build and return new vectors.

## 6. Test plan

`tests/test_conformance.xi` (module `querystring_tests`) has 20 checks run by
`fn main() -> Int`; a check is `[PASS]` only when every assertion in it holds.
All Str equality goes through `str_compare`.

| Test | Covers |
|---|---|
| t1 | simple pairs kept in order and serialized |
| t2 | repeated names preserved; `get_all` returns all, in order; absent -> empty; `None` |
| t3 | segment without `=` gets value `""`; serialized as `flag=` |
| t4 | empty segments skipped; `&&` -> empty query |
| t5 | one leading `?` tolerated and dropped |
| t6 | `+` -> space; `%2B` -> `+`; both directions on components |
| t7 | mixed-case `%XX`; uppercase re-encoding of `%c3%a9` |
| t8 | malformed escapes kept literal (`%`, `%2`, `%zz`, `%4G1`, `100%`) |
| t9 | empty names and empty values preserved; duplicate empty names |
| t10 | percent-decoded names and values; canonical re-serialization |
| t11 | `qs_set` replaces only the first matching pair, in place |
| t12 | `qs_set` appends when absent; source and intermediate queries unchanged; empty query + `qs_set` |
| t13 | `qs_remove` removes all matches; no-op when absent; source intact |
| t14 | `qs_has` matches the whole name, case-sensitively |
| t15 | pinned serialization: space -> `+`, unreserved kept, uppercase `%XX` |
| t16 | empty query: zero pairs, `""`, `None` get, `has` false |
| t17 | parse -> serialize -> parse is stable on a 5-pair sample (incl. empty name/value) |
| t18 | component encode/decode round-trip for ASCII samples; `100%25`; `a+b%2Bc` |
| t19 | only the leading `?` is special; later `?` literal in value and name |
| t20 | names compare by content, not identity (`str_compare` discipline) |

## 7. v0.61.3 constraints observed

- Free functions only (no `self` methods); all scanning is byte-wise.
- No `Vec[StructType]`: `Query` uses two parallel `Vec[Str]`.
- No inline lambdas; no `Vec[fn]` test dispatch (tests are called directly).
- No `&mut` patterns in `match`.
- `Str` equality via `str_compare` with typed locals for `Vec[Str]` reads.
- Bytes widen as `(string.byte_at(s, i) as Int) & 0xFF`.
- `match` is exhaustive; `use` lines end with `;`, `module` does not.
- No `Ok`/`Err` anywhere: the API has no `Result` channel.

## Contracts (batch #19 hardening pass, 2026-10-07)

Runtime-checkable `ensures:` clauses added to `src/querystring.xi` in the
batch #19 hardening pass (compiler v0.64.0; no version bump): 23 clauses
across the 10 public entry points. Two consecutive
`.\scripts\port.ps1 -Package xiom.querystring -TimeoutSec 60` runs ended
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)` with the clauses
active (10.2 s and 10.3 s). The 20-check conformance suite exercises all 10
entry points with the clauses active; none trapped.

All clauses are `ensures:`; no `requires:` was added, so the accepted-input
domain is unchanged. Only `qs_count`'s `result >= 0` is a pure scalar
expression (`result` arithmetic only, no calls), the shape the Z3 emitter
can reason about; every other clause observes `Str`/`Vec` lengths or calls
public functions, so the v0.64.0 emitter leaves it UNKNOWN and it is
runtime-checked. `xiom-verify --check` on v0.64.0 reported **1 proven /
1 violated / 27 unknown / 8 errors**; the single reported "violation" is an
emitter artifact -- `_limit` is emitted as an unknown constant
(`unknown constant _limit (xiom_ptr_Query)`), the body assertion errors out
and the unconstrained `result` makes `not (result >= 0)` satisfiable -- the
clause is true in the code (the minimum of two non-negative vector
lengths). No real counterexample was produced.

| Entry point | Clause(s) added | Class |
|---|---|---|
| `qs_encode_component` | `ensures: s.len() == 0 => result.len() == 0` | runtime-checked |
| `qs_encode_component` | `ensures: result.len() >= s.len()`; `ensures: result.len() <= 3 * s.len()` | runtime-checked (byte-wise 1 or 3 output bytes per input byte) |
| `qs_decode_component` | `ensures: s.len() == 0 => result.len() == 0` | runtime-checked |
| `qs_decode_component` | `ensures: result.len() <= s.len()` | runtime-checked (each step consumes >= 1 and emits <= 1 byte) |
| `qs_parse` | `ensures: text.len() == 0 => qs_count(result) == 0` | runtime-checked (cross-call) |
| `qs_parse` | `ensures: qs_count(result) <= text.len()` | runtime-checked (cross-call; every pair consumes a non-empty slice) |
| `qs_count` | `ensures: result >= 0` | Z3-provable (pure scalar) |
| `qs_count` | `ensures: result <= q.names.len()`; `ensures: result <= q.values.len()` | runtime-checked (parallel-vector minimum) |
| `qs_get` | `ensures: qs_has(q, name) => result is Some`; `ensures: result is None => !qs_has(q, name)` | runtime-checked (cross-call; Option tag only, no payload read) |
| `qs_get_all` | `ensures: result.len() <= qs_count(q)`; `ensures: !qs_has(q, name) => result.len() == 0`; `ensures: q.names.len() == 0 => result.len() == 0` | runtime-checked (cross-calls on a Vec result) |
| `qs_has` | `ensures: result => qs_count(q) > 0` | runtime-checked (cross-call) |
| `qs_has` | `ensures: q.names.len() == 0 => !result` | runtime-checked |
| `qs_set` | `ensures: qs_has(q, name) => qs_count(result) == qs_count(q)` | runtime-checked (exact; `qs_set` and `qs_has` share the `_limit` scan) |
| `qs_set` | `ensures: !qs_has(q, name) => qs_count(result) == qs_count(q) + 1` | runtime-checked (exact; append path) |
| `qs_remove` | `ensures: qs_count(result) <= qs_count(q)`; `ensures: !qs_has(q, name) => qs_count(result) == qs_count(q)` | runtime-checked (exact; filter keeps every non-match) |
| `qs_serialize` | `ensures: qs_count(q) == 0 => result.len() == 0` | runtime-checked |
| `qs_serialize` | `ensures: result.len() >= 2 * qs_count(q) - 1` | runtime-checked (one '=' per pair plus count-1 '&' minimum) |

No clause uses tuple-component access, a `Result`/`Option` payload field
read, a struct payload field, or `Str` equality. Struct returns (`Query`)
are observed only through `qs_count`/`qs_has` cross-calls. The only
cross-function clause calls are `qs_count` and `qs_has`; both are terminal
over `_limit`/`str_compare` and never call the entry point they guard
against, so there is no postcondition call-cycle (transitive re-entry 0).
