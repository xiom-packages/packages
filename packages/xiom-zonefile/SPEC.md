# xiom.zonefile -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.zonefile`, version `0.1.0`).
Module: `src/zonefile.xi` (`module xiom.zonefile`).
Depends on `xiom.std`; the library module imports only `xiom.string`,
`xiom.string.builder` and `xiom.string.compare` (the tests add `xiom.test`
and `xiom.io`).

## 1. Scope

A pure-XIOM (no FFI, no sockets) DNS master-file codec for the subset listed
here:

- `$ORIGIN name` and `$TTL n`, tracked while parsing and applied to the
  records that follow;
- records `[name] [ttl] [class] type rdata` with an omitted name or TTL
  inherited from the previous record;
- owner names completed against the current origin, `@` meaning the origin,
  absolute (trailing-dot) names preserved;
- parenthesized records spanning lines, `;` comments to end of line, and
  quoted tokens with `\"` and `\\` escapes;
- the types SOA, NS, A, AAAA, CNAME, MX, TXT, PTR with per-type RDATA token
  counts; RDATA kept as whitespace-separated tokens plus a joined-text form
  for TXT;
- flat record storage in one `Zone` value with parallel `Vec[Str]` /
  `Vec[Int]` fields and a shared token pool (no `Vec[StructType]`);
- accessors for record count, name, TTL, class, type, RDATA token count,
  RDATA token and TXT text;
- a canonical emitter (`zone_emit`) with one record per line and
  deterministic formatting, and a byte-stable round-trip.

Errors are deterministic `Err(Str)` strings; the full catalog is in
section 6.

## 2. Non-goals

- Socket I/O, servers, resolvers, caching, retries or wire encoding.
- DNSSEC types (RRSIG/DNSKEY/DS/NSEC/...), `$INCLUDE`, `$GENERATE` or any
  directive beyond `$ORIGIN` and `$TTL`.
- A class or type registry beyond the eight types and the single class `IN`.
- TTL time units (`1h`, `1w`): TTLs are decimal seconds only.
- RDATA interpretation: addresses, names and numbers inside RDATA are never
  parsed, validated or rewritten; only the token count is enforced.
- Name resolution of RDATA targets (an NS target or MX exchange stays
  exactly as written, relative or absolute).
- Name escape syntax (a name token cannot contain whitespace, `;`, `(` or
  `)`; backslash outside quotes is an ordinary byte).
- Quoted strings that span lines: a quote must close on the same line.
- Multiple records on one physical line: a record ends at a newline at
  parenthesis depth 0 (a `)` never starts a new record).

## 3. Grammar

Input is a sequence of bytes (the runtime `Str`, NUL-terminated, so no
`0x00` can occur). The parser makes one left-to-right pass.

```
document   = { hws | newline | comment | directive | record } ;
directive  = "$ORIGIN" hws value | "$TTL" hws digits ;
record     = owned | inherited ;
owned      = owner [ hws ttl ] [ hws class ] hws type [ hws rdata ] eol ;
inherited  = hws [ ttl ] [ hws class ] hws type [ hws rdata ] eol ;
eol        = newline | end-of-input ;
```

Terminology:

- `hws` = space (`0x20`), TAB (`0x09`) or CR (`0x0D`). LF (`0x0A`) is a
  newline, not horizontal whitespace. CRLF line endings therefore work, and
  a missing final newline is accepted.
