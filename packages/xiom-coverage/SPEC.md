# xiom.coverage -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.coverage` (`src/coverage.xi`). Pure XIOM, no FFI, no I/O.

## 1. Scope

A line-based parser, accessor set, canonical emitter and summary math for the
**text form** of gcov coverage data (the `.gcov` files written by
`gcov --stdout` / `gcov -t`), all in memory:

- `gcov_parse` reads one `Str` stream into a `GcovDoc`;
- per-file and overall accessors expose metadata, records and summary math;
- `gcov_emit` serializes a document back to canonical `.gcov` text.

The subset is: `Source`, `Graph`, `Data`, `Runs` and `Programs` metadata
records; line records `count:lineno:source` in four count forms; function
summaries `function <name> called <N> returned <P>% blocks executed <Q>%`;
branch records `branch <N> taken <M>` / `branch <N> taken never` /
`branch <N> never executed`; call records `call <N> returned <tail>`; and
unconditional branch records `unconditional <N> taken [<M>]`. The grammar in
section 4 is exact; section 8 is the complete error catalog. Anything outside
the subset is a deterministic `Err("coverage: ...")` naming the line and byte
offset.

`Str` is treated as a UTF-8 byte buffer. Line scanning is byte-wise; every
stored source path, name, tail and source-text value is a slice of the input,
so non-ASCII content (multi-byte UTF-8) round-trips byte-exact.

## 2. Non-goals

- **No `.gcda` / `.gcno` binary parsing.** This module never reads gcov's
  binary counter or graph files. Only the text form is parsed, and the
  numbers in it are trusted as written.
- **No gcov invocation, no instrumentation.** The module is a codec; it never
  produces coverage data.
- **No coverage merging, filtering or baseline subtraction.** Two documents
  are parsed independently; combining them is the caller's job.
- **No branch-condition or expression semantics.** Branch records are opaque
  counts.
- **No report rendering**: no HTML, no text report, no charts. Only the
  summary accessors in section 6.
- **No file I/O, no streaming.** The whole `Str` is in memory.
- **No error recovery.** The first offending line aborts the parse; records
  parsed before it are discarded because the function returns `Err`.
- No BOM stripping, no `#` comments, no standalone-CR line endings, no
  gcov's `*`-suffixed counts, no negative counts.
- No FFI, no registry integration, no new dependencies.

## 3. Data model

`GcovDoc` is flat because XIOM v0.61.3 cannot hold `Vec[StructType]`. All
per-file arrays are index-aligned and parallel; `_file_count` is their
shortest length, so a hand-built document cannot be read out of range.
Records live in six global stores, each addressed through the range
`(off[f], n[f])` of file section `f`, and every range accessor clamps to the
shortest arrays of its store:

```xi
pub type GcovDoc = {
  sf: Vec[Str];        // per file: Source path
  graph: Vec[Str];     // per file: Graph value
  graph_has: Vec[Int]; // per file: 1 = Graph record present
  data: Vec[Str];      // per file: Data value
  data_has: Vec[Int];  // per file: 1 = Data record present
  runs: Vec[Int];      // per file: Runs (-1 = absent)
  programs: Vec[Int];  // per file: Programs (-1 = absent)
  ln_off: Vec[Int]; ln_n: Vec[Int];   // line ranges
  br_off: Vec[Int]; br_n: Vec[Int];   // branch ranges
  fn_off: Vec[Int]; fn_n: Vec[Int];   // function ranges
  cl_off: Vec[Int]; cl_n: Vec[Int];   // call ranges
  un_off: Vec[Int]; un_n: Vec[Int];   // unconditional ranges
  ev_off: Vec[Int]; ev_n: Vec[Int];   // event ranges (stream order)
  ln_no: Vec[Int]; ln_cnt: Vec[Int]; ln_src: Vec[Str];
  br_idx: Vec[Int]; br_taken: Vec[Int];
  fn_name: Vec[Str]; fn_called: Vec[Int]; fn_ret: Vec[Int]; fn_blocks: Vec[Int];
  cl_idx: Vec[Int]; cl_tail: Vec[Str];
  un_idx: Vec[Int]; un_taken: Vec[Int];
  ev_kind: Vec[Int]; ev_ref: Vec[Int];
}
```

- `ln_cnt[i]` stores the printed count for a digits record, or one of the
  sentinels `GCOV_NOT_EXECUTED` (-1, `#####`), `GCOV_NO_CODE` (-2, `=====`)
  and `GCOV_NO_LINE` (-3, `-`).
- `br_taken[i]` stores the taken count (`>= 0`) or -1 for
  `never executed` / `taken never`.
- `un_taken[i]` stores the count or -1 when the record carried none.
- `fn_ret[i]` / `fn_blocks[i]` store the two printed percents (0..100).
- The event store keeps the per-file record order: each event is a
  `(ev_kind[i], ev_ref[i])` pair, where `ev_kind` is one of the `GCOV_EV_*`
  constants and `ev_ref` is the record's local index in the corresponding
  per-file store. This is what lets `gcov_emit` replay the input stream
  order.
