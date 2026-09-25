# xiom.systemd -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.systemd` (`src/systemd.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

A small, dependency-free systemd unit-file parser and emitter for in-memory
`Str` documents:

- `unit_parse` -- document -> `Result[Unit, Str]`,
- `unit_section_count` / `unit_key_count` -- size,
- `unit_section_index` / `unit_section_name` -- section identity and order,
- `unit_section_key_count` / `unit_section_keys` -- per-section entry access,
- `unit_section_value_at` / `unit_key_at` / `unit_value_at` -- positional
  access into the flat storage,
- `unit_get` / `unit_get_last` -- value lookup by section + key,
- `unit_emit` -- `Unit` -> canonical unit text.

The byte-level rules follow the documented systemd unit-file subset: sections,
`Key=Value` assignments, `#`/`;` full-line comments, backslash continuations,
blank lines and CRLF. See sections 4-5 for the exact decisions.

## 2. Non-goals

- No directive semantics: `ExecStart=`, `After=`, `Environment=` and every
  other key are opaque byte runs. No boolean/int/list parsing, no `reset`
  semantics for empty assignments, no unit-type validation.
- No drop-in directories, no `*.d` scanning, no merge priority, no
  `systemctl` or D-Bus integration.
- No specifier expansion (`%i`, `%n`, `%H`, `${VAR}` are literal data).
- No process management, no file I/O, no streaming: one in-memory `Str` in,
  one in-memory `Str` out.
- No quoted, escaped or multi-line directive semantics beyond the single
  trailing-backslash join.

## 3. Data model

```xi
pub type Unit = {
  sections: Vec[Str];    // distinct section names, first-seen order
  sec_starts: Vec[Int];  // start index of each section's range in keys/values
  sec_counts: Vec[Int];  // length of each section's range
  keys: Vec[Str];        // every entry key, flat storage order
  values: Vec[Str];      // entry values, index-aligned with keys
}
```

Invariants for every `Unit` produced by `unit_parse`:

- `sections.len() == sec_starts.len() == sec_counts.len()`;
- `keys.len() == values.len() == sum(sec_counts)`;
- the section ranges partition `[0, keys.len())` in section order:
  `sec_starts[i] + sec_counts[i] <= sec_starts[i + 1]`;
- `sections` is duplicate-free and in first-seen (document) order;
- the entries inside each section range are in document order, duplicates
  included;
- duplicate keys are preserved, never merged: `unit_get` returns the first
  assignment, `unit_get_last` the last.

`Vec[StructType]` is not usable in this compiler, so the model is deliberately
flat: section metadata lives in the range vectors and entries live in two
parallel vectors. A repeated section header reopens the section and its new
entries are inserted at the end of that section's range, shifting later
entries right, so the range stays contiguous while the flat order of entries
across sections may change (per-section order never does).

## 4. Line grammar

```
document   = *( physical )                      ; LF or CRLF terminated
physical   = *( byte except LF )                ; one trailing CR removed
logical    = physical *( "\" physical )         ; a trailing "\" joins the next
                                                  physical line; the marker is
                                                  removed, no separator inserted
line       = ws* ( header / pair / comment / blank )
header     = "[" name "]" ws*
name       = 1*( ALPHA / DIGIT / "_" / "." / "-" )
pair       = key ws* "=" ws* value
key        = 1*( byte except "=", SP, TAB, LF, CR )
value      = *( byte except LF, CR )
comment    = ( "#" / ";" ) *( byte except LF )  ; full line only
ws         = SP | TAB
ALPHA      = "A".."Z" / "a".."z"
DIGIT      = "0".."9"
```

## 5. Decisions (each is covered by the conformance suite)

1. **Lines.** LF terminates a physical line; one trailing CR is removed, so
   CRLF input parses identically to LF input. A final physical line without a
   newline is still a line. The empty text has no lines.
