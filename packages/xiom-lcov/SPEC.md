# xiom.lcov -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.lcov` (`src/lcov.xi`). Pure XIOM, no FFI, no I/O.

## 1. Scope

A line-based parser and canonical emitter for a documented LCOV tracefile
subset, all in memory:

- `lcov_parse` reads one `Str` tracefile into an `LcovDoc`;
- file, record and summary accessors expose what the tracefile said and what
  the records actually imply;
- `lcov_emit` serializes a document back to canonical LCOV.

The subset is: `TN:<test name>`, `SF:<source file>`, `FN:<line>,<name>`,
`FNDA:<count>,<name>`, `FNF:<n>`, `FNH:<n>`, `DA:<line>,<count>[,<checksum>]`,
`LF:<n>`, `LH:<n>`, `BRDA:<line>,<block>,<branch>,<taken|->`, `BRF:<n>`,
`BRH:<n>` and `end_of_record`. The grammar in section 4 is exact; section 8 is
the complete error catalog. Anything outside the subset is a deterministic
`Err("lcov: ...")` with a 1-based line number.

`Str` is treated as a UTF-8 byte buffer. Line scanning is byte-wise; every
stored value is a slice of the input, so non-ASCII content (multi-byte UTF-8
in test names, paths, function names or checksums) round-trips byte-exact.

## 2. Non-goals

- **No gcov / llvm-cov invocation, no instrumentation.** The module is a
  codec; it never produces coverage data.
- **No coverage merging, filtering or baseline subtraction.** Two documents
  are parsed independently; combining them is the caller's job.
- **No branch-condition or expression semantics.** `BRDA` is opaque data.
- **No report generation**: no HTML, no text summary, no percentage.
- **No declared/computed reconciliation.** A mismatch is reported, never
  repaired or rejected.
- **No file I/O, no streaming.** The whole `Str` is in memory.
- **No error recovery.** The first offending line aborts the parse; records
  parsed before it are discarded because the function returns `Err`.
- **No `VER:`-style extensions, no `#` comments, no BOM stripping, no
  standalone-CR line endings.**
- No FFI, no registry integration, no new dependencies.

## 3. Data model

`LcovDoc` is flat because XIOM v0.61.3 cannot hold `Vec[StructType]`:

```xi
pub type LcovDoc = {
  sf: Vec[Str];            // per file: source path
  tn: Vec[Str];            // per file: test name ("" = none)
  decl_fnf: Vec[Int];      // per file: declared FNF (-1 = absent)
  decl_fnh: Vec[Int];      // ...
  decl_lf: Vec[Int];
  decl_lh: Vec[Int];
  decl_brf: Vec[Int];
  decl_brh: Vec[Int];
  fn_off: Vec[Int];   fn_n: Vec[Int];       // ranges into fn_line/fn_name
  fn_line: Vec[Int];  fn_name: Vec[Str];
  fnda_off: Vec[Int]; fnda_n: Vec[Int];     // ranges into fnda_hits/fnda_name
  fnda_hits: Vec[Int]; fnda_name: Vec[Str];
  da_off: Vec[Int];   da_n: Vec[Int];       // ranges into the four DA arrays
  da_line: Vec[Int];  da_hits: Vec[Int]; da_cs: Vec[Int]; da_checksum: Vec[Str];
  brda_off: Vec[Int]; brda_n: Vec[Int];     // ranges into the four BRDA arrays
  brda_line: Vec[Int]; brda_block: Vec[Str];
  brda_branch: Vec[Str]; brda_taken: Vec[Int];
}
```

File section `f` (0-based, in stream order) is `sf[f]` / `tn[f]` plus its
record ranges in the four global stores. Every push on a store is mirrored on
its `*_n` counter, so ranges never drift; `lcov_file_count` and every range
accessor clamp to the shortest parallel arrays, so a hand-built document can
never cause an out-of-range read either.

`da_cs[f][i]` is `1` when the `DA` record carried a third field and `0` when
it did not; this keeps "no checksum" distinguishable from "empty checksum"
(which is rejected anyway). `brda_taken` stores `-1` for the `-` sentinel;
taken counts are non-negative otherwise.

