# xiom.profiling

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** folded-stack sampling profile analysis: parse `perf`-style folded
> text, aggregate leaves, rank the heaviest stacks, collapse stacks by depth.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.compare` and `xiom.convert`). Tests additionally use
> `xiom.test` and `xiom.io`.

## Scope

`xiom.profiling` is a dependency-light toolbox for the text side of sampling
profilers. It reads the *folded* format that `perf script |
stackcollapse-perf.pl` (and friends) produce -- one line per unique stack,
`"<stack> <count>"` -- into a table, and answers the usual questions without
any rendering:

- how many samples and how many unique stacks were captured,
- what a specific stack's count is,
- which stacks are duplicates and how to merge them,
- which leaf frames dominate (and their totals),
- which `k` stacks are the heaviest,
- what the profile looks like collapsed to the last `depth` frames.

Everything is byte-exact: stacks are opaque text to this module, frames are
split only on `;`, and no normalization (trimming, case folding, address
stripping) happens. See `SPEC.md` for the grammar, aggregation rules and the
test plan.

## Folded format

```
main;work;parse 120
main;work;write 15
main;idle 3
```

- one entry per line: the stack text, one or more spaces, then the trailing
  decimal count;
- the stack is a `;`-separated frame list with the **leaf last**;
- LF line endings; a single trailing CR per line is stripped (CRLF works);
- blank lines are skipped; any other malformed line aborts the parse with
  `Err("profiling: line N: ...")`.

Space-joined stack traces are **not** accepted: frames must be joined with
`;`. See `SPEC.md` section 3 for the exact grammar.

## API

| Function | Returns | Description |
|---|---|---|
| `prof_parse(text)` | `Result[ProfData, Str]` | Parse folded text into a table. `Err("profiling: line N: ...")` on the first malformed line; blank lines are skipped and still count for `N`. |
| `prof_total(data)` | `Int` | Sum of all entry counts (duplicates included). |
| `prof_stack_count(data)` | `Int` | Number of entries (lines), not frames. |
| `prof_count_for(data, stack)` | `Int` | Count of exactly `stack` (byte-exact); `0` when absent; first match on unmerged duplicates. |
| `prof_merge_same(data)` | `ProfData` | Sum duplicate stacks, keeping first-seen order. |
| `prof_leaf(data)` | `Vec[Str]` | Distinct leaf (last) frame names, first-seen order. |
| `prof_leaf_totals(data)` | `ProfData` | One entry per distinct leaf, count summed; `stacks` hold leaf names. |
| `prof_top(data, k)` | `Vec[Str]` | Up to `k` `"<stack> <count>"` lines, count descending, ties first-seen; `k <= 0` yields no lines, `k` beyond the size yields all. |
| `prof_collapse_depth(data, depth)` | `ProfData` | Truncate each stack to its last `depth` frames; `depth < 1` yields an empty table; duplicates are not merged. |

## Usage

```xi
use xiom.profiling;
use xiom.io;

fn main() -> Int {
  let text = "main;work;parse 120\nmain;work;write 15\nmain;idle 3\n";
  let parsed = prof_parse(text);
  match parsed {
    Ok(d) => {
      io.println("samples: " + prof_total(&d));        // 138
      io.println("stacks: " + prof_stack_count(&d));   // 3
      let leaves = prof_leaf(&d);                      // ["parse", "write", "idle"]
      let top = prof_top(&d, 2);                       // ["main;work;parse 120", "main;work;write 15"]
      let depth1 = prof_collapse_depth(&d, 1);         // stacks "parse", "write", "idle"
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.profiling
```

Expected tail: 26 `[PASS]` lines, `xiom.profiling: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Folded text only.** Input must be the collapsed `"<stack> <count>"`
  format; raw `perf.data`, binary stacks and JSON are out of scope.
- **No flamegraph rendering.** The module aggregates and ranks; producing SVG
  or any visual artifact is left to a renderer built on these tables.
- **Frames are `;`-separated.** A space-joined stack trace is not valid input:
  the parser takes everything before the final space-run plus integer as the
  stack, so spaces may appear *inside* stack text (perf C++ symbols do), but
  frames are split only on `;` and never validated.
- **No frame normalization.** Addresses, module paths, argument lists and
  whitespace are preserved byte-for-byte.
- **Single trailing CR only.** CRLF input works and one trailing CR per line
  is stripped; interior CR bytes stay verbatim, and whitespace-only lines
  (spaces/tabs) are malformed rather than blank.
- **Counts fit a signed 64-bit `Int`.** A count that would overflow aborts
  the parse; counts are non-negative (a sign makes the line malformed).
- **Duplicates are kept** by `prof_parse`; merge explicitly with
  `prof_merge_same` (or aggregate with `prof_leaf_totals`).

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