2. **Continuation.** A physical line whose last byte is `\` is joined with the
   immediately following physical line: the `\` is removed and the next
   physical line is appended with **no separator inserted** (neither a space
   nor an LF). This applies to every physical line, so a header, a comment or
   a value may be continued. Continued physical lines are concatenated in
   order. A trailing `\` on the final physical line has no following line and
   is `Err("systemd: continuation at end of input: ...")`; a following blank
   line is a real following line and completes the join. `\\` at the end of a
   physical line leaves one literal `\` and still continues, so a parsed value
   never ends with `\`.
3. **Classification.** The logical line is scanned after skipping leading
   SP/TAB. An empty remainder is blank and skipped. A first byte of `#` or `;`
   makes the whole logical line a comment and it is skipped. A first byte of
   `[` starts a section header; every other non-blank line is a pair.
4. **Comments are full-line only.** `#` and `;` start a comment only as the
   first non-whitespace byte of the logical line. Anywhere else they are
   ordinary data: `ExecStart=/bin/echo # not a comment` keeps the whole text
   as the value. Comments are parsed and dropped; emit never writes them.
5. **Section headers.** `[` + name + `]`, optionally followed by SP/TAB. The
   name must be non-empty and contain only `A-Z a-z 0-9 _ . -`. `[]` is
   `Err("systemd: empty section name: ...")`; a missing `]`, junk after `]` or
   a byte outside the name set is `Err("systemd: malformed section header:
   ...")`. There is no trimming inside the brackets, so `[  ]` is malformed,
   not empty. `[Unit]  ` (trailing blanks) is accepted. A header switches the
   current section; a name that was already seen reopens that section.
6. **Pairs.** A pair is split at the first `=`. The key is the text before it
   with trailing SP/TAB removed; it must be non-empty and contain no SP/TAB
   (`Key name=v` is `Err("systemd: malformed key in line: ...")`, `=v` is
   `Err("systemd: empty key in line: ...")`). The value is the text after the
   first `=` with leading SP/TAB removed; it may be empty and its trailing
   whitespace is kept. `Key=`, `Key=   ` and `Key=v` are all valid. A
   non-blank, non-comment line with no `=` is
   `Err("systemd: line without '=': ...")`.
7. **Keys are case-sensitive.** Section names and keys are compared
   byte-exactly: `[Unit]` is not `[unit]` and `Description` is not
   `description`. There is no case folding anywhere.
8. **No section before the first key.** A pair before the first header is
   `Err("systemd: key before any section: ...")`. Blank lines and comments may
   precede the first header.
9. **Duplicates.** A repeated key is not an error and is not merged: each
   assignment appends another entry to the current section, in document order.
   `unit_get` returns the first value, `unit_get_last` the last.
10. **Reopened sections.** A repeated header does not create a second section:
    the entries after it append to the existing section's range, and the
    section keeps its first-seen position in `sections`.
11. **Control bytes.** Every byte < 0x20 other than TAB (0x09) and LF (0x0A)
    is rejected with `Err("systemd: control byte 0xNN in input")`, where `NN`
    is two lowercase hex digits. CR (0x0D) is allowed only immediately before
    LF; a lone CR is reported the same way. NUL cannot be represented in an
    XIOM `Str` (the literal/runtime representation is NUL-terminated), so in
    practice the rejected set is 0x01-0x08, 0x0B, 0x0C, 0x0E-0x1F; the check
    still covers 0x00 if it could occur.
12. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning is
    byte-wise; only ASCII bytes are special, so non-ASCII keys, values and
    section names pass through byte-exact. No byte sequence is ever split or
    rewritten.
13. **Emission.** For every section in order: `[Name]`, then one line per
    entry `Key=Value`, each line followed by LF except that no trailing LF is
    written after the document. Exactly one blank line separates two sections.
    An empty document (no sections) emits `""`. Keys, values and section names
    are written verbatim; comments and continuation markers are not
    reconstructed.
