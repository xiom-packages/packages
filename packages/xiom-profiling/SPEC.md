# xiom.profiling -- Specification

Status: incubating, pure XIOM (no FFI), package version 0.1.0.
This document is normative for the behavior pinned by
`tests/test_conformance.xi`.

## 1. Purpose

Analyze folded-stack sampling profiles (the `"<stack> <count>"` line format
emitted by `perf script | stackcollapse-perf.pl` and equivalent tools):
parse text into a table, aggregate totals / duplicates / leaves, rank the
heaviest stacks, and collapse stacks to a fixed depth. No rendering, no
frame normalization, no FFI.

## 2. Data model

```xi
pub type ProfData = {
  stacks: Vec[Str];   // ';'-separated frame list, leaf last
  counts: Vec[Int];   // sample count of stacks[i]
}
```

Invariant: `stacks.len() == counts.len()`; `counts[i] >= 0`. The two vectors
are used instead of a `Vec[StructType]` because XIOM v0.61.3 miscompiles
vectors of records. `ProfData` is never nested in a `Vec`.

## 3. Line grammar

Input is a byte string. Lines are separated by LF (`\n`); the last line does
not need a trailing LF. For each physical line:

1. If the line is empty after stripping **one** trailing CR (`\r`), skip it
   (blank line). Blank lines still advance the physical line counter.
2. Otherwise the line must match:

```
line   = stack, 1*SP, count ;
stack  = ? any byte sequence of length >= 1 that does not end in a space ? ;
count  = 1*DIGIT ;                      // "0".."9223372036854775807"
SP     = %x20 ;                         // ASCII space, exactly; not TAB
DIGIT  = %x30-39 ;
```

Concretely, scanning from the end of the line:

- `count` is the maximal trailing run of ASCII digits. No sign, no leading
  `+`/`-`, no radix prefix. The value must fit a signed 64-bit `Int`.
- immediately before `count` there is a run of one or more ASCII spaces
  (0x20) — the separator. Two or more spaces are equivalent to one; the
  separator is not part of the stack.
- `stack` is every byte before that space run, verbatim (leading spaces, tabs
  and interior spaces included), and must be non-empty.

Consequences (all pinned by tests):

- `"a;b 12"`, `"a;b  12"` and `"c   4"` parse; `"a;b\t12"` does not
  (TAB is not the separator);
- `"nope"`, `"a;b x"` and `"a 1 "` (trailing space after the count) are
  malformed — the count must be at the very end of the line;
- `"a;b12"` is malformed (digits not preceded by a space);
- `" 12"` is malformed (empty stack); a whitespace-only line is malformed,
  only a zero-length line is blank;
- CRLF input (`"...\r\n"`) parses; exactly one trailing CR per line is
  stripped. Interior CR bytes are ordinary stack bytes.

### 3.1 Errors

The first malformed line aborts the whole parse. Every error message starts
with `profiling: line N: ` where `N` is the 1-based physical line number
(blank lines included), followed by exactly one of:

| Suffix | Condition |
|---|---|
| `missing count` | the line does not end in an ASCII digit run |
| `missing separator` | the trailing digit run is not preceded by an ASCII space |
| `empty stack` | only spaces precede the count (no stack text) |
| `count out of range` | the digit run does not fit a signed 64-bit `Int` |

Examples: `Err("profiling: line 3: missing count")` for input
`"a 1\n\nbogus\n"`.

## 4. Functions

`prof_parse(text)` -> `Result[ProfData, Str]`
: Parse per section 3 into a table with entries in file order (duplicates are
  kept as separate entries). `Ok(empty table)` for the empty string. First
  malformed line yields `Err` per section 3.1. Complexity: O(text length).

`prof_total(data)` -> `Int`
: Sum of every count (duplicates each contribute). Empty table -> `0`.
  Complexity: O(entries).

`prof_stack_count(data)` -> `Int`
: `stacks.len()`: number of folded entries (lines), not frames. Complexity: O(1).

`prof_count_for(data, stack)` -> `Int`
: Count of the first entry whose stack text is byte-equal (str_compare) to
  `stack`; `0` when absent. On unmerged duplicates the first match wins;
  combine with `prof_merge_same` first to get the summed count.
  Complexity: O(entries).

`prof_merge_same(data)` -> `ProfData`
: New table where byte-equal stacks are merged into one entry positioned at
  the first occurrence; counts add. Distinct stacks keep first-seen order.
  Empty input -> empty table. Complexity: O(entries * distinct stacks).