## 4. Exact record grammar

```
tracefile   = *( blank / tn / section )
blank       = ws*
tn          = "TN:" rest
section     = sf *( record ) "end_of_record"
sf          = "SF:" path
record      = fn / fnda / fnf / fnh / da / lf / lh / brda / brf / brh
fn          = "FN:" uint "," name
fnda        = "FNDA:" uint "," name
fnf         = "FNF:" uint
fnh         = "FNH:" uint
da          = "DA:" uint "," uint [ "," checksum ]
lf          = "LF:" uint
lh          = "LH:" uint
brda        = "BRDA:" uint "," block "," branch "," taken
brf         = "BRF:" uint
brh         = "BRH:" uint
ws          = SPACE / TAB
uint        = 1*( "0".."9" )             value <= 1000000000, <= 10 digits
taken       = uint / "-"
rest        = 0*( any byte except LF and CR )     -- verbatim
path        = 1*( any byte except LF and CR )     -- non-empty
name        = 1*( any byte except LF and CR and "," )  -- non-empty
block       = 1*( any byte except LF and CR and "," )  -- verbatim, non-empty
branch      = same as block
checksum    = 1*( any byte except LF and CR and "," )  -- verbatim, non-empty
```

Line splitting: the stream is split on LF; one CR immediately before the LF
(or before end of input) is dropped, so LF and CRLF both work. A standalone
CR is content, not a terminator. A line that is empty or holds only SPACE/TAB
is ignored. No other trimming happens: `DA:1,2 ` (trailing space) is a
non-numeric-field error, not a lenient parse.

## 5. Parsing rules and decisions

Each rule is covered by the conformance suite; section 11 maps them to checks.

1. **Dispatch order.** A non-blank line is classified in this order:
   `end_of_record`, `SF:`, `TN:`, then (inside an open section) the ten data
   records, and otherwise unknown.
2. **Sections.** `SF:<path>` opens a file section; `end_of_record` closes it.
   A section may contain any number of records, in any order, including none.
   The same path may appear in multiple sections; they stay separate.
3. **Unclosed section.** A new `SF:` while a section is open is
   `missing end_of_record` naming the *open* section's SF line. Reaching end
   of input with a section still open is the same error with the same line.
4. **Records outside a section.** `FN`, `FNDA`, `FNF`, `FNH`, `DA`, `LF`,
   `LH`, `BRDA`, `BRF`, `BRH` and `end_of_record` before any `SF:`, or after
   an `end_of_record` without a new `SF:`, are `record outside source file`.
5. **TN.** `TN:` is legal anywhere, inside or outside a section. It sets the
   current test name to the rest of the line (may be empty). It labels every
   `SF:` section that starts after it, until the next `TN:`; it does not
   relabel an already-open section. Two `TN:` records are last-wins.
6. **Numbers.** A numeric field is a digits run of at most 10 digits with a
   value `<= 1000000000` (so it can never overflow). Leading zeros are
   accepted (`DA:007,01` is line 7, hits 1). An empty, non-digit or
   overflowing field is `non-numeric field`; a leading `-` with at least one
   more byte is `negative number`.
7. **Field counts.** `FN` and `FNDA` take exactly two comma-separated fields,
   `DA` two or three, `BRDA` exactly four, and `FNF`/`FNH`/`LF`/`LH`/`BRF`/
   `BRH` exactly one. Any other count is `bad field count`.
8. **Empty required fields.** The SF path, an FN/FNDA name, a BRDA block or
   branch, and a present DA checksum must be non-empty; an empty one is
   `empty field`. An empty `TN:` is legal and means "no test name".
9. **Declared records.** `FNF`, `FNH`, `LF`, `LH`, `BRF`, `BRH` store the
   declared value of the current file; a second record of the same kind
   overwrites the first (last wins). `0` is a real value distinct from
   "absent" (`-1` in the accessors).
10. **Block and branch fields.** `BRDA` block and branch are stored verbatim
    (any non-empty text without commas), not parsed as numbers.
11. **Taken field.** `BRDA` taken is either a non-negative count or the bare
    `-` sentinel (stored as `-1`). `-` followed by digits is `negative
    number`, and the bare `-` is not accepted anywhere else.