- A **token** is a bare token or a quoted token.
  - *Bare token*: one or more bytes that are not `hws`, newline, `;`, `(`
    or `)`. A `"` is an ordinary byte inside a bare token.
  - *Quoted token*: `"` ... `"`. Inside it, `\"` decodes to `"`, `\\` to
    `\`, and any other backslash sequence is kept verbatim (backslash plus
    the next byte). A quoted token may contain spaces, `;`, `(`, `)` and
    `"` (via `\"`). The token ends at the first unescaped `"`; LF inside a
    quoted token (or a backslash at EOF) is `zonefile: unterminated quote`.
- `(` and `)` outside quotes are token separators and group a record across
  lines. Inside parentheses a newline is whitespace. A `)` at depth 0, or a
  `(` that is still open at end of input, is
  `zonefile: unbalanced parentheses`.
- `;` outside quotes starts a comment that runs to the next newline (or end
  of input); the newline itself still ends the record.
- **Owner omission.** A record whose first token is preceded by a space or
  TAB on its first line is an `inherited` record: it reuses the previous
  owner name (error `zonefile: missing name` when there is none). Because a
  comment line is skipped entirely, the indentation test looks one byte back
  from the first token of the logical record.
- **TTL position.** The first token after the owner is a TTL when it is a
  non-empty run of ASCII digits; otherwise it is tried as a class, then as
  the type. There is no sign, no decimal point and no time unit.
- **Class.** The only class token is `IN`, matched case-insensitively; an
  omitted class means `IN`. Any other token in that position is read as the
  type (so `CH` is `zonefile: bad type`).
- **Type.** One of `SOA`, `NS`, `A`, `AAAA`, `CNAME`, `MX`, `TXT`, `PTR`,
  matched case-insensitively and stored canonical-uppercase.

### 3.1 Examples

```text
; a small zone
$ORIGIN example.com
$ORIGIN sub            ; -> sub.example.com.
$TTL 300
@       IN SOA ns1 admin 2024010101 3600 600 604800 86400
www     A     192.0.2.1
        A     192.0.2.2        ; owner and TTL inherited
mail   600 MX   10 mail        ; explicit TTL becomes the inherited one
txt    TXT    "hello world" "a\"b"
```

Record 0 is `sub.example.com. 300 IN SOA ns1 admin ...`; record 1 is
`www.sub.example.com. 300 IN A 192.0.2.1`; record 4 is
`mail.sub.example.com. 600 IN MX 10 mail`.

## 4. Name resolution

Applied to owner tokens and to the `$ORIGIN` value; RDATA tokens are never
resolved.

| Token | Result |
|---|---|
| `@` | the current origin |
| ends with `.` | the token verbatim (absolute; case preserved) |
| anything else | `token + "." + origin` |

- The initial origin is the root, spelled `"."`. A relative owner before
  any `$ORIGIN` therefore becomes absolute at the root: `www` -> `www.`.
- `$ORIGIN value` resolves `value` against the *current* origin with the
  same table, so `$ORIGIN example.com` at the root yields `example.com.`
  and a later `$ORIGIN sub` yields `sub.example.com.`.
- Every stored name ends with a trailing dot, including the root `"."`.

## 5. TTL rules

- The inherited TTL starts at 0 and is set by `$TTL n` and by every record
  that carries an explicit TTL.
- A record without an explicit TTL uses the inherited TTL. A record with an
  explicit TTL uses it and updates the inherited TTL for the records that
  follow.
- `$TTL` accepts exactly one value token of ASCII digits; leading zeros are
  preserved in meaning only (the stored value is numeric).
- Valid TTL range: `0 .. 4294967295`. A record TTL token that is all digits
  but exceeds the range is `zonefile: bad TTL`; a `$TTL` value that is not
  all digits or exceeds the range is `zonefile: bad $TTL`.

## 6. Types and RDATA token counts

| Type | RDATA tokens | Meaning (not validated) |
|---|---|---|
| `SOA` | exactly 7 | mname, rname, serial, refresh, retry, expire, minimum |
| `NS` | exactly 1 | target |
| `A` | exactly 1 | IPv4 address text |
| `AAAA` | exactly 1 | IPv6 address text |
| `CNAME` | exactly 1 | target |
| `MX` | exactly 2 | preference, exchange |
| `TXT` | one or more | character-strings; joined with single spaces |
| `PTR` | exactly 1 | target |

Zero RDATA tokens is `zonefile: missing rdata` for every type (it is
checked before the per-type count); any other wrong count is
`zonefile: bad token count`.

`zone_txt_text` is the record's tokens joined with a single space. It makes
`"hello world"` (one token containing a space) and `hello world` (two
tokens) both read as `hello world`; `zone_rdata_token_count` and
`zone_rdata_token` keep the two cases distinct.

## 7. API signatures

All functions are free functions in module `xiom.zonefile` (no methods):

```xi
pub type Zone = {
  names: Vec[Str];
  ttls: Vec[Int];
  classes: Vec[Str];
  types: Vec[Str];
  token_starts: Vec[Int];
  token_counts: Vec[Int];
  tokens: Vec[Str];
  texts: Vec[Str];
}

pub fn zone_parse(text: Str) -> Result[Zone, Str]

pub fn zone_record_count(z: &Zone) -> Int
pub fn zone_name(z: &Zone, i: Int) -> Str
pub fn zone_ttl(z: &Zone, i: Int) -> Int
pub fn zone_class(z: &Zone, i: Int) -> Str
pub fn zone_type(z: &Zone, i: Int) -> Str
pub fn zone_rdata_token_count(z: &Zone, i: Int) -> Int
pub fn zone_rdata_token(z: &Zone, i: Int, j: Int) -> Str
pub fn zone_txt_text(z: &Zone, i: Int) -> Str

pub fn zone_emit(z: &Zone) -> Str
```

`names`, `ttls`, `classes`, `types`, `token_starts`, `token_counts` and
`texts` are index-aligned per record: record `i` uses `names[i]`,
`ttls[i]`, `classes[i]`, `types[i]`, `texts[i]` and the slice
`tokens[token_starts[i] .. token_starts[i] + token_counts[i]]`.
`Zone` is the only exported type; everything else is a free function.

## 8. Semantics

`zone_parse(text)`
: One pass over `text`. Returns `Ok(Zone)` for any document in the subset,
  including an empty document and one with only blank/comment lines, and
  the first failure otherwise (check order in section 9). Directives and
  comments are not stored; names are resolved and TTLs are effective.
  Each record contributes one row to the aligned vectors, and every push
  happens in `_zf_push_record`, so the vectors cannot drift.

`zone_record_count(z)`
: The smallest length of the seven aligned vectors, so a hand-built
  corrupted `Zone` reports fewer records instead of driving out-of-range
  reads. `O(1)`.

`zone_name(z, i)`
: `""` when `i < 0` or `i >= zone_record_count(z)`; otherwise the resolved
  absolute owner name (always trailing-dot). `O(1)`.

`zone_ttl(z, i)`
: `-1` out of range; otherwise `0..4294967295` (0 is a real value).
  `O(1)`.

`zone_class(z, i)` / `zone_type(z, i)`
: `""` out of range; otherwise `"IN"` / the canonical uppercase type.
  `O(1)`.

`zone_rdata_token_count(z, i)`
: `0` out of range or for a negative start; otherwise the record's token
  count clamped so `start + count <= tokens.len()` (a corrupted document
  cannot read past the pool). `O(1)`.

`zone_rdata_token(z, i, j)`
: `""` when `j < 0` or `j >= zone_rdata_token_count(z, i)`; otherwise the
  token verbatim, i.e. after unquoting and the documented `\"`/`\\`
  decoding. An out-of-range token and a real empty TXT token both read
  `""`; use `zone_rdata_token_count` to tell them apart. `O(1)`.

`zone_txt_text(z, i)`
: The record's tokens joined with single spaces for a TXT record, `""` for
  every other type and for out-of-range `i`. `O(1)` (precomputed at parse
  time).

`zone_emit(z)`
: See section 10. `O(total output length)`.

## 9. Error string catalog

All error strings are stable API and start with `zonefile: `.

| Error text | Condition |
|---|---|
| `zonefile: unterminated quote` | a quoted token has no closing `"` before LF or EOF |
| `zonefile: unbalanced parentheses` | `)` at depth 0, or `(` still open at EOF |
| `zonefile: unknown directive` | first token starts with `$` and is not `$ORIGIN`/`$TTL` |
| `zonefile: $ORIGIN without value` | `$ORIGIN` with no value token |
| `zonefile: bad $ORIGIN` | `$ORIGIN` with more than one value token |
| `zonefile: $TTL without value` | `$TTL` with no value token |
| `zonefile: bad $TTL` | `$TTL` value not all digits, above 4294967295, or extra tokens |
| `zonefile: missing name` | indented record before any owner name was set |
| `zonefile: bad TTL` | record TTL all digits but above 4294967295 |
| `zonefile: bad type` | no type token, or the token is outside the eight documented types |
| `zonefile: missing rdata` | record has zero RDATA tokens |
| `zonefile: bad token count` | RDATA token count differs from the per-type count (section 6) |

**Check order.** Scanning comes first: while a logical record is scanned, an
unterminated quote or an unbalanced parenthesis is reported before any
field is interpreted. For a directive, the value count and value are
checked in that order. For a record, the checks run: owner name (missing
name), TTL (bad TTL), type (bad type), RDATA presence (missing rdata), then
the per-type token count (bad token count). The first failure in document
order wins.

## 10. Canonical emitter

`zone_emit(z)` writes one line per record, in record order:

```
name SP ttl SP class SP type [ SP token ]... LF
```

- `name` is the stored resolved absolute name (trailing dot).
- `ttl` is the effective decimal TTL (`sb_push_int` formatting).
- `class` and `type` are the stored canonical spellings (`IN`, uppercase
  type).
- Each RDATA token is rendered by the canonical quoting rule: a token that
  is empty or contains horizontal whitespace, LF, `;`, `(`, `)`, `"` or
  `\` is written as a quoted string where `"` and `\` are escaped as `\"`
  and `\\`; every other token is written verbatim.
- Every line, including the last, ends with LF; an empty document emits
  `""`.
- Directives, comments, original whitespace, parentheses and the case of
  type tokens are not preserved.

**Round-trip.** For any text `x` in the documented subset,
`zone_emit(parse(x))` is a fixed point: parsing it yields a document whose
counts, names, TTLs, classes, types, tokens and TXT texts all equal the
first parse, and emitting that document reproduces the same text byte for
byte.

## 11. Complexity

| Operation | Complexity |
|---|---|
| `zone_parse` | O(text length) |
| accessors | O(1) |
| `zone_emit` | O(total output length) |

No allocation happens on an error path; every successful parse copies its
tokens into fresh values.

## 12. Test plan

`tests/test_conformance.xi` (`module zonefile_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. SOA zone: `$ORIGIN`, `$TTL`, `@`, relative owner, class, TTL and the
   seven SOA tokens pinned through the accessors;
2. `$ORIGIN` chaining (`example.com` then `sub`), `@`, absolute names
   preserved, MX tokens verbatim;
3. omitted owner and TTL inheritance (explicit TTL updates the inherited
   value; class-only and type-only continuation lines);
4. class defaulting to `IN`, explicit `in`, case-insensitive types, owner
   case preserved;
5. parenthesized SOA spanning lines with comments between tokens;
6. quoted TXT strings: `"hello world"`, `\"` -> `"`, `\\` -> `\`;
7. TXT multi-token joined text, empty token, `;` inside quotes;
8. comments: whole-line, trailing, `;` inside a quoted string;
9. `zonefile: missing rdata` for A, TXT and a comment-terminated record;
10. `zonefile: bad type` for an unknown type, a missing type, a class-only
    line, SRV and the CH class;
11. `zonefile: unbalanced parentheses` (open at EOF, `)` at depth 0, stray
    `)`), plus balanced parentheses on one line;
12. `zonefile: bad token count` for MX, A, NS, short and long SOA; TXT
    accepts any non-zero count;
13. `zonefile: unterminated quote` for LF, EOF, an embedded newline and a
    trailing backslash;
14. directives: `$ORIGIN`/`$TTL` without value, bad `$ORIGIN`, bad `$TTL`
    (non-digit and 4294967296), `$INCLUDE` unknown, trailing comment;
15. bad TTL (4294967296), missing name (indented first record), TTL 0 and
    TTL 4294967295 accepted;
16. canonical emitter pinned (resolved names, effective TTLs, uppercase
    types, canonical quoting of TXT tokens, `""` for an empty token, empty
    document emits `""`);
17. round-trip: `emit(parse(x))` is a fixed point and preserves every
    accessor of every record (directives, comments, parens, escapes);
18. accessors clamp out-of-range indexes (`""`, `-1`, `0`) and an empty
    document has zero records and emits `""`;
19. all eight documented types parse with their token counts, names and
    spot-checked tokens;
20. root origin, numeric owner name (`123` -> `123.`), CRLF line endings,
    blank lines and comment-only lines.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.zonefile
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## 13. Known limitations

- **Subset codec.** No transport, resolver or server behavior; no DNSSEC
  types, no `$INCLUDE`/`$GENERATE`, no class other than `IN`, no TTL time
  units and no type/class registry.
- **RDATA is opaque.** Token counts are enforced, but nothing inside the
  RDATA is validated: `999.999.999.999` is a fine A token.
- **Owner names only are resolved.** NS/CNAME/PTR targets, MX exchanges and
  SOA mname/rname stay byte-for-byte as written, even when relative.
- **No name escapes.** A name token cannot contain whitespace, `;`, `(`
  or `)`; a quoted owner name is accepted by the scanner but is outside the
  documented subset.
- **Quotes do not span lines.** A quoted token must close on its own line;
  the RFC's line-continuation inside quotes is not supported.
- **One record per logical line.** Parentheses group a record across lines,
  but two records cannot share a physical line and `)` does not terminate
  a record before the newline.
- **Directives are not retained.** `Zone` does not expose the final
  `$ORIGIN`/`$TTL`, comments or source line numbers.
- **`Str` is a NUL-terminated C string.** A zone file cannot contain a
  `0x00` byte; tokens are otherwise byte-transparent.
- **Error strings, not codes.** All failures are `Err(Str)` with the stable
  catalog of section 9.
- Not thread-safe; `Zone` is a plain value with `Vec` fields.

## 14. Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_zf_ok`, `_zf_err`); constructing `Result` values directly inside
  larger functions miscompiles in this compiler.
- Every byte read from a `Str` goes through `_zf_byte_at` and is widened
  with `(byte_at(s, i) as Int) & 0xFF` before it enters `Int` comparisons
  or arithmetic; `UInt8` constants are built from masked `Int` values.
- No `==`/`!=` on `Str` values: equality goes through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a `Str` read from a
  `Vec[Str]` element lowers to a pointer comparison), and every `Vec[Str]`
  element is bound to a typed local first.
- The document is flat (parallel `Vec[Str]`/`Vec[Int]` fields plus one
  shared token pool) because `Vec[StructType]` is unsupported; every push
  on the aligned vectors happens in `_zf_push_record`, and the accessors
  and emitter clamp against mismatched lengths.
- Token scanning returns negative status codes instead of a `Result`, so
  no `Result` is ever constructed outside the leaf helpers; quotes,
  parentheses and comments are scanned by hand in one pass.
- Strings are assembled with `xiom.string.builder` (`sb_new`,
  `sb_push_byte`, `sb_push_str`, `sb_push_int`, `sb_to_str`); the emitted
  TTL uses `sb_push_int`.
- The package declares no `extern "C"` blocks (no FFI).