14. **Round trip.** For any `Unit` produced by `unit_parse`,
    `unit_parse(unit_emit(u))` reproduces the same section order, section
    entry ranges and key/value sequences, and `unit_emit` is idempotent
    (`emit(parse(emit(u))) == emit(u)`). This holds because parsed values
    never begin with SP/TAB (trimmed), never contain LF or CR (line
    structure), never end with `\` (continuation), and parsed names/keys
    satisfy the grammar.
15. **Totality of the read API.** Accessors and `unit_emit` never panic on a
    hand-built `Unit`: out-of-range indices return `None` / `-1` / an empty
    vector, and a range whose metadata is missing or longer than the flat
    vectors is clamped. Clamping does not repair a drifted `Unit`; callers
    building `Unit` literals must keep the section-3 invariants.

## 6. API contract

```xi
pub fn unit_parse(text: Str) -> Result[Unit, Str]
pub fn unit_section_count(u: &Unit) -> Int
pub fn unit_key_count(u: &Unit) -> Int
pub fn unit_section_index(u: &Unit, name: Str) -> Int
pub fn unit_section_name(u: &Unit, index: Int) -> Option[Str]
pub fn unit_section_key_count(u: &Unit, index: Int) -> Int
pub fn unit_section_keys(u: &Unit, index: Int) -> Vec[Str]
pub fn unit_section_value_at(u: &Unit, section: Int, key: Int) -> Option[Str]
pub fn unit_key_at(u: &Unit, index: Int) -> Option[Str]
pub fn unit_value_at(u: &Unit, index: Int) -> Option[Str]
pub fn unit_get(u: &Unit, section: Str, key: Str) -> Option[Str]
pub fn unit_get_last(u: &Unit, section: Str, key: Str) -> Option[Str]
pub fn unit_emit(u: &Unit) -> Str
```

Semantics:

- `unit_parse` -- Ok for any document that satisfies section 5, including an
  empty one; Err with a section-7 message otherwise. Errors are reported at
  the first offending byte in document order (control bytes are checked over
  the whole text before any line is interpreted).
- `unit_section_count` -- number of distinct sections.
- `unit_key_count` -- total entry count, duplicates included.
- `unit_section_index` -- first-seen index of `name`, or `-1`.
- `unit_section_name` -- section name at `index`, or `None`.
- `unit_section_key_count` -- entries in the section at `index`, or `-1` when
  the index is out of range (`0` means the section exists but is empty).
- `unit_section_keys` -- a fresh `Vec[Str]` of that section's keys in entry
  order; empty when the index is out of range.
- `unit_section_value_at` -- value of the `key`-th entry of section index
  `section`, or `None`.
- `unit_key_at` / `unit_value_at` -- flat entry access by document-order index,
  or `None`.
- `unit_get` / `unit_get_last` -- first/last value assigned to
  (section, key), or `None` when the section or key is absent.
- `unit_emit` -- canonical text (section 5 decision 13); total.

Complexity, with `L` input length, `E` entries, `S` sections and `O` output
length: `unit_parse` is O(L) for scanning plus O(E) per insertion when
sections reopen, i.e. O(L + E * S) worst case and O(L + E) when every section
appears in a single run. Lookups are O(S + E) (linear scan of the section's
range); `unit_section_keys` is O(E); `unit_emit` is O(O); the range-vector
accessors are O(1).

## 7. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"systemd: "`. The
offending logical line is appended after `": "` (for the control-byte errors
the message carries the byte value instead, because a control byte inside a
message is not printable).