- Presence flags (`graph_has`, `data_has`) and the `-1` sentinels
  (`runs`, `programs`, `un_taken`) distinguish "record present with value"
  from "record absent" without trusting `.len()` on strings read from
  `Vec[Str]` elements (a known v0.61.3 miscompilation, BUG 17).

Every push on a store is mirrored on the owning file's `*_n` counter and, for
record stores, on the event store, so ranges never drift.

## 4. Exact record grammar

```
stream      = *( blank / record )
blank       = ws*
record      = meta / line / function / branch / call / unconditional
meta        = "-:" ws* "0" ":" key ":" value
key         = "Source" / "Graph" / "Data" / "Runs" / "Programs"
line        = cnt-field ":" ln-field ":" src
cnt-field   = ws* ( digits / "#####" / "=====" / "-" )
ln-field    = ws* digits ws*
src         = 0*( any byte except LF and CR )          -- verbatim
function    = "function " name " called " called " returned " pct "% blocks executed " pct "%"
name        = 1*( any byte except LF and CR )           -- no " called " substring
called      = digits
pct         = digits                                    -- value <= 100
branch      = "branch" ws+ idx ws+ ( taken / never-exec )
taken       = "taken" ws+ ( digits / "never" )
never-exec  = "never" ws+ "executed"
idx         = digits
call        = "call" ws+ idx ws+ "returned" ws+ tail
tail        = 1*( any byte except LF and CR )           -- non-blank, verbatim
uncond      = "unconditional" ws+ idx ws+ "taken" [ ws+ digits ]
digits      = 1*( "0".."9" )  value <= 1000000000, <= 10 digits
ws          = SPACE / TAB
value       = 1*( any byte except LF and CR )           -- non-empty (meta)
```

Notes on the exact surface:

- The record keywords (`function`, `branch`, `call`, `unconditional`) may be
  preceded by SPACE/TAB, but nothing else. Keywords are matched by prefix;
  `function` requires the following SPACE (the `name` starts after it).
- A line record's `count` and `lineno` fields may be padded with SPACE/TAB;
  the source text after the second `:` is kept verbatim (leading spaces are
  significant content).
- A meta record is exactly a line record whose `count` is `-`, whose
  `lineno` is `0`, and whose text starts with `key ":"`. `Source` must have a
  non-empty value; `Graph`/`Data` too; `Runs`/`Programs` values must be pure
  digits.
- The function `name` runs from after `function ` to the first literal
  `" called "` and must be non-empty (C identifiers cannot contain spaces, so
  this is unambiguous for gcov output).
- `branch <N> taken never` and `branch <N> never executed` both store -1.
- Anything after the last token of a record must be SPACE/TAB only.

Line splitting: the stream is split on LF; one CR immediately before the LF
(or before end of input) is dropped, so LF and CRLF both work. A standalone
CR is content, not a terminator. A line that is empty or holds only SPACE/TAB
is ignored. No other trimming happens.

## 5. Parsing rules and decisions

1. A `Source` meta record opens a new file section. A stream may hold any
   number of sections, in stream order.
2. `Graph`, `Data`, `Runs`, `Programs` update the **open** section; a
   duplicate overwrites (last wins). Before any `Source` they are
   `record before Source` errors (after value validation).
3. Line, function, branch, call and unconditional records append to the open
   section in stream order and are only legal after a `Source`; any record
   before it is a `record before Source` error.
4. `#####` means not executed, `=====` means the line has no code, `-` (with
   a positive line number) means no line. All three are stored as sentinels;
   everything else about them is data.
5. Executable/covered decisions are summary-time (section 6), not parse-time.
6. A count of `0` is accepted, is executable, and is **not** covered.
7. Branch indices need not be unique or ordered; records are stored verbatim,
   in stream order, including duplicate indices.
8. Function percentages are validated to 0..100; a 101% record is malformed.
9. Call tails are opaque: `call 0 returned never` is valid and the tail
   `never` is preserved verbatim.
10. The unconditional count is optional; `unconditional 0 taken` stores -1
    and emits without a count.
11. `Source` with an empty path, empty `Graph`/`Data` values and non-numeric
    `Runs`/`Programs` values are `bad metadata value` errors.
12. Empty input, blank-only input, or an input with no records parses to an
    empty document (`gcov_file_count == 0`) that emits `""`.
13. Numeric fields reject negative signs (`-5` -> malformed), non-digits,
    more than 10 digits, and values above 1000000000.

## 6. Summary math

All coverage numbers are derived from the stored records; percents use
truncating integer division (which is floor for non-negative values), with a
guaranteed `0` when the denominator is 0:

- **Executable lines** (`gcov_file_executable_lines`): line records whose
  count is a digits value (including `0`) or `#####`. `=====` and `-` are
  not executable.
- **Covered lines** (`gcov_file_covered_lines`): count `>= 1`. Both `0` and
  `#####` count as uncovered.
