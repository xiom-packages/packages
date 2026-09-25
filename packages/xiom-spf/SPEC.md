# xiom.spf -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.spf` (`src/spf.xi`). Pure XIOM, no FFI, no DNS, no evaluation,
no DNS TXT framing.

## 1. Scope

A small, dependency-free SPF codec for one in-memory record string:

- `spf_parse` -- record -> `Result[Spf, Str]`,
- `spf_emit` -- `Spf` -> canonical record text,
- accessors -- term count, kind, qualifier, value, CIDR length, modifier
  flag and `spf_find_modifier`,
- `spf_macro_valid` -- the documented macro-shape predicate.

The documented subset covers the `v=spf1` version section, the eight
mechanisms, the four qualifiers, `redirect`/`exp` and unknown `name=value`
modifiers, `%{...}` macro pass-through, and CIDR validation; see sections 3-6.

## 2. Non-goals

- No DNS lookups, no record selection, no recursion: `include`, `redirect`,
  `exp` and the DNS-querying mechanisms are parsed and stored, never
  evaluated. There is no 10-lookup limit and no result (pass/fail/neutral)
  computation.
- No DNS TXT framing: multiple character-strings, concatenation, size limits
  and the TXT record selection rules of RFC 7208 section 4 are the caller's
  responsibility; the module sees one already-concatenated `Str`.
- No address-syntax validation: `ip4`/`ip6` payloads are reserved as written
  (only the CIDR length is checked), and no address normalisation exists.
- No macro expansion: macros are shape-checked and passed through; `%{...}`
  expansion, domain-spec equivalence and the `exp` explanation text are out
  of scope.
- No dual CIDR lengths, no `exp` explain-string parsing, no DNSBL reversed
  domain handling and no vendor extensions.
- No URL/domain IDN handling beyond verbatim bytes: the record is treated as
  a byte buffer, bytes >= 0x80 pass through and no UTF-8 validation happens.
- No mutable editing API: a record is produced by `spf_parse` (or
  `spf_new`) and read through accessors.

## 3. Data model

```xi
pub type Spf = {
  kind: Vec[Str];        // mechanism canonical name or modifier name as written
  qualifier: Vec[Str];   // "+", "-", "~", "?" for mechanisms; "" for modifiers
  value: Vec[Str];       // domain-spec / address / modifier value, verbatim
  cidr: Vec[Int];        // validated CIDR length, or -1 when absent
  is_modifier: Vec[Int]; // 1 = modifier, 0 = mechanism
}
```

Invariants for a parsed record:

- all five vectors have the same length (the term count); `spf_push_term` is
  the only place that extends them;
- `kind[i]` is a canonical lowercase mechanism name (`all`, `include`, `a`,
  `mx`, `ip4`, `ip6`, `ptr`, `exists`) when `is_modifier[i] == 0`, and the
  modifier name exactly as written when `is_modifier[i] == 1`;
- `qualifier[i]` is one of `+`, `-`, `~`, `?` for mechanisms and `""` for
  modifiers;
- `cidr[i]` is -1 or in 0..32 (a/mx/ip4) or 0..128 (ip6); it is never 0..-1
  ambiguous because -1 is not a valid length;
- `value[i]` is non-empty for `include`, `exists`, `ip4` and `ip6`; it may be
  empty for `all`, `a`, `mx`, `ptr` and non-redirect/exp modifiers.

Accessors and `spf_emit` clamp to the length of the shortest vector
(`_spf_span`), so a hand-built value whose vectors disagree cannot cause an
out-of-bounds read; it is simply truncated.

`Vec[StructType]` is not usable in this compiler, so the model is deliberately
flat instead of a list of term structs.

## 4. Grammar

```
record       = ws* version ( 1*ws term )* ws*
version      = "v=spf1"                          ; ASCII case-insensitive
term         = [ qualifier ] mechanism / modifier
qualifier    = "+" / "-" / "~" / "?"
mechanism    = "all"
             / "include" ":" domain-spec
             / "a" [ ":" domain-spec ] [ "/" cidr4 ]
             / "mx" [ ":" domain-spec ] [ "/" cidr4 ]
             / "ptr" [ ":" domain-spec ]
             / "ip4" ":" address [ "/" cidr4 ]
             / "ip6" ":" address [ "/" cidr6 ]
             / "exists" ":" domain-spec
modifier     = name "=" macro-string
name         = ALPHA *( ALPHA / DIGIT / "-" / "_" / "." )
cidr4        = canonical decimal 0..32
cidr6        = canonical decimal 0..128
ws           = SP / TAB

macro-string = *( macro-expand / macro-literal )
macro-expand = "%{" macro-letter transformers *delimiter "}"
             / "%%" / "%_" / "%-"
macro-letter = "s" / "l" / "o" / "d" / "i" / "p" / "h" / "c" / "r" / "t" / "v"
transformers = *DIGIT [ "r" ]
delimiter    = "." / "-" / "+" / "," / "/" / "_" / "="
```