12. **Mismatch tolerance.** A declared total that disagrees with the records
    is never an error; section 6 explains the accessors.
13. **No comments, no directives.** A line starting with `#` is an unknown
    record; the LCOV extension records (`VER:`, `FNL:`, `FNA:`, ...) are not
    part of the subset.
14. **Determinism.** The same input always yields the same document or the
    same first error; the input is never mutated.

## 6. Declared vs computed summaries

For each file section, the declared records (when present) and the computed
values are both exposed:

| Summary | Declared accessor (`-1` = absent) | Computed accessor | Computed from |
|---|---|---|---|
| functions found | `lcov_declared_fnf` | `lcov_computed_fnf` | number of `FN` records |
| functions hit | `lcov_declared_fnh` | `lcov_computed_fnh` | number of `FNDA` records with hits `> 0` |
| lines found | `lcov_declared_lf` | `lcov_computed_lf` | number of `DA` records |
| lines hit | `lcov_declared_lh` | `lcov_computed_lh` | number of `DA` records with hits `> 0` |
| branches found | `lcov_declared_brf` | `lcov_computed_brf` | number of `BRDA` records |
| branches hit | `lcov_declared_brh` | `lcov_computed_brh` | number of `BRDA` records with taken `>= 1` |

`lcov_*_mismatch` returns `true` exactly when the declared record exists
(`>= 0`) and differs from the computed value; it returns `false` when the
record is absent or the values agree. Mismatches are tolerated at parse time,
preserved by the emitter and reported only through these accessors.

Duplicate names in `FNDA` are counted once per record (no deduplication), and
the `-` sentinel and an explicit `0` both count as not hit for `BRH`.

## 7. Canonical emitter

`lcov_emit(d)` writes file sections in stored order; each section uses
exactly this record order, every emitted line terminated by LF:

1. `TN:<name>` when the section's test name is non-empty;
2. `SF:<source>`;
3. every `FN` record in stored order;
4. every `FNDA` record in stored order;
5. `FNF:<n>`, then `FNH:<n>`, when the declared value exists;
6. every `DA` record in stored order (the checksum field only when the
   record carried one);
7. `LF:<n>`, then `LH:<n>`, when the declared value exists;
8. every `BRDA` record in stored order (`-` when taken is negative);
9. `BRF:<n>`, then `BRH:<n>`, when the declared value exists;
10. `end_of_record`.

An empty document emits `""` (no bytes). Values are written in canonical
decimal (no leading zeros). Emission is canonical rather than byte-identical
to an arbitrary accepted input, because input record order is not preserved
and a `TN` label is written once per labelled section. `lcov_emit` is
idempotent: `lcov_emit(parse(lcov_emit(d))) == lcov_emit(d)`.

## 8. Error catalog

All messages are `"lcov: "` + a lower-case description; `<L>` is the 1-based
physical line number of the offending line. The first offending line aborts
the parse and everything parsed before it is discarded (`Err`, not a partial
document).

