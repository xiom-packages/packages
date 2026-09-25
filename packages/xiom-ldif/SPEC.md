# xiom.ldif -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.ldif` (`src/ldif.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free LDIF (RFC 2849) content-entry codec for in-memory
`Str` documents:

- `ldif_parse` -- document -> `Result[Ldif, Str]`,
- `ldif_entry_count`, `ldif_entry_attr_count`, `ldif_dn` -- entry shape,
- `ldif_attr_name` / `ldif_attr_value` / `ldif_attr_bytes` /
  `ldif_attr_kind` / `ldif_attr_is_url` -- per-attribute access,
- `ldif_first_value` -- first value of a name in an entry,
- `ldif_kind_label`, `LDIF_KIND_PLAIN` / `_BASE64` / `_URL` -- value kinds,
- `ldif_emit` -- `Ldif` -> canonical LDIF text.

Non-goals (deliberately out of scope): LDAP schema semantics (DNs are opaque
strings, attribute names are not resolved, options are not interpreted), URL
fetching, change/modify records (`changetype` is rejected), streaming, file
I/O, and any normalization beyond the documented canonical emit form.

## 2. Data model

```xi
pub type Ldif = {
  entry_start: Vec[Int];  // first attribute of each entry
  entry_count: Vec[Int];  // attribute count of each entry
  names: Vec[Str];        // attribute descriptions, document order
  kinds: Vec[Int];        // LDIF_KIND_PLAIN / _BASE64 / _URL per attribute
  text: Vec[Str];         // value text as written (plain, base64 or URL)
  pool: Vec[UInt8];       // decoded bytes of every base64 value, concatenated
  pool_start: Vec[Int];   // start of the attribute's decoded bytes in pool
  pool_len: Vec[Int];     // decoded byte length (0 for plain and URL values)
}
```

Invariants produced by `ldif_parse`: `entry_start.len() ==
entry_count.len()`; the five attribute vectors are index-aligned and have the
same length; entry e owns the contiguous attribute range
`[entry_start[e], entry_start[e] + entry_count[e])`, `entry_count[e] >= 1`
and attribute 0 of every entry is its `dn`; for a base64 attribute
`pool_len[i] > 0` and the decoded bytes are `pool[pool_start[i] ..
pool_start[i] + pool_len[i])`, while plain and URL attributes have
`pool_len[i] == 0` and their text in `text[i]`. A byte pool is used because
base64 payloads are binary and may contain NUL, which a `Str` cannot carry.

`Vec[StructType]` is not usable in this compiler, so the file is deliberately
flat (parallel homogeneous vectors plus entry ranges) instead of a list of
entry structs. Every accessor clamps its indices and the spans it uses, so a
drifted or hand-built `Ldif` can never read out of bounds.

## 3. Physical lines, folding, records

```
document   = *( blank / comment / entry )
blank      = *( SP / TAB ) LF                 ; empty line included
comment    = "#" *( byte except LF )
entry      = dn-line 1*( attr-line )
attr-line  = name value-spec
```

Decisions (each is covered by the conformance suite):

1. **Line endings.** A physical line ends at LF (`\n`) or CRLF (`\r\n`); one
   trailing CR is removed, so CRLF input parses identically to LF. A final
   line without a terminator is still a line and a trailing terminator does
   not produce an extra empty line. A lone CR is a control-byte error (see
   section 5). A UTF-8 BOM is not stripped.
2. **Blank lines.** A physical line is blank when it is empty or every byte
   is SP or TAB. Blank lines are record separators: a run of them collapses
   and each entry is a maximal run of non-blank logical lines.
3. **Folding.** A physical line whose first byte is SP and which is not blank
   is a continuation: the first SP byte is removed and the remaining bytes
   are appended to the current logical line with no other trimming (so
   `"  x"` appends `" x"`). A continuation with no current logical line --
   at the start of the input or immediately after a blank line -- is
   `Err("ldif: continuation without previous line")`.
4. **Comments.** A physical line whose first byte is `#` is a comment and is
   ignored everywhere: it is never folded, never ends a record, and a
   continuation after it still attaches to the last non-blank logical line.
   Comments must start at byte 0; an indented `#` line starts with SP and is
   therefore a continuation, not a comment. Comments are not preserved by
   `ldif_emit`.
5. **dn policy.** Every entry must contain exactly one attribute whose
   description is `dn` (ASCII case-insensitive) and it must be the entry's
   first attribute. Otherwise the document is rejected (section 5).
   `ldif_dn` therefore returns the first attribute's value for any parsed
   entry.
6. **changetype.** An attribute description equal to `changetype`
   (case-insensitive) is rejected: change/modify records are a non-goal
   rather than being passed through. This is pinned by the conformance
   suite.
7. **Duplicate dn.** A second `dn` attribute in one entry is rejected (no
   last-wins merge). This is the pinned duplicate-dn policy.

## 4. Attribute lines and value forms