Mechanism names, modifier names and the version literal are recognized ASCII
case-insensitively (RFC 5234 string semantics). `domain-spec` and `address`
are any run of non-separator bytes; they are stored verbatim and only
macro-shape-checked.

## 5. Parsing decisions

Each decision is covered by the conformance suite.

1. **Separators.** Terms are separated by one or more SP or TAB bytes
   (extension over the RFC's SP). Leading and trailing separator runs are
   ignored. Empty terms cannot arise from splitting; the "empty term" error
   covers a term that is only a qualifier or has no name.
2. **Control bytes.** Input containing any C0 control byte other than SP and
   TAB (LF and CR included), or DEL (0x7F), is
   `Err("spf: control byte in input")`, checked before parsing. Bytes >= 0x80
   pass through. (`Str` is NUL-terminated on this toolchain, so a NUL byte
   cannot occur in ordinary `Str` values; the check is defensive for NUL and
   effective for the other control bytes.)
3. **Version.** The first token must be `v=spf1` ASCII case-insensitively. A
   first token starting with `v=` that differs (for example `v=spf2`,
   `v=spf10`, `v=`) is `Err("spf: wrong version: <token>")`; any other first
   token is `Err("spf: missing version")`, as is empty or whitespace-only
   input. A later `v=...` token is an ordinary modifier named `v` (see 7).
4. **Qualifiers.** `+`, `-`, `~` and `?` precede a mechanism and apply to it;
   `+` is the default and is stored explicitly. A qualifier before a modifier
   is `Err("spf: bad modifier: <term>")`. A qualifier with no term after it is
   `Err("spf: empty term: <term>")`.
5. **Names.** A term's name is the leading run of `ALPHA / DIGIT / "-" / "_"
   / "."` after any qualifier and must start with an ASCII letter. A name
   followed by nothing is a bare mechanism (`all`, `a`, `mx`, `ptr` complete;
   `include`, `ip4`, `ip6`, `exists` error); a name followed by `=` is a
   modifier; `:` and `/` introduce a value and/or CIDR; any other delimiter
   makes the term an unknown mechanism. A term starting with a digit is an
   unknown mechanism; a term whose first byte is neither a qualifier, a
   letter nor a digit (for example `:x`, `/24`, `=x`, `%{d}`) is an empty
   term.
6. **Mechanisms.** `all` takes no value and no CIDR; `a`/`mx` take an optional
   domain-spec and an optional CIDR 0..32; `ip4` takes a required address and
   an optional CIDR 0..32; `ip6` takes a required address and an optional
   CIDR 0..128; `include`/`exists` take a required domain-spec; `ptr` takes an
   optional domain-spec (documented but discouraged by RFC 7208; it is parsed
   and preserved, never evaluated). `include`, `exists` and `ptr` accept no
   CIDR, so a top-level `/` in their value is
   `Err("spf: bad mechanism syntax: <term>")`. `a:/24` is accepted and stored
   exactly like `a/24`. `ip4`/`ip6` addresses are stored verbatim, with no
   address-syntax validation.
7. **Modifiers.** `name=value` with `name` as in 5. Values are macro strings
   and may be empty for modifiers other than `redirect` and `exp`
   (`Err("spf: bad modifier: <term>")` when one of those two has an empty
   value). The name is stored as written; recognition, duplicate detection and
   `spf_find_modifier` are ASCII case-insensitive. Every modifier name may
   appear at most once: a repeat is
   `Err("spf: duplicate modifier: <name>")` (name as written in the second
   occurrence). This is stricter than RFC 7208, which only forbids a second
   `redirect`/`exp`; unknown modifiers are also single-instance here.
   Duplicate mechanisms are allowed and preserved.
8. **CIDR lengths.** Written as a canonical decimal: `0` alone, or a
   non-zero-leading run of digits, no sign, no leading zeros, value within
   0..32 for `a`/`mx`/`ip4` and 0..128 for `ip6`. Anything else (empty,
   `024`, `x`, `1.5`, `-1`, `33` for v4, `129` for v6) is
   `Err("spf: bad cidr: <term>")`. A top-level `/` inside `%{...}` is a macro
   delimiter and never splits the value.
9. **Macros.** Every `%` in a domain-spec, address or modifier value must
   start a well-formed macro: `%{...}` with one or more macro letters, then
   digits, then an optional `r`, then zero or more delimiters, then `}`; or
   one of the escapes `%%`, `%_`, `%-`. Anything else (a trailing `%`, `%x`,
   an empty or unterminated body, a non-letter body, a stray digit after the
   delimiters) is `Err("spf: bad macro: <term>")`. Macro letters are matched
   ASCII case-insensitively. Macros are otherwise passed through verbatim.
10. **Error precedence inside a term.** For `a`/`mx`/`ip4`/`ip6` the top-level
    `/` split and the CIDR value are checked first, then a required value,
    then the macro shape; for `include`/`exists`/`ptr` the value presence and
    the top-level `/` are checked before the macro shape; for modifiers the
    required value, then the macro shape, then the duplicate name. The first
    failing check wins. Errors are reported in source order across terms.
11. **Round-trip.** `spf_parse(spf_emit(r))` succeeds for every record `r`
    that `spf_parse` produced, preserving kinds, qualifiers, values, CIDR
    lengths, modifier flags and term order. `spf_emit` is idempotent:
    emitting the reparse of an emitted record yields identical text.

## 6. API contract

```xi
pub fn spf_parse(record: Str) -> Result[Spf, Str]
pub fn spf_new() -> Spf
pub fn spf_term_count(r: &Spf) -> Int
pub fn spf_term_kind(r: &Spf, i: Int) -> Str
pub fn spf_term_qualifier(r: &Spf, i: Int) -> Str
pub fn spf_term_value(r: &Spf, i: Int) -> Str
pub fn spf_term_cidr(r: &Spf, i: Int) -> Int
pub fn spf_term_is_modifier(r: &Spf, i: Int) -> Bool
pub fn spf_find_modifier(r: &Spf, name: Str) -> Int
pub fn spf_macro_valid(s: Str) -> Bool
pub fn spf_emit(r: &Spf) -> Str
```

- `spf_parse` is O(record length); `spf_macro_valid` is O(|s|);
  `spf_find_modifier` is O(term count); the accessors are O(1); `spf_emit` is
  O(total output length).
- Every accessor is total: an out-of-range index yields `""`, `-1` or
  `false` (see each doc comment). No accessor traps, including on a manually
  built `Spf` whose parallel vectors disagree.
- `spf_term_cidr` uses -1 as the absent sentinel, matching the stored
  representation; -1 is never a valid CIDR length.
- `spf_emit` writes values verbatim and assumes they contain no control byte,
  SP or TAB; that holds for every record produced by `spf_parse`.

### Canonical emitter

`spf_emit` writes:

1. `v=spf1`;
2. one space and one term per term, in order, with no trailing space:
   - mechanisms as `[qualifier]name[:value][/cidr]`, where the qualifier is
     written only when it is not `+`, the name is the canonical lowercase
     spelling, the value is written verbatim when non-empty, and the CIDR is
     written as a canonical decimal when present;
   - modifiers as `name=value` with the name and value verbatim.

An empty record emits `v=spf1`. `spf_new()` emits `v=spf1`.

## 7. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"spf: "`:

| Message | Trigger |
|---|---|
| `spf: control byte in input` | C0 control byte (not SP/TAB), LF, CR or DEL anywhere in the input |
| `spf: missing version` | empty/whitespace-only input, or a first token not starting with `v=` |
| `spf: wrong version: <token>` | a first token starting with `v=` that is not `v=spf1` |
| `spf: empty term: <term>` | a term that is only a qualifier, or whose first name byte is not a letter or digit |
| `spf: unknown mechanism: <term>` | a term whose mechanism name is not one of the eight, or that starts with a digit |
| `spf: bad mechanism syntax: <term>` | `all` with a value/CIDR; a top-level `/` in include/exists/ptr; a missing required value; a CIDR on a mechanism that takes none |
| `spf: bad cidr: <term>` | a CIDR that is empty, non-decimal, non-canonical or out of range |
| `spf: bad macro: <term>` | a `%` that does not start a well-formed macro or escape |
| `spf: duplicate modifier: <name>` | a modifier name that already appeared (case-insensitive) |
| `spf: bad modifier: <term>` | a qualifier before `=`, or an empty `redirect=`/`exp=` value |

Messages are deterministic. `<term>` is the whole term as written (including
any qualifier), `<name>` is the modifier name as written, `<token>` is the
first record token. The first failing term in source order is reported.

## 8. Test plan