| Condition | Exact message |
|---|---|
| Line matches no record prefix (empty prefix, `# comment`, `VER:`, ...) | `lcov: unknown record at <L>` |
| Wrong number of comma-separated fields for the record kind | `lcov: bad field count at <L>` |
| Empty SF path, FN/FNDA name, BRDA block/branch or DA checksum | `lcov: empty field at <L>` |
| Numeric field empty, non-digit, over 10 digits or `> 1000000000` | `lcov: non-numeric field at <L>` |
| Numeric field starts with `-` (including `-<digits>`) | `lcov: negative number at <L>` |
| File-scoped record with no open section | `lcov: record outside source file at <L>` |
| EOF or a new `SF:` while a section is open | `lcov: missing end_of_record at <L>` (`<L>` = the open section's SF line) |

## 9. API contract

```xi
pub fn lcov_parse(text: Str) -> Result[LcovDoc, Str]
pub fn lcov_emit(d: &LcovDoc) -> Str
pub fn lcov_doc_new() -> LcovDoc

pub fn lcov_file_count(d: &LcovDoc) -> Int
pub fn lcov_file_source(d: &LcovDoc, f: Int) -> Str
pub fn lcov_file_test_name(d: &LcovDoc, f: Int) -> Str

pub fn lcov_declared_fnf(d: &LcovDoc, f: Int) -> Int
pub fn lcov_declared_fnh(d: &LcovDoc, f: Int) -> Int
pub fn lcov_declared_lf(d: &LcovDoc, f: Int) -> Int
pub fn lcov_declared_lh(d: &LcovDoc, f: Int) -> Int
pub fn lcov_declared_brf(d: &LcovDoc, f: Int) -> Int
pub fn lcov_declared_brh(d: &LcovDoc, f: Int) -> Int

pub fn lcov_computed_fnf(d: &LcovDoc, f: Int) -> Int
pub fn lcov_computed_fnh(d: &LcovDoc, f: Int) -> Int
pub fn lcov_computed_lf(d: &LcovDoc, f: Int) -> Int
pub fn lcov_computed_lh(d: &LcovDoc, f: Int) -> Int
pub fn lcov_computed_brf(d: &LcovDoc, f: Int) -> Int
pub fn lcov_computed_brh(d: &LcovDoc, f: Int) -> Int

pub fn lcov_fnf_mismatch(d: &LcovDoc, f: Int) -> Bool
pub fn lcov_fnh_mismatch(d: &LcovDoc, f: Int) -> Bool
pub fn lcov_lf_mismatch(d: &LcovDoc, f: Int) -> Bool
pub fn lcov_lh_mismatch(d: &LcovDoc, f: Int) -> Bool
pub fn lcov_brf_mismatch(d: &LcovDoc, f: Int) -> Bool
pub fn lcov_brh_mismatch(d: &LcovDoc, f: Int) -> Bool

pub fn lcov_fn_count(d: &LcovDoc, f: Int) -> Int
pub fn lcov_fn_line(d: &LcovDoc, f: Int, i: Int) -> Int
pub fn lcov_fn_name(d: &LcovDoc, f: Int, i: Int) -> Str
pub fn lcov_fnda_count(d: &LcovDoc, f: Int) -> Int
pub fn lcov_fnda_hits(d: &LcovDoc, f: Int, i: Int) -> Int
pub fn lcov_fnda_name(d: &LcovDoc, f: Int, i: Int) -> Str
pub fn lcov_da_count(d: &LcovDoc, f: Int) -> Int
pub fn lcov_da_line(d: &LcovDoc, f: Int, i: Int) -> Int
pub fn lcov_da_hits(d: &LcovDoc, f: Int, i: Int) -> Int
pub fn lcov_da_has_checksum(d: &LcovDoc, f: Int, i: Int) -> Bool
pub fn lcov_da_checksum(d: &LcovDoc, f: Int, i: Int) -> Str
pub fn lcov_brda_count(d: &LcovDoc, f: Int) -> Int
pub fn lcov_brda_line(d: &LcovDoc, f: Int, i: Int) -> Int
pub fn lcov_brda_block(d: &LcovDoc, f: Int, i: Int) -> Str
pub fn lcov_brda_branch(d: &LcovDoc, f: Int, i: Int) -> Str
pub fn lcov_brda_taken(d: &LcovDoc, f: Int, i: Int) -> Int
```

Sentinels (never an out-of-range read):

| Situation | Return |
|---|---|
| `lcov_file_source`, `lcov_file_test_name`, `lcov_*_name`, `lcov_da_checksum`, `lcov_brda_block`, `lcov_brda_branch` out of range | `""` |
| `lcov_fn_line`, `lcov_fnda_hits`, `lcov_da_line`, `lcov_da_hits`, `lcov_brda_line` out of range | `-1` |
| `lcov_brda_taken` `-` sentinel or out of range | `-1` |
| `lcov_declared_*` absent or out of range | `-1` |
| `lcov_computed_*`, `*_count` out of range | `0` |
| `lcov_*_mismatch` absent/out of range | `false` |

**Round trip.** For any document `d` produced by `lcov_parse`, let
`e = lcov_emit(d)`. Then `lcov_parse(e)` succeeds and returns a document with
the same sections, test names, record values, checksum presence and declared
values as `d`; and `lcov_emit` of that document equals `e`. The suite checks
this structurally (never with `==` on element strings, BUG 17) plus string
equality of the two emissions.

Complexity: `lcov_parse` and `lcov_emit` are O(input length) with string
concatenation costs; record counts and file accessors are O(1); the computed
hit counts and mismatch flags are O(records of that file).

## 10. Test matrix

`tests/test_conformance.xi` (module `lcov_tests`) runs 21 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). All string comparisons go through `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | every record kind, accessors, computed summaries | sections 4, 6 |
| t2 | per-file ranges across two sections | rules 2, 3 of section 5, section 3 |
| t3 | canonical record order from shuffled input | section 7 |
| t4 | CRLF and blank lines | line splitting, section 5 |
| t5 | TN labels following sections, empty TN omitted | rule 5 |
| t6 | declared/computed mismatch tolerated and exposed | rule 12, section 6 |
| t7 | duplicate TN and declared record are last-wins | rules 5, 9 |
| t8 | `-`, `0` and positive taken counts stay distinct | rule 11, section 6 |
| t9 | 0..1000000000 accepted, leading zeros, overflow rejected | rule 6 |
| t10 | unknown record prefixes | rule 1, catalog |
| t11 | wrong comma counts | rule 7, catalog |
| t12 | non-digit bytes in numeric fields | rule 6, catalog |
| t13 | negative numbers and the bare `-` | rules 6, 11, catalog |
| t14 | records outside an open section | rule 4, catalog |
| t15 | unclosed section at EOF and on a nested SF | rule 3, catalog |
| t16 | empty required fields | rule 8, catalog |
| t17 | empty, blank-only and TN-only inputs | rules 4, 13 |
| t18 | out-of-range accessor sentinels | section 9 |
| t19 | round trip and emit idempotence over nine inputs | section 9 |
| t20 | declared zero is present, not absent | rule 9, section 7 |
| t21 | spaces/punctuation in names, paths and checksums | section 1 |

## 11. Known limitations

- No gcov, merge, filter or report features (section 2).
- Function names, checksums and BRDA block/branch fields may not contain
  commas; a comma splits the fields and typically triggers a field-count or
  numeric error.
- A `DA` checksum may not be empty; `DA:1,2,` is an error.
- Only one CR is dropped from the end of a line, and only SPACE/TAB-only
  lines count as blank; other surrounding whitespace is content.
- No `VER:`/`FNL:`/`FNA:` extensions, no `#` comments, no BOM stripping.
- `TN` labels are attached to sections, not to whole streams; the emitter
  repeats the label before every labelled section.