```
attr-line  = name value-spec
value-spec = ":" FILL plain / "::" FILL base64 / ":<" FILL url
name       = ALPHA *( ALPHA / DIGIT / HYPHEN )
             *( ";" 1*( ALPHA / DIGIT / HYPHEN ) )
FILL       = *( SP )
```

1. **Names.** The description ends at the first `:` and must match the
   grammar above: a leading letter, then letters/digits/hyphens, then any
   number of `;option` segments whose first character is not `;`. The name is
   stored exactly as written (case and options preserved); `dn` and
   `changetype` detection and `ldif_first_value` matching are ASCII
   case-insensitive because LDAP attribute descriptions are.
2. **Plain.** `name: value`. All SP bytes directly after the `:` are FILL and
   are not part of the value; everything else to the end of the line is the
   value verbatim, including trailing SP/TAB. `name:` with nothing after the
   colon is a legal empty value. A value that itself starts with SP cannot be
   expressed (the FILL run would absorb it).
3. **Base64.** `name:: base64`. All SP after `::` are FILL. The payload must
   be strict base64: a positive multiple of 4 bytes over the alphabet
   `A-Z a-z 0-9 + /`, with `=` only as the final one or two padding
   characters of the last quad. Whitespace is not allowed inside the payload
   (folds are removed before decoding, so a folded base64 value decodes
   normally). The unused low bits of a padded final byte are not checked.
   The decoded bytes are the value; `ldif_attr_bytes` returns them
   binary-exact and `ldif_attr_value` returns them as text up to the first
   NUL byte (see section 10).
4. **URL.** `name:< url`. All SP after `:<` are FILL; the rest of the line is
   the URL token, preserved verbatim and never fetched, parsed or validated.
   An empty URL is allowed. A plain value whose first byte is `<` is not
   affected: the URL marker requires the `<` immediately after the first `:`
   (`name: <x` is a plain value `"<x"`).
5. **Control bytes.** Anywhere in the input, C0 control bytes (0x00-0x1F)
   other than TAB and LF are rejected, and CR is accepted only immediately
   before LF. Values may therefore contain TAB and every byte >= 0x20
   (non-ASCII UTF-8 passes through byte-exact).

## 5. Error catalog and precedence

All failures are `Err(msg)` with a message starting with `"ldif: "`; there is
no partial result and no line/column number (the offending line text is
included where useful).

| Message | Trigger |
|---|---|
| `ldif: control byte 0xNN in input` | first C0 byte other than TAB/LF, or a CR not followed by LF |
| `ldif: continuation without previous line` | a fold at input start or right after a blank line |
| `ldif: line without colon: <line>` | a non-blank logical line with no `:` |
| `ldif: malformed attribute name in line: <line>` | empty name, bad first character, space, or empty/trailing option (`1abc`, `bad name`, `bad;`, `bad;;b`, `: x`) |
| `ldif: changetype records are not supported in line: <line>` | attribute description `changetype` (case-insensitive) |
| `ldif: missing dn in entry` | an entry whose attributes contain no `dn` |
| `ldif: duplicate dn in entry` | two or more `dn` attributes in one entry |
| `ldif: attribute before dn: <line>` | a `dn` present but not as the entry's first attribute |
| `ldif: bad base64 in value: <line>` | empty payload, length not a multiple of 4, non-alphabet byte, or misplaced `=` |

Precedence: the control-byte scan is global and first; unfolding follows; then
each record is checked in two passes -- pass 1 reports line-without-colon,
malformed-name and changetype errors in document order, then applies the dn
policy (missing, duplicate, attribute-before-dn, in that order); pass 2
reports bad base64 in document order.

## 6. Emitter

`ldif_emit` writes the canonical form:

- every entry in document order, every attribute in stored order, names
  verbatim, with LF line endings;
- exactly one blank line between two entries and no trailing LF; an empty
  document emits `""`;
- plain values as `name: value`, URL values as `name:< url` (one SP after the
  marker), both verbatim;
- base64 values re-encoded canonically from the decoded pool bytes, with
  `=`-padding, as `name:: <base64>`; the first line carries up to 76 base64
  characters after the prefix, every continuation line starts with exactly
  one SP and carries up to 76 more;
- unknown kind values are written as plain values.

Round-trip guarantee: for any `Ldif` produced by `ldif_parse`,
`parse(emit(l))` has the same entry count, per-entry attribute count,
attribute names, kinds, text values and decoded bytes as `l`, and
`emit(parse(emit(l))) == emit(l)`. Because base64 is re-encoded, a
non-canonical but accepted payload (non-zero pad bits) is normalized on the
first emit.

## 7. API signatures