- **Unexecuted lines** (`gcov_file_unexecuted_lines`):
  `max(0, executable - covered)`.
- **Line percent / basis points**: `floor(covered * 100 / executable)` and
  `floor(covered * 10000 / executable)`; 0 when no executable lines.
- **Branch totals / taken**: every branch record counts; taken means
  `br_taken >= 1` (`taken 0`, `taken never` and `never executed` are not
  taken). Percent as above; 0 when no branch records.
- **Function totals / called**: every function summary counts; called means
  `fn_called >= 1`. Percent as above; 0 when no function records.
- **Totals** (`gcov_total_*`): sum the per-file numerators and denominators
  first, then divide once; pooled totals are exact and are never an average
  of per-file percents.

There are no floating-point values anywhere (XIOM v0.61.3 has no
`Vec[Float64]`), so every metric is an integer; basis points give
two-decimal resolution.

## 7. Canonical emission

`gcov_emit` writes, for each file section in stored order:

1. `-:0:Source:<path>`;
2. `-:0:Graph:<value>` when present, `-:0:Data:<value>` when present,
   `-:0:Runs:<n>` when present, `-:0:Programs:<n>` when present
   (fixed order, once each; duplicates collapse by last-wins);
3. its records in the **original stream order** (the event store), each
   normalized:
   - line: `<count>:<lineno>:<src>`, count as digits / `#####` / `=====` /
     `-`, no padding, `src` verbatim;
   - function: `function <name> called <N> returned <P>% blocks executed
     <Q>%`;
   - branch: `branch <N> taken <M>` for `M >= 0`, else
     `branch <N> never executed`;
   - call: `call <N> returned <tail>` with the verbatim tail;
   - unconditional: `unconditional <N> taken <M>` when `M >= 0`, else
     `unconditional <N> taken`.

Every line ends with LF; an empty document emits `""`. Emission is
canonicalization, not byte preservation: padding disappears, `taken never`
and `never executed` both normalize to `never executed`. Re-parsing emitted
text yields an equivalent document (`doc_equal`: metadata, all records and
event pairs) and emitting again is byte-identical.

## 8. Error catalog

Every rejection is `Err("coverage: <reason> at line L byte O")`, where `L`
is the 1-based line number and `O` is the 0-based byte offset of that line's
first non-SPACE/TAB byte. The complete reason list:

| Reason | Trigger |
|--------|---------|
| `unknown record` | first non-blank byte is not a digit, `-`, `#`, `=`, or a known keyword |
| `malformed line record` | missing `:` fields, empty/invalid count or line number, `lineno == 0` with a non-`-` count, >10 digit or >1000000000 values |
| `record before Source` | any line/branch/function/call/unconditional (or `Graph`/`Data`/`Runs`/`Programs`) before the first `Source` |
| `unknown metadata` | `-:0:<key>:` where `key` is not Source/Graph/Data/Runs/Programs |
| `bad metadata value` | empty `Source`/`Graph`/`Data` value, or non-numeric `Runs`/`Programs` value |
| `malformed function record` | missing ` called `/` returned `/`%`/` blocks executed `/`%`, empty name, non-numeric or out-of-range count/percent, trailing junk |
| `malformed branch record` | non-numeric index, missing `taken`/`never executed`, non-numeric taken count, trailing junk |
| `malformed call record` | non-numeric index, missing `returned`, blank tail, trailing junk |
| `malformed unconditional record` | non-numeric index, missing `taken`, non-numeric count, trailing junk |

The first offending line aborts the parse; no partial document is returned.

## 9. Complexity and limits

- Parse/emit: O(input length); the ` called ` search is O(line length)
  because function lines are short.
- Summary accessors: O(records); totals are O(files * records).
- Numeric values are capped at 1000000000 and 10 digits, so `part * 10000`
  cannot overflow the Int accumulator for values this parser can produce.
- No global state; every function is deterministic and free of I/O.

## 10. Conformance mapping

| Area | Checks |
|------|--------|
| Happy path: all 5 metadata kinds, all 6 record stores, accessors, summaries, exact emit | t1 |
| Multi-file ranges and pooled totals | t2, t13 |
| Count forms and padding; `0` executable but uncovered | t3, t20 |
| No executable lines -> 0 percents | t4, t21 |
| Branch forms (`taken M`, `taken 0`, `taken never`, `never executed`) | t5, t12 |
| Function summaries, called math, leading zeros | t6, t18 |
| CRLF and blank lines | t7 |
| Metadata last-wins and canonical metadata order | t8 |
| Empty/blank-only input | t9 |
| Error catalog with exact messages and byte offsets | t10 |
| Event store stream order | t11 |
| Call tails verbatim; optional unconditional count | t14 |
| Count cap 1000000000 and integral math | t15 |
| Multi-byte UTF-8 round trip | t16 |
| Out-of-range accessor sentinels | t17 |
| Round trips and emit idempotence | t19 |
| Verbatim, deterministic record indices and order | t22 |

Run them with `.\scripts\port.ps1 -Package xiom.coverage`.