`prof_leaf(data)` -> `Vec[Str]`
: Distinct leaf (innermost) frame names in first-seen order. The leaf of a
  stack is the text after the last `;`; a stack without `;` is its own leaf.
  An empty stack (only constructible by hand-building `ProfData`) has leaf
  `""`. Empty input -> empty vector. Complexity: O(entries * distinct leaves).

`prof_leaf_totals(data)` -> `ProfData`
: New table with one entry per distinct leaf, in first-seen order, where
  `stacks[i]` is the leaf NAME (not a full stack) and `counts[i]` is the sum
  of the counts of all entries with that leaf. Duplicates collapse as in
  `prof_merge_same`. Complexity: O(entries * distinct leaves).

`prof_top(data, k)` -> `Vec[Str]`
: Re-formatted `"<stack> <count>"` lines (folded format) for the `k`
  heaviest entries, count descending; equal counts keep first-seen order
  (stable). `k` is clamped: `k <= 0` -> no lines, `k >= prof_stack_count` ->
  every entry. Input is ranked as-is (not merged). Complexity:
  O(entries^2) worst case (stable insertion sort); the result holds
  min(k, entries) lines.

`prof_collapse_depth(data, depth)` -> `ProfData`
: New table with every stack truncated to its last `depth` frames (leading
  frames dropped); counts are unchanged. Frames are `;`-separated segments.
  `depth < 1` -> empty table (documented choice: no "leaves only" mode for
  depth 0; use `depth = 1` for that). `depth >=` a stack's frame count keeps
  it unchanged. Duplicates are preserved as separate entries (not merged).
  Complexity: O(entries * stack length).

## 5. Test plan

`tests/test_conformance.xi` (`module profiling_tests`) runs 26 checks; the
suite passes when all print `[PASS]` and `main` returns 0.

| # | Check | Pins |
|---|---|---|
| t1 | parse one folded line | stack text + count, LF-terminated |
| t2 | multi-line input | file order kept, last line may lack LF |
| t3 | separator spacing | 2+ spaces equivalent, count `0` valid |
| t4 | blank lines | skipped, not entries; `stack_count` unaffected |
| t5 | CRLF / lone CR | CRLF parses, one trailing CR stripped, stack has no CR |
| t6 | empty input | `Ok` empty; total/count_for/merge/leaf/top/collapse all empty |
| t7 | missing count | malformed + exact message `line 1: missing count` |
| t8 | missing separator | `a;b12` and TAB case -> `line 1: missing separator` |
| t9 | empty stack | `" 12"`, `"     7"` -> `line 1: empty stack` |
| t10 | count overflow | 20-digit count rejected; `INT_MAX` accepted, `INT_MAX+1` not |
| t11 | line numbering | blanks advance the counter: `line 3` cases |
| t12 | trailing whitespace | `"a 1 "`, `"a 1\t"`, `" "` -> `missing count` |
| t13 | total / stack_count | sums with and without duplicates, zero count |
| t14 | count_for | present, absent, empty needle, first match on duplicates |
| t15 | merge_same | duplicates summed, first-seen order |
| t16 | merge_same no-op | distinct stack order and counts unchanged; empty stays empty |
| t17 | prof_leaf | distinct leaves, first-seen order |
| t18 | leaf_totals | per-leaf sums pinned, first-seen order |
| t19 | single-frame stacks | stack is its own leaf; leaf totals |
| t20 | prof_top ordering | count desc; ties c (3) before d (3) after a 9 |
| t21 | prof_top clamp | `k=99` all, `k=0`/`k=-1` none, `k=1` heaviest |
| t22 | prof_top lines | `"stack count"` format from parsed input; empty input |
| t23 | collapse depth 1 | leaf frame only, counts preserved |
| t24 | collapse depth 2/deep | last N frames; `depth >= frames` unchanged |
| t25 | collapse depth < 1 | `0`, `-3`, empty input -> empty table |
| t26 | collapse duplicates | equal collapsed stacks stay separate entries |

## 6. Out of scope

- Raw binary profiles (`perf.data`, DTrace, pprof protobuf).
- Flamegraph/differential-flamegraph rendering or SVG output.
- Frame normalization (addresses, offsets, inlining, module paths).
- Multi-frame-precision stack traces: frames must already be collapsed and
  `;`-joined; space-joined traces are not accepted (section 3).