```xi
pub const LDIF_KIND_PLAIN: Int = 0
pub const LDIF_KIND_BASE64: Int = 1
pub const LDIF_KIND_URL: Int = 2

pub fn ldif_parse(text: Str) -> Result[Ldif, Str]
pub fn ldif_entry_count(l: &Ldif) -> Int
pub fn ldif_entry_attr_count(l: &Ldif, e: Int) -> Int
pub fn ldif_dn(l: &Ldif, e: Int) -> Str
pub fn ldif_attr_name(l: &Ldif, e: Int, i: Int) -> Str
pub fn ldif_attr_value(l: &Ldif, e: Int, i: Int) -> Str
pub fn ldif_attr_bytes(l: &Ldif, e: Int, i: Int) -> Vec[UInt8]
pub fn ldif_attr_kind(l: &Ldif, e: Int, i: Int) -> Int
pub fn ldif_attr_is_url(l: &Ldif, e: Int, i: Int) -> Bool
pub fn ldif_first_value(l: &Ldif, e: Int, name: Str) -> Option[Str]
pub fn ldif_kind_label(kind: Int) -> Str
pub fn ldif_emit(l: &Ldif) -> Str
```

Accessors are total: an out-of-range entry/attribute yields `""`, `0`,
`LDIF_KIND_PLAIN`, `false`, `None` or an empty vector respectively.

Complexity: `ldif_parse` is O(total input length) -- every byte is visited a
constant number of times and base64 decoding is linear in the payload;
`ldif_emit` is O(total output length); `ldif_first_value` is O(attributes in
the entry); every other accessor is O(1).

## 8. Test plan

`tests/test_conformance.xi` (module `ldif_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | one entry | dn first, plain names/values, kind, not-URL |
| t2 | record separators | blank runs split entries, per-entry isolation, `dn` lookup |
| t3 | folding | plain and repeated folds append after one SP |
| t4 | base64 | decode in place including `dn::`, kind, bytes, label |
| t5 | base64 shapes | `YQ==`/`YWI=`, folded payload |
| t6 | URL form | raw token, predicate, `<` plain distinction |
| t7 | comments | skipped everywhere, fold across a comment |
| t8 | CRLF | identical parse to LF |
| t9 | empty input | empty and blank/comment-only documents |
| t10 | missing dn | Err |
| t11 | attribute before dn | Err, dn must be first |
| t12 | duplicate dn | Err, case-insensitive repeat |
| t13 | line without colon | Err |
| t14 | malformed names | `1abc`, `bad;`, `bad;;b`, empty; `a;lang-en` accepted |
| t15 | bad base64 | length, alphabet, misplaced padding, empty |
| t16 | control bytes | 0x01/0x0b/0x0d rejected, TAB kept |
| t17 | changetype | rejected, case-insensitive |
| t18 | stray fold | fold at start / after blank is Err; SP-only line is blank |
| t19 | round trip | parse -> emit -> parse preserves entries, values, kinds, binary bytes; idempotent emit |
| t20 | canonical wrap | exact emit text, 76-char base64 lines with leading-space continuation |
| t21 | case-insensitivity | `DN`/`CN`, `first_value` matching, first of repeats |
| t22 | totality | empty/TAB/trailing-space values, out-of-range accessors, kind labels |

All `Str` comparisons go through `xiom.string.compare`'s `str_compare`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Binary expectations avoid NUL string literals (the
compiler truncates a literal at NUL), so `{0x00, 0x01}` is checked
numerically.

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.ini` / `xiom.properties` / `xiom.systemd` (byte-wise scanning
with `xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the file is parallel homogeneous
  vectors plus entry ranges (no `Vec[LdifEntry]`).
- `Ok`/`Err` for `Result[Ldif, Str]`, `Result[Int, Str]` and
  `Result[Vec[UInt8], Str]` are constructed only in the leaf helpers
  `_ok_ldif`/`_err_ldif`, `_ok_rec`/`_err_rec` and `_ok_bytes`/`_err_bytes`.
- Every byte read is widened with `(x as Int) & 0xFF`; `Str` equality goes
  through `xiom.string.compare` and `Vec` elements are read into typed locals.
- Base64 grouping uses multiplication, division and modulo only; no bitwise
  shifts are used (they miscompile on values with the high bit set).
- `sb_to_str` is never called on decoded payloads (`Str` is NUL-terminated);
  binary access is `ldif_attr_bytes`.
- Tests dispatch directly (`t1()` ... `t22()`); no `Vec[fn]`, no lambdas, no
  `mut` match patterns and every `match` is exhaustive.

## 10. Known limitations

- No change/modify records: `changetype` is rejected, not passed through.
- No LDAP semantics: DNs are opaque (no parsing/validation/normalization),
  attribute names and options are not resolved, no schema checking.
- URL values are raw tokens: never fetched, validated or canonicalized.
- No lone-CR line endings (control-byte error); a UTF-8 BOM is not stripped
  and makes the first line malformed.
- Leading SP of a plain/URL value cannot be represented (FILL absorbs it);
  base64 is the way to carry whitespace-sensitive or binary payloads.
- `ldif_attr_value` reads a decoded base64 payload as text and truncates at
  the first NUL; `ldif_attr_bytes` is the binary-safe accessor.
- Comments are not preserved on emit and base64 is re-encoded canonically.
- No file I/O, no streaming and no error positions (the offending line text
  is included instead).