| Message | Trigger |
|---|---|
| `systemd: control byte 0xNN in input` | any byte < 0x20 other than TAB/LF, or a CR not followed by LF |
| `systemd: key before any section: <line>` | `Description=x` before the first `[Section]` |
| `systemd: malformed section header: <line>` | `[Unit`, `[Un it]`, `[Unit]junk`, `[[Unit]]`, `[]x`, `[  ]` |
| `systemd: empty section name: <line>` | `[]` |
| `systemd: line without '=': <line>` | `justakey`, `Key value` (no `=`) |
| `systemd: empty key in line: <line>` | `=value`, `   =` |
| `systemd: malformed key in line: <line>` | `Key name=v`, `Key\tname=v` (SP/TAB inside the key) |
| `systemd: continuation at end of input: <text>` | `Key=a\` as the final physical line |

The `<line>` shown for a pair is the joined logical line (continuation
markers already removed). `unit_emit` and every accessor are total for any
`Unit` value.

## 8. Test plan

`tests/test_conformance.xi` (module `systemd_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | two-section parse | sections, entries, lookup misses, counts and order |
| t2 | full-line comments | `#`/`;` skipped; inline markers are data |
| t3 | value whitespace | leading SP/TAB trimmed, trailing kept, empty value allowed |
| t4 | continuation joins | join without separator, repeated joins, key order |
| t5 | continued comment | a trailing `\` also continues a comment line |
| t6 | duplicate keys | preserved in order, `unit_get` first / `unit_get_last` last |
| t7 | reopened section | one contiguous range, section order, flat layout |
| t8 | CRLF input | CR stripped, trailing spaces kept |
| t9 | blank/indented lines | whitespace-only lines skipped, leading line ws ignored |
| t10 | bad headers | `[]`, `[  ]`, `[Unit`, `[Un it]`, `[Unit]junk`, `[[Unit]]`, `[]x` |
| t11 | key before section | `Description=x` before `[Unit]` is Err |
| t12 | bad pairs | missing `=`, empty key, whitespace-bearing key |
| t13 | continuation at EOF | trailing `\` with no next line is Err; a blank line completes it |
| t14 | control bytes | `0x01`, `0x1f`, `0x07`, `0x0b` anywhere are Err |
| t15 | lone CR | CR without LF is Err |
| t16 | emit layout | exact canonical text, blank-line separators, empty section |
| t17 | round trip | parse -> emit -> parse stable, emit idempotent |
| t18 | empty documents | `""` and comment-only input: zero sections, emit `""` |
| t19 | index accessors | all accessors at valid and out-of-range indices |
| t20 | case sensitivity | section names and keys are byte-exact |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.ini` / `xiom.dotenv` (byte-wise scanning with
`xiom.string.byte_at`, `Vec[UInt8]` accumulation with
`xiom.string.builder.sb_to_str`) and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the document is flat: five parallel
  range/metadata vectors, not a list of section or entry structs.
- `Ok`/`Err` for `Result[Unit, Str]` are constructed only in the leaf helpers
  `_ok_unit`/`_err_unit`; `_apply_line` communicates success through
  `Result[Int, Str]` built by `_ok_int`/`_err_int`.
- Str equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); values are read into typed
  locals before use.
- Every `UInt8` read is widened with `(b as Int) & 0xFF` before numeric
  comparison; byte constants are below 128.
- `_section_span` returns a small private `_Span` struct holding the clamped
  `start`/`count` pair, so the accessors share one bounds-checking path.
- Tests dispatch directly (`t1()` ... `t20()`); `Vec[fn]` indexed calls are
  not used, no match pattern binds `mut`, no inline lambdas, and every
  `match` is exhaustive.
- `Str` is NUL-terminated in this compiler: `"\x00"` truncates a literal and
  `sb_to_str` must not be handed a 0x00 byte, so the module never builds a
  message or output from a control byte and the NUL row of the catalog is
  defensive only.

## 10. Known limitations

- No directive semantics of any kind (no lists, booleans, `Environment=`
  splitting, no `reset`-style empty assignment semantics).
- No drop-ins, include files, aliases, templates/instances or specifier
  expansion.
- No comments preserved; no continuation reconstruction.
- No inline comments and no escaping beyond the trailing-backslash join.
- Keys cannot contain SP/TAB; there is no key quoting.
- CR only as part of CRLF; NUL is not representable in `Str`.
- No file I/O, no streaming, no directory scanning.
- Errors carry no line/column position (the offending line text is included,
  except for control-byte errors, which carry the byte value).