`tests/test_conformance.xi` (module `spf_tests`) runs 26 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | bare record | zero terms, emits `v=spf1`, round-trips |
| t2 | `all` | default `+`, `-all`, empty value/CIDR, mechanism flag |
| t3 | mechanism catalog | all eight names, values, default qualifier |
| t4 | qualifiers | `+ - ~ ?`, canonical emit drops `+` |
| t5 | ip4/ip6 | CIDR 0..32 and 0..128, absent CIDR, verbatim addresses |
| t6 | a/mx forms | optional value, `a/24`, CIDR 0 and 32, exact emit |
| t7 | macros | pass-through verbatim, macro slash inside a CIDR term |
| t8 | redirect/exp | modifier fields, case-insensitive `spf_find_modifier` |
| t9 | unknown modifiers | preserved verbatim, `=` in values, later `v=` token |
| t10 | canonical emit | lowercase mechanisms, verbatim values, single spaces |
| t11 | round-trip | 16-term mixed record, emit idempotence |
| t12 | version | missing, wrong (`v=`, `v=spf2`, `v=spf10`), case-insensitive `V=SPF1` |
| t13 | unknown mechanism | bare, `allx`, `ipv4:`, `a!b`, digit-leading, qualifier included |
| t14 | bad mechanism syntax | `all:x`, `include`, empty values, `/` on ptr/exists/include |
| t15 | bad CIDR | out of range, empty, leading zero, non-digit, `-1`, boundary OK |
| t16 | empty term | qualifier-only and nameless (`:x`, `/24`, `=x`, `%{d}`) |
| t17 | duplicate modifier | redirect/exp/unknown names, case-insensitive |
| t18 | bad modifier | qualifier before `=`, empty `redirect=`/`exp=` |
| t19 | bad macro | trailing `%`, `%{`, `%{}`, `%{x}`, unterminated, escapes OK |
| t20 | `spf_macro_valid` | the documented predicate, positives and negatives |
| t21 | control bytes | `\u{0001}`, `\u{000B}`, DEL, LF, CR |
| t22 | separators | TAB/SP runs, trim, canonical emit |
| t23 | bounded accessors | out-of-range kind/qualifier/value/cidr/modifier |
| t24 | `spf_new` | empty record, emits `v=spf1` |
| t25 | normalisation | `a:/24` -> `a/24`, canonical kind, macro-slash |
| t26 | order/duplicates | modifiers before mechanisms, duplicate mechanisms |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); test helpers read elements only through the accessors.

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the pure-parser idioms
of `xiom.robots`/`xiom.cidr` (byte-wise scanning with `xiom.string.byte_at`,
`Vec[UInt8]` accumulation with `xiom.string.builder`) and documents these
compiler-driven choices:

- `Vec[StructType]` is unsupported, so a record is a flat set of parallel
  vectors; `_spf_push_term` is the only extension point and `_spf_span`
  clamps every reader.
- `Ok`/`Err` for `Result[Spf, Str]` are constructed only in the leaf helpers
  `_spf_ok`/`_spf_err`; the internal term parsers return `""` on success and
  the catalog message on failure.
- Str equality between values read from `Vec[Str]` elements goes through
  `xiom.string.compare` (BUG 17); element values are bound to typed locals
  before use.
- Every byte read goes through `_spf_byte`, which widens with `& 0xFF`, so no
  UInt8 value is ever compared against a >= 128 constant.
- Modifier-flag reads use `r.is_modifier[i] != 0` because `Vec[Bool]`
  element semantics are not exercised elsewhere in this harness.
- `spf_parse` owns the token loop; `spf_emit` builds the output once with
  `builder.sb_push_str` and never rewrites a trailing separator.
- Tests dispatch directly (`t1()` ... `t26()`); no `Vec[fn]` indexed calls,
  no inline lambdas, no `mut` match patterns, and every `match` is
  exhaustive.

## 10. Known limitations

- No evaluation and no DNS: the parsed record is inert data.
- `ip4`/`ip6` payloads are not validated as addresses; an invalid address is
  stored and re-emitted verbatim.
- Macro shape only: no expansion, no domain-spec equivalence, no `%{p}`
  reverse lookup.
- Unknown modifiers are single-instance here, stricter than RFC 7208, and
  `exp` explain-strings are not parsed.
- The version literal is matched ASCII case-insensitively (ABNF semantics),
  while RFC 7208's record-selection wording says "exactly `v=spf1`"; this
  package narrows that wording to lowercase when emitting.
- Comments do not exist in the syntax, so none are preserved or emitted;
  separator runs and mechanism name casing are canonicalized.
- Errors carry the whole term but no column/offset.
- `spf_emit` assumes LF/control-byte-free values; hand-built `Spf` values
  bypassing `spf_parse` are neither validated nor canonicalised.