- Numbers are capped at 1000000000; larger values are rejected rather than
  wrapped.
- Declared totals are stored but never reconciled or repaired.
- Errors are first-error only; no recovery, no partial document.

## 12. Compiler / stdlib notes (v0.61.3)

The implementation follows the proven idioms of the sibling packages
(`xiom.tap`, `xiom.lexing`, `xiom.bencode`): free functions only, flat
parallel `Vec`s instead of `Vec[StructType]`, byte-wise scanning with
`xiom.string.byte_at` / `str_slice`, and `Result` construction confined to
the leaf helpers `_ok_doc` / `_err_doc` because constructing `Ok`/`Err` in
other shapes miscompiles in this compiler.

Every `Str` read from a `Vec[Str]` element is bound to a typed local and
compared with `str_compare` (BUG 17: `==` on such values lowers to a pointer
comparison); `Int` element reads are likewise bound to typed locals. Widened
bytes are masked (`(b as Int) & 0xFF`). Numeric runs longer than 10 digits are
rejected before any accumulation, so the value can never overflow. Record
counters are updated with indexed writes on the `*_n` arrays (an idiom
validated by `xiom.bencode`); every per-file array is pushed together in
`_file_push`, and every range accessor clamps to the shortest parallel
arrays, so mismatched arrays cannot cause an out-of-range read. No
`&struct.field` is passed as a `&Vec` parameter. No workarounds beyond these
documented patterns were required.
